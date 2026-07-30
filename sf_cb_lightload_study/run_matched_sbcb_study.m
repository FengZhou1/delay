function experiment = run_matched_sbcb_study(base_result_dir,overrides)
%RUN_MATCHED_SBCB_STUDY Run SB-CB on the verified SF-CB arrival conditions.
%   The saved SF-CB condition table is not recomputed. Arrival traces are
%   deterministically regenerated from its saved configuration and checked
%   packet-for-packet against the saved baseline packet table.

    if nargin < 1 || isempty(base_result_dir)
        error('run_matched_sbcb_study:MissingBase', ...
            'A verified SF-CB result directory is required.');
    end
    if nargin < 2
        overrides = struct();
    end
    base_result_dir = char(base_result_dir);
    required_files = {'config.mat','condition_summary.csv', ...
        'packet_delays.csv','manifest.json'};
    for i = 1:numel(required_files)
        if ~exist(fullfile(base_result_dir,required_files{i}),'file')
            error('run_matched_sbcb_study:MissingBaseFile', ...
                'Missing %s in %s.',required_files{i},base_result_dir);
        end
    end
    base_manifest = jsondecode(fileread( ...
        fullfile(base_result_dir,'manifest.json')));
    if ~strcmpi(base_manifest.status,'completed') || ...
            ~strcmpi(base_manifest.verification_status,'VERIFIED')
        error('run_matched_sbcb_study:UnverifiedBase', ...
            'The base SF-CB result is not completed and VERIFIED.');
    end

    loaded = load(fullfile(base_result_dir,'config.mat'),'cfg');
    cfg = apply_overrides(loaded.cfg,overrides);
    cfg = validate_experiment_config(cfg);
    tune_cfg = phase_cfg_local(cfg,'tune');
    eval_cfg = phase_cfg_local(cfg,'eval');
    sf_condition_table = readtable(fullfile(base_result_dir, ...
        'condition_summary.csv'),'TextType','string');
    keep_sf = ismember(double(sf_condition_table.lambda_per_node), ...
        double(cfg.lambda_values)) & ...
        ismember(double(sf_condition_table.M),double(cfg.M_values));
    sf_condition_table = sf_condition_table(keep_sf,:);
    saved_packet_table = readtable(fullfile(base_result_dir, ...
        'packet_delays.csv'),'TextType','string');

    if isfield(overrides,'output_dir') && ~isempty(overrides.output_dir)
        output_dir = char(overrides.output_dir);
    else
        stamp = char(datetime('now','Format','yyyyMMdd_HHmmss'));
        output_dir = fullfile(base_result_dir,['matched_sbcb_' stamp]);
    end
    if exist(output_dir,'dir')
        error('run_matched_sbcb_study:OutputExists', ...
            'Output directory already exists: %s',output_dir);
    end
    mkdir(output_dir);
    verification_dir = fullfile(output_dir,'verification');
    mkdir(verification_dir);
    save(fullfile(output_dir,'config.mat'),'cfg','base_result_dir');

    scenario = prepare_scenario_v2(eval_cfg,eval_cfg.topology_seed);
    save(fullfile(output_dir,'scenario.mat'),'scenario','-v7.3');

    tune_traces = build_trace_cache_local(tune_cfg,cfg.lambda_values, ...
        cfg.n_tune_runs,0);
    validation_traces = build_trace_cache_local(eval_cfg, ...
        cfg.lambda_values,cfg.n_validation_runs,5000000);
    eval_traces = build_trace_cache_local(eval_cfg,cfg.lambda_values, ...
        cfg.n_eval_runs,10000000);
    trace_report = verify_saved_eval_traces(saved_packet_table, ...
        eval_traces,eval_cfg,cfg.lambda_values);
    writetable(trace_report,fullfile(verification_dir, ...
        'arrival_trace_match.csv'));
    if ~all(trace_report.passed)
        error('run_matched_sbcb_study:TraceMismatch', ...
            'Regenerated evaluation arrivals do not match the SF-CB run.');
    end

    q_rows = struct([]);
    validation_rows = struct([]);
    run_rows = struct([]);
    condition_rows = struct([]);
    packet_tables = cell(0,1);
    stress_cache = containers.Map('KeyType','char','ValueType','any');
    q_index = 0;
    validation_index = 0;
    run_index = 0;
    condition_index = 0;
    packet_index = 0;
    total = numel(cfg.lambda_values)*numel(cfg.M_values);
    progress = 0;
    started = tic;

    fprintf('\n=== Matched SB-CB light-load study ===\n');
    fprintf('Base SF-CB result: %s\n',base_result_dir);
    fprintf('Output: %s\n',output_dir);
    for lambda_index = 1:numel(cfg.lambda_values)
        lambda = cfg.lambda_values(lambda_index);
        for m_index = 1:numel(cfg.M_values)
            M = cfg.M_values(m_index);
            progress = progress+1;
            fprintf('[%d/%d] sb_cb lambda=%g M=%g\n', ...
                progress,total,lambda,M);

            coarse = evaluate_grid_local(M,cfg.q_coarse,'coarse', ...
                tune_traces(lambda_index,:),scenario,tune_cfg,cfg);
            coarse_best = choose_best_q_local(coarse,cfg);
            fine_q = local_fine_grid_local(cfg.q_coarse, ...
                coarse_best,cfg.q_fine_points);
            fine_q = remove_existing_local(fine_q,[coarse.q]);
            if isempty(fine_q)
                fine = struct([]);
            else
                fine = evaluate_grid_local(M,fine_q,'fine', ...
                    tune_traces(lambda_index,:),scenario,tune_cfg,cfg);
            end
            grid = [coarse(:);fine(:)];
            [~,q_order] = sort([grid.q]);
            grid = grid(q_order);
            [~,order] = sort([grid.q]);
            grid = grid(order);
            initial_index = choose_best_q_local(grid,cfg);
            [best_q,validation,stress_cache] = ...
                validate_candidates_local(M,grid,initial_index, ...
                validation_traces(lambda_index,:),scenario,eval_cfg,cfg, ...
                stress_cache);

            for i = 1:numel(validation)
                validation_index = validation_index+1;
                row = validation(i);
                row.variant = "sb_cb";
                row.lambda_per_node = lambda;
                row.M = M;
                if isempty(validation_rows)
                    validation_rows = row;
                else
                    validation_rows(validation_index) = row; %#ok<AGROW>
                end
            end
            for i = 1:numel(grid)
                q_index = q_index+1;
                row = rmfield(grid(i),'run_metrics');
                row.variant = "sb_cb";
                row.lambda_per_node = lambda;
                row.M = M;
                row.selected = abs(row.q-best_q) <= ...
                    16*eps(max(1,abs(best_q)));
                if isempty(q_rows)
                    q_rows = row;
                else
                    q_rows(q_index) = row; %#ok<AGROW>
                end
            end

            metrics = repmat(empty_metric_local(),cfg.n_eval_runs,1);
            for run = 1:cfg.n_eval_runs
                seed = protocol_seed_local(cfg,M,run,10000000);
                result = simulate_sb_cb_v2(eval_traces{lambda_index,run}, ...
                    scenario,eval_cfg,M,best_q,seed);
                metrics(run) = extract_metrics_local(result,eval_cfg);
                run_index = run_index+1;
                row = metric_run_row_local(metrics(run),lambda,M, ...
                    best_q,run,result);
                if isempty(run_rows)
                    run_rows = row;
                else
                    run_rows(run_index) = row; %#ok<AGROW>
                end
                packet_index = packet_index+1;
                packet_tables{packet_index,1} = packet_table_local( ... %#ok<AGROW>
                    result,lambda,M,best_q,run);
            end

            condition_index = condition_index+1;
            row = summarize_condition_local(metrics,lambda,M,best_q,cfg);
            if isempty(condition_rows)
                condition_rows = row;
            else
                condition_rows(condition_index) = row; %#ok<AGROW>
            end
            fprintf(['  best q=%.5g, mean total=%.3f ms, ' ...
                'completion=%.4f\n'],best_q, ...
                row.mean_total_delay_us/1000,row.completion_ratio_mean);
        end
    end

    sb_condition_table = struct2table(condition_rows);
    sb_run_table = struct2table(run_rows);
    sb_q_scan_table = struct2table(q_rows);
    sb_q_validation_table = struct2table(validation_rows);
    sb_packet_table = vertcat(packet_tables{:});
    combined_condition_table = [sf_condition_table;sb_condition_table];

    writetable(sb_condition_table,fullfile(output_dir, ...
        'sb_cb_condition_summary.csv'));
    writetable(sb_run_table,fullfile(output_dir,'sb_cb_run_summary.csv'));
    writetable(sb_q_scan_table,fullfile(output_dir,'sb_cb_q_scan.csv'));
    writetable(sb_q_validation_table,fullfile(output_dir, ...
        'sb_cb_q_validation.csv'));
    writetable(sb_packet_table,fullfile(output_dir, ...
        'sb_cb_packet_delays.csv'));
    writetable(combined_condition_table,fullfile(output_dir, ...
        'condition_summary_with_sb_cb.csv'));

    figure_output = plot_sfcb_sbcb_matched_results( ...
        combined_condition_table,output_dir);
    save(fullfile(output_dir,'matched_study_results.mat'), ...
        'cfg','base_result_dir','sb_condition_table','sb_run_table', ...
        'sb_q_scan_table','sb_q_validation_table','sb_packet_table', ...
        'combined_condition_table','trace_report','-v7.3');

    manifest = struct();
    manifest.schema_version = '1.0';
    manifest.study_type = 'matched_sb_cb_lightload_comparison';
    manifest.status = 'completed';
    manifest.verification_status = 'VERIFIED';
    manifest.created_at = char(datetime('now', ...
        'Format','yyyy-MM-dd HH:mm:ss'));
    manifest.elapsed_s = toc(started);
    manifest.base_result_dir = base_result_dir;
    manifest.n_sb_cb_conditions = height(sb_condition_table);
    manifest.n_combined_conditions = height(combined_condition_table);
    manifest.output_dir = output_dir;
    manifest.figure_png = figure_output.png_path;
    manifest.figure_pdf = figure_output.pdf_path;
    write_json_local(fullfile(output_dir,'manifest.json'),manifest);

    experiment = struct('output_dir',output_dir,'config',cfg, ...
        'sb_cb_condition_summary',sb_condition_table, ...
        'sb_cb_run_summary',sb_run_table, ...
        'sb_cb_q_scan',sb_q_scan_table, ...
        'sb_cb_q_validation',sb_q_validation_table, ...
        'sb_cb_packet_delays',sb_packet_table, ...
        'combined_condition_summary',combined_condition_table, ...
        'trace_verification',trace_report, ...
        'figure',figure_output,'manifest',manifest);
    fprintf('=== completed in %.1f s ===\n',manifest.elapsed_s);
end

function cfg = apply_overrides(cfg,overrides)
    names = fieldnames(overrides);
    for i = 1:numel(names)
        if ~strcmp(names{i},'output_dir')
            cfg.(names{i}) = overrides.(names{i});
        end
    end
    cfg.arrival_end_us = cfg.warmup_us+cfg.measure_us;
    cfg.sim_hard_end_us = cfg.arrival_end_us+cfg.drain_max_us;
end

function value = phase_cfg_local(cfg,phase)
    value = cfg;
    if strcmp(phase,'tune')
        value.warmup_us = cfg.tune_warmup_us;
        value.measure_us = cfg.tune_measure_us;
        value.drain_max_us = cfg.tune_drain_max_us;
    elseif ~strcmp(phase,'eval')
        error('run_matched_sbcb_study:BadPhase','Unknown phase.');
    end
    value.arrival_end_us = value.warmup_us+value.measure_us;
    value.sim_hard_end_us = value.arrival_end_us+value.drain_max_us;
    value = validate_experiment_config(value);
end

function traces = build_trace_cache_local(cfg,lambdas,n_runs,seed_offset)
    traces = cell(numel(lambdas),n_runs);
    for lambda_index = 1:numel(lambdas)
        for run = 1:n_runs
            seed = bounded_seed_local(cfg.traffic_seed_base+seed_offset+ ...
                round(lambdas(lambda_index)*1e6)+run);
            traces{lambda_index,run} = generate_arrival_trace( ...
                lambdas(lambda_index),cfg,seed);
        end
    end
end

function report = verify_saved_eval_traces(saved,traces,cfg,lambdas)
    rows = struct([]);
    index = 0;
    for lambda_index = 1:numel(lambdas)
        for run = 1:size(traces,2)
            trace = traces{lambda_index,run};
            cohort = trace.times_us>=cfg.warmup_us & ...
                trace.times_us<cfg.arrival_end_us;
            packet_ids = find(cohort);
            keep = saved.variant=="baseline" & saved.M==1 & ...
                saved.lambda_per_node==lambdas(lambda_index) & ...
                saved.run==run;
            observed = sortrows(saved(keep,:),{'packet_id'});
            passed = height(observed)==numel(packet_ids);
            if passed
                passed = isequal(double(observed.packet_id),packet_ids) && ...
                    isequal(double(observed.node_id), ...
                    double(trace.node_id(cohort))) && ...
                    isequal(double(observed.arrival_us), ...
                    double(trace.times_us(cohort)));
            end
            index = index+1;
            row = struct('lambda_per_node',lambdas(lambda_index), ...
                'run',run,'n_packets',numel(packet_ids), ...
                'passed',passed);
            if isempty(rows)
                rows = row;
            else
                rows(index) = row; %#ok<AGROW>
            end
        end
    end
    report = struct2table(rows);
end

function grid = evaluate_grid_local(M,q_values,stage,traces,scenario, ...
        sim_cfg,cfg)
    q_values = unique(double(q_values(:).'));
    grid = repmat(empty_grid_local(),numel(q_values),1);
    for q_index = 1:numel(q_values)
        metrics = repmat(empty_metric_local(),numel(traces),1);
        for run = 1:numel(traces)
            seed = protocol_seed_local(cfg,M,run,0);
            result = simulate_sb_cb_v2(traces{run},scenario,sim_cfg,M, ...
                q_values(q_index),seed);
            metrics(run) = extract_metrics_local(result,sim_cfg);
        end
        total = [metrics.mean_total_delay_us];
        queue = [metrics.mean_queue_delay_us];
        access = [metrics.mean_access_delay_us];
        completion = [metrics.completion_ratio];
        finite_total = total(isfinite(total));
        if isempty(finite_total)
            mean_total = inf;
            se_total = inf;
        else
            mean_total = mean(finite_total);
            se_total = standard_error_local(finite_total);
        end
        grid(q_index) = struct('q',q_values(q_index), ...
            'stage',string(stage),'n_runs',numel(metrics), ...
            'mean_total_delay_us',mean_total, ...
            'se_total_delay_us',se_total, ...
            'mean_queue_delay_us',mean(queue,'omitnan'), ...
            'mean_access_delay_us',mean(access,'omitnan'), ...
            'completion_ratio_mean',mean(completion,'omitnan'), ...
            'min_completion_ratio',min(completion), ...
            'run_metrics',{metrics});
    end
end

function index = choose_best_q_local(grid,cfg)
    q = [grid.q];
    delay = [grid.mean_total_delay_us];
    self_stable = isfinite(delay) & ...
        [grid.completion_ratio_mean]>=cfg.min_tune_completion_ratio & ...
        [grid.min_completion_ratio]>=cfg.min_tune_completion_ratio & ...
        q<1-1e-12;
    neighbor_stable = false(size(self_stable));
    for i = 1:numel(grid)
        lo = max(1,i-1);
        hi = min(numel(grid),i+1);
        neighbor_stable(i) = self_stable(i) && all(self_stable(lo:hi));
    end
    if any(neighbor_stable)
        candidates = find(neighbor_stable);
    elseif any(self_stable)
        candidates = find(self_stable);
    else
        maximum = max([grid.min_completion_ratio]);
        candidates = find([grid.min_completion_ratio]>= ...
            maximum-1e-12 & isfinite(delay) & q<1-1e-12);
    end
    if isempty(candidates)
        error('run_matched_sbcb_study:NoFiniteQ', ...
            'No finite nonabsorbing SB-CB q candidate.');
    end
    [minimum_delay,local] = min(delay(candidates));
    provisional = candidates(local);
    tolerance = max(grid(provisional).se_total_delay_us, ...
        cfg.q_delay_tie_fraction*minimum_delay);
    near = candidates(delay(candidates)<=minimum_delay+tolerance);
    [~,local] = min(q(near));
    index = near(local);
end

function [best_q,rows,cache] = validate_candidates_local(M,grid, ...
        initial_index,traces,scenario,sim_cfg,cfg,cache)
    q = [grid.q];
    eligible = isfinite([grid.mean_total_delay_us]) & ...
        [grid.min_completion_ratio]>=cfg.min_tune_completion_ratio & ...
        q<1-1e-12;
    initial_q = q(initial_index);
    lower = sort(q(eligible & q<initial_q),'descend');
    higher = sort(q(eligible & q>initial_q),'ascend');
    candidates = unique([initial_q lower higher],'stable');
    rows = struct([]);
    best_q = initial_q;
    best_min_completion = -Inf;
    best_delay = Inf;

    for candidate_index = 1:numel(candidates)
        candidate_q = candidates(candidate_index);
        [stress_pass,stress_worst_us,cache] = stress_recovery_local( ...
            M,candidate_q,scenario,sim_cfg,cfg,cache);
        if ~stress_pass
            row = validation_row_local(candidate_index,candidate_q,0, ...
                0,0,Inf,true,false,stress_worst_us,false);
        else
            metrics = repmat(empty_metric_local(),numel(traces),1);
            for run = 1:numel(traces)
                seed = protocol_seed_local(cfg,M,run,5000000);
                result = simulate_sb_cb_v2(traces{run},scenario, ...
                    sim_cfg,M,candidate_q,seed);
                metrics(run) = extract_metrics_local(result,sim_cfg);
            end
            completion = [metrics.completion_ratio];
            delay = [metrics.mean_total_delay_us];
            conservation = [metrics.packet_conservation_ok];
            minimum_completion = min(completion);
            mean_completion = mean(completion);
            mean_delay = mean(delay,'omitnan');
            passed = minimum_completion>= ...
                cfg.min_validation_completion_ratio && ...
                all(conservation) && stress_pass;
            row = validation_row_local(candidate_index,candidate_q, ...
                numel(metrics),minimum_completion,mean_completion, ...
                mean_delay,all(conservation),stress_pass, ...
                stress_worst_us,passed);
            if minimum_completion>best_min_completion || ...
                    (minimum_completion==best_min_completion && ...
                    mean_delay<best_delay)
                best_q = candidate_q;
                best_min_completion = minimum_completion;
                best_delay = mean_delay;
            end
        end
        if isempty(rows)
            rows = row;
        else
            rows(candidate_index) = row; %#ok<AGROW>
        end
        if row.passed
            best_q = candidate_q;
            return;
        end
    end
end

function row = validation_row_local(rank,q,n_runs,min_completion, ...
        mean_completion,mean_delay,conservation,stress_pass, ...
        stress_worst_us,passed)
    row = struct('candidate_rank',rank,'q',q,'n_runs',n_runs, ...
        'min_completion_ratio',min_completion, ...
        'mean_completion_ratio',mean_completion, ...
        'mean_total_delay_us',mean_delay, ...
        'all_packet_conservation_ok',conservation, ...
        'stress_recovery_passed',stress_pass, ...
        'stress_worst_completion_us',stress_worst_us, ...
        'passed',passed);
end

function [passed,worst_completion_us,cache] = stress_recovery_local( ...
        M,q,scenario,sim_cfg,cfg,cache)
    key = sprintf('M%.12g_q%.17g',M,q);
    if isKey(cache,key)
        cached = cache(key);
        passed = cached.passed;
        worst_completion_us = cached.worst_completion_us;
        return;
    end
    stress_cfg = sim_cfg;
    stress_cfg.warmup_us = 0;
    stress_cfg.measure_us = cfg.q_stress_horizon_us;
    stress_cfg.drain_max_us = 0;
    stress_cfg.arrival_end_us = cfg.q_stress_horizon_us;
    stress_cfg.sim_hard_end_us = cfg.q_stress_horizon_us;
    stress_cfg.stability_rate_tolerance = 1;
    stress_cfg.stability_censor_tolerance = 1;
    stress_cfg.stability_require_slope = false;
    stress_cfg = validate_experiment_config(stress_cfg);
    n_stress = min(cfg.q_stress_nodes,stress_cfg.n_nodes);
    trace = make_manual_arrival_trace(zeros(n_stress,1), ...
        (1:n_stress).',stress_cfg);
    passed = true;
    worst_completion_us = 0;
    for run = 1:cfg.q_stress_runs
        seed = protocol_seed_local(cfg,M,run,6000000);
        result = simulate_sb_cb_v2(trace,scenario,stress_cfg,M,q,seed);
        completion = result.packet_log.completion_us;
        if any(~isfinite(completion))
            passed = false;
            worst_completion_us = Inf;
            break;
        end
        worst_completion_us = max(worst_completion_us,max(completion));
    end
    cache(key) = struct('passed',passed, ...
        'worst_completion_us',worst_completion_us);
end

function q = local_fine_grid_local(coarse,best_index,n_points)
    coarse = unique(double(coarse(:).'));
    if best_index<=1
        lo = max(1e-4,coarse(1)/2);
        hi = coarse(2);
    elseif best_index>=numel(coarse)
        lo = coarse(end-1);
        hi = 1;
    else
        lo = coarse(best_index-1);
        hi = coarse(best_index+1);
    end
    q = unique(linspace(lo,hi,n_points));
end

function values = remove_existing_local(values,existing)
    keep = true(size(values));
    for i = 1:numel(values)
        keep(i) = ~any(abs(values(i)-existing)<= ...
            16*eps(max(1,abs(values(i)))));
    end
    values = values(keep);
end

function metric = extract_metrics_local(result,cfg)
    pkt = result.packet_log;
    cohort = pkt.arrival_us>=cfg.warmup_us & ...
        pkt.arrival_us<cfg.arrival_end_us;
    completed = cohort & isfinite(pkt.completion_us);
    metric = empty_metric_local();
    metric.n_arrived = sum(cohort);
    metric.n_completed = sum(completed);
    metric.n_censored = metric.n_arrived-metric.n_completed;
    metric.completion_ratio = metric.n_completed/max(1,metric.n_arrived);
    metric.mean_total_delay_us = ...
        mean(pkt.total_delay_us(completed),'omitnan');
    metric.mean_queue_delay_us = ...
        mean(pkt.queue_delay_us(completed),'omitnan');
    metric.mean_access_delay_us = ...
        mean(pkt.access_delay_us(completed),'omitnan');
    metric.p95_total_delay_us = ...
        percentile_or_nan_local(pkt.total_delay_us(completed),95);
    metric.mean_attempts = mean(pkt.attempts(completed),'omitnan');
    metric.final_backlog = result.summary.final_backlog;
    metric.stable = result.summary.stable;
    metric.packet_conservation_ok = result.summary.packet_conservation_ok;
end

function row = metric_run_row_local(metric,lambda,M,q,run,result)
    row = metric;
    row.variant = "sb_cb";
    row.lambda_per_node = lambda;
    row.M = M;
    row.Tp_us = result.summary.Tp_us;
    row.q = q;
    row.run = run;
    row.collision_channel_time_us = ...
        result.summary.collision_channel_time_us_total;
    row.mean_batch_size = 1;
end

function row = summarize_condition_local(metrics,lambda,M,q,cfg)
    timing = mmw_timing_config(cfg);
    total = [metrics.mean_total_delay_us];
    queue = [metrics.mean_queue_delay_us];
    access = [metrics.mean_access_delay_us];
    completion = [metrics.completion_ratio];
    row = struct();
    row.variant = "sb_cb";
    row.lambda_per_node = lambda;
    row.M = M;
    row.Tp_us = timing.CONN_SLOT_US*M;
    row.best_q = q;
    row.n_eval_runs = numel(metrics);
    row.mean_total_delay_us = mean(total,'omitnan');
    row.ci95_total_delay_us = ci95_local(total);
    row.mean_queue_delay_us = mean(queue,'omitnan');
    row.ci95_queue_delay_us = ci95_local(queue);
    row.mean_access_delay_us = mean(access,'omitnan');
    row.ci95_access_delay_us = ci95_local(access);
    row.p95_total_delay_us_mean = ...
        mean([metrics.p95_total_delay_us],'omitnan');
    row.completion_ratio_mean = mean(completion,'omitnan');
    row.stable_fraction = mean([metrics.stable]);
    row.final_backlog_mean = mean([metrics.final_backlog]);
    row.mean_attempts = mean([metrics.mean_attempts],'omitnan');
    row.delay_identity_error_us = abs(row.mean_total_delay_us- ...
        row.mean_queue_delay_us-row.mean_access_delay_us);
end

function value = packet_table_local(result,lambda,M,q,run)
    pkt = result.packet_log;
    keep = pkt.in_measurement_cohort;
    packet_id = find(keep);
    n = numel(packet_id);
    value = table(repmat("sb_cb",n,1),repmat(lambda,n,1), ...
        repmat(M,n,1),repmat(q,n,1),repmat(run,n,1), ...
        packet_id,pkt.node_id(keep),pkt.arrival_us(keep), ...
        pkt.hol_us(keep),pkt.first_attempt_us(keep), ...
        pkt.completion_us(keep),pkt.total_delay_us(keep), ...
        pkt.queue_delay_us(keep),pkt.access_delay_us(keep), ...
        pkt.attempts(keep),logical(pkt.status(keep)), ...
        'VariableNames',{'variant','lambda_per_node','M','q','run', ...
        'packet_id','node_id','arrival_us','hol_us','first_attempt_us', ...
        'completion_us','total_delay_us','queue_delay_us', ...
        'access_delay_us','attempts','completed'});
end

function value = protocol_seed_local(cfg,M,run,offset)
    variant_index = 5;
    value = bounded_seed_local(cfg.protocol_seed_base+offset+ ...
        variant_index*1000000+M*10000+run);
end

function value = bounded_seed_local(raw)
    value = mod(round(double(raw)),2^31-2)+1;
end

function value = standard_error_local(x)
    x = x(isfinite(x));
    if numel(x)<=1
        value = 0;
    else
        value = std(x,0)/sqrt(numel(x));
    end
end

function value = ci95_local(x)
    value = 1.96*standard_error_local(x);
end

function value = percentile_or_nan_local(x,p)
    if isempty(x)
        value = NaN;
    else
        value = prctile(x,p);
    end
end

function value = empty_metric_local()
    value = struct('n_arrived',0,'n_completed',0,'n_censored',0, ...
        'completion_ratio',0,'mean_total_delay_us',NaN, ...
        'mean_queue_delay_us',NaN,'mean_access_delay_us',NaN, ...
        'p95_total_delay_us',NaN,'mean_attempts',NaN, ...
        'final_backlog',0,'stable',false, ...
        'packet_conservation_ok',false);
end

function value = empty_grid_local()
    value = struct('q',NaN,'stage',"",'n_runs',0, ...
        'mean_total_delay_us',Inf,'se_total_delay_us',Inf, ...
        'mean_queue_delay_us',NaN,'mean_access_delay_us',NaN, ...
        'completion_ratio_mean',0,'min_completion_ratio',0, ...
        'run_metrics',repmat(empty_metric_local(),0,1));
end

function write_json_local(path,value)
    fid = fopen(path,'w');
    if fid<0
        error('run_matched_sbcb_study:ManifestWrite', ...
            'Cannot open %s.',path);
    end
    cleanup = onCleanup(@() fclose(fid));
    fwrite(fid,jsonencode(value,'PrettyPrint',true),'char');
    clear cleanup;
end
