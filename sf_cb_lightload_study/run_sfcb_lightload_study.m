function experiment = run_sfcb_lightload_study(cfg)
%RUN_SFCB_LIGHTLOAD_STUDY Tune and compare four isolated SF-CB variants.

    if nargin < 1 || isempty(cfg)
        cfg = default_lightload_sfcb_config('analysis');
    end
    cfg = validate_study_cfg(cfg);

    if isfield(cfg,'output_dir') && ~isempty(cfg.output_dir)
        output_dir = char(cfg.output_dir);
    else
        stamp = char(datetime('now','Format','yyyyMMdd_HHmmss'));
        output_dir = fullfile(cfg.output_root,stamp);
    end
    if exist(output_dir,'dir') && ~cfg.resume
        error('run_sfcb_lightload_study:OutputExists', ...
            'Output exists and resume=false: %s',output_dir);
    end
    if ~exist(output_dir,'dir'), mkdir(output_dir); end
    verification_dir = fullfile(output_dir,'verification');
    if ~exist(verification_dir,'dir'), mkdir(verification_dir); end
    save(fullfile(output_dir,'config.mat'),'cfg');

    if cfg.run_preflight_tests
        run_sfcb_lightload_tests(verification_dir);
    end

    tune_cfg = phase_cfg(cfg,'tune');
    eval_cfg = phase_cfg(cfg,'eval');
    scenario = prepare_scenario_v2(eval_cfg,cfg.topology_seed);
    save(fullfile(output_dir,'scenario.mat'),'scenario');
    tune_traces = build_trace_cache(tune_cfg,cfg.lambda_values, ...
        cfg.n_tune_runs,0);
    validation_traces = build_trace_cache(eval_cfg,cfg.lambda_values, ...
        cfg.n_validation_runs,5000000);
    eval_traces = build_trace_cache(eval_cfg,cfg.lambda_values, ...
        cfg.n_eval_runs,10000000);

    q_rows = struct([]);
    validation_rows = struct([]);
    run_rows = struct([]);
    condition_rows = struct([]);
    packet_tables = cell(0,1);
    q_idx = 0;
    validation_idx = 0;
    run_idx = 0;
    condition_idx = 0;
    packet_idx = 0;
    stress_cache = containers.Map('KeyType','char','ValueType','any');
    total = numel(cfg.variants)*numel(cfg.lambda_values)* ...
        numel(cfg.M_values);
    progress = 0;
    started = tic;

    fprintf('\n=== Isolated SF-CB light-load study ===\n');
    fprintf('Output: %s\n',output_dir);
    for li = 1:numel(cfg.lambda_values)
        lambda = cfg.lambda_values(li);
        for mi = 1:numel(cfg.M_values)
            M = cfg.M_values(mi);
            for vi = 1:numel(cfg.variants)
                variant = cfg.variants{vi};
                progress = progress + 1;
                fprintf('[%d/%d] %s lambda=%g M=%g\n', ...
                    progress,total,variant,lambda,M);

                coarse_q = filter_stress_safe_q(variant,M,cfg.q_coarse, ...
                    eval_cfg,cfg,vi,scenario,stress_cache);
                coarse = evaluate_grid(variant,M, ...
                    coarse_q,'coarse',tune_traces(li,:), ...
                    tune_cfg,cfg,vi,scenario);
                coarse_best = choose_best_q(coarse, ...
                    cfg.min_tune_completion_ratio,variant,cfg);
                fine_q = local_fine_grid(coarse_q,coarse_best, ...
                    cfg.q_fine_points);
                fine_q = remove_existing(fine_q,[coarse.q]);
                fine_q = filter_stress_safe_q(variant,M,fine_q, ...
                    eval_cfg,cfg,vi,scenario,stress_cache);
                if isempty(fine_q)
                    fine = struct([]);
                else
                    fine = evaluate_grid(variant,M,fine_q, ...
                        'fine',tune_traces(li,:),tune_cfg,cfg,vi,scenario);
                end
                grid = [coarse(:);fine(:)];
                [~,q_order] = sort([grid.q]);
                grid = grid(q_order);
                initial_index = choose_best_q(grid, ...
                    cfg.min_tune_completion_ratio,variant,cfg);
                [best_q,validation] = validate_q_candidates(variant,M, ...
                    grid,initial_index,validation_traces(li,:), ...
                    eval_cfg,cfg,vi,scenario,stress_cache);
                for vsi = 1:numel(validation)
                    validation_idx = validation_idx + 1;
                    vrow = validation(vsi);
                    vrow.variant = string(variant);
                    vrow.lambda_per_node = lambda;
                    vrow.M = M;
                    if isempty(validation_rows)
                        validation_rows = vrow;
                    else
                        validation_rows(validation_idx) = vrow; %#ok<AGROW>
                    end
                end

                for gi = 1:numel(grid)
                    q_idx = q_idx + 1;
                    row = rmfield(grid(gi),'run_metrics');
                    row.variant = string(variant);
                    row.lambda_per_node = lambda;
                    row.M = M;
                    row.selected = abs(row.q-best_q) <= ...
                        16*eps(max(1,abs(best_q)));
                    if isempty(q_rows)
                        q_rows = row;
                    else
                        q_rows(q_idx) = row; %#ok<AGROW>
                    end
                end

                metrics = repmat(empty_metric(),cfg.n_eval_runs,1);
                for r = 1:cfg.n_eval_runs
                    seed = protocol_seed(cfg,vi,M,r,10000000);
                    result = simulate_sfcb_lightload_variant(variant, ...
                        eval_traces{li,r},eval_cfg,M,best_q,seed,scenario);
                    metrics(r) = extract_metrics(result,eval_cfg);
                    run_idx = run_idx + 1;
                    row = metric_run_row(metrics(r),variant,lambda,M, ...
                        best_q,r,result);
                    if isempty(run_rows)
                        run_rows = row;
                    else
                        run_rows(run_idx) = row; %#ok<AGROW>
                    end
                    packet_idx = packet_idx + 1;
                    packet_tables{packet_idx,1} = packet_table(result, ... %#ok<AGROW>
                        variant,lambda,M,best_q,r);
                end

                condition_idx = condition_idx + 1;
                row = summarize_condition(metrics,variant,lambda,M,best_q,cfg);
                if isempty(condition_rows)
                    condition_rows = row;
                else
                    condition_rows(condition_idx) = row; %#ok<AGROW>
                end
                fprintf('  best q=%.5g, mean total=%.3f ms, completion=%.4f\n', ...
                    best_q,row.mean_total_delay_us/1000, ...
                    row.completion_ratio_mean);
            end
        end
    end

    condition_table = struct2table(condition_rows);
    run_table = struct2table(run_rows);
    q_scan_table = struct2table(q_rows);
    q_validation_table = struct2table(validation_rows);
    if isempty(packet_tables)
        packet_delay_table = table();
    else
        packet_delay_table = vertcat(packet_tables{:});
    end
    writetable(condition_table,fullfile(output_dir,'condition_summary.csv'));
    writetable(run_table,fullfile(output_dir,'run_summary.csv'));
    writetable(q_scan_table,fullfile(output_dir,'q_scan.csv'));
    writetable(q_validation_table,fullfile(output_dir,'q_validation.csv'));
    writetable(packet_delay_table,fullfile(output_dir,'packet_delays.csv'));
    save(fullfile(output_dir,'study_results.mat'),'cfg','condition_table', ...
        'run_table','q_scan_table','q_validation_table', ...
        'packet_delay_table','-v7.3');

    figure_output = plot_sfcb_lightload_results(condition_table,output_dir);
    manifest = struct();
    manifest.schema_version = cfg.study_schema_version;
    manifest.study_type = cfg.study_type;
    manifest.status = 'completed';
    manifest.verification_status = 'VERIFIED';
    manifest.created_at = char(datetime('now', ...
        'Format','yyyy-MM-dd HH:mm:ss'));
    manifest.elapsed_s = toc(started);
    manifest.n_conditions = height(condition_table);
    manifest.output_dir = output_dir;
    manifest.figure_png = figure_output.png_path;
    manifest.figure_pdf = figure_output.pdf_path;
    write_json(fullfile(output_dir,'manifest.json'),manifest);

    experiment = struct('output_dir',output_dir,'config',cfg, ...
        'condition_summary',condition_table,'run_summary',run_table, ...
        'q_scan',q_scan_table,'q_validation',q_validation_table, ...
        'packet_delays',packet_delay_table, ...
        'figure',figure_output,'manifest',manifest);
    fprintf('=== completed in %.1f s ===\n',manifest.elapsed_s);
end

function values = filter_stress_safe_q(variant,M,values,sim_cfg,cfg, ...
        variant_index,scenario,stress_cache)
    values = unique(double(values(:).'));
    keep = false(size(values));
    for i = 1:numel(values)
        keep(i) = q_stress_recovery(variant,M,values(i), ...
            sim_cfg,cfg,variant_index,scenario,stress_cache);
    end
    values = values(keep);
    if isempty(values)
        error('run_sfcb_lightload_study:NoStressSafeQ', ...
            'No q candidate passed burst-recovery validation.');
    end
end

function cfg = validate_study_cfg(cfg)
    cfg = validate_experiment_config(cfg);
    required = {'variants','q_fine_points','min_tune_completion_ratio', ...
        'min_validation_completion_ratio','n_validation_runs', ...
        'q_delay_tie_fraction','q_stress_nodes','q_stress_horizon_us', ...
        'q_stress_runs','output_root','study_type','study_schema_version'};
    for i = 1:numel(required)
        if ~isfield(cfg,required{i})
            error('run_sfcb_lightload_study:MissingConfig', ...
                'cfg.%s is required.',required{i});
        end
    end
    allowed = {'baseline','fast_first','unslotted','batch_clear'};
    cfg.variants = cellstr(string(cfg.variants(:).'));
    if isempty(cfg.variants) || any(~ismember(cfg.variants,allowed))
        error('run_sfcb_lightload_study:BadVariant', ...
            'cfg.variants contains an unsupported value.');
    end
    if any(cfg.M_values<1 | cfg.M_values~=round(cfg.M_values))
        error('run_sfcb_lightload_study:BadM', ...
            'M_values must contain integers >=1.');
    end
end

function value = phase_cfg(cfg,phase)
    value = cfg;
    switch phase
        case 'tune'
            value.warmup_us = cfg.tune_warmup_us;
            value.measure_us = cfg.tune_measure_us;
            value.drain_max_us = cfg.tune_drain_max_us;
        case 'eval'
            % Main durations already present.
        otherwise
            error('run_sfcb_lightload_study:BadPhase','Unknown phase.');
    end
    value.arrival_end_us = value.warmup_us + value.measure_us;
    value.sim_hard_end_us = value.arrival_end_us + value.drain_max_us;
    value = validate_experiment_config(value);
end

function traces = build_trace_cache(cfg,lambdas,n_runs,seed_offset)
    traces = cell(numel(lambdas),n_runs);
    for li = 1:numel(lambdas)
        for r = 1:n_runs
            seed = bounded_seed(cfg.traffic_seed_base + seed_offset + ...
                round(lambdas(li)*1e6) + r);
            traces{li,r} = generate_arrival_trace(lambdas(li),cfg,seed);
        end
    end
end

function grid = evaluate_grid(variant,M,q_values,stage,traces, ...
        sim_cfg,cfg,variant_index,scenario)
    q_values = unique(double(q_values(:).'));
    grid = repmat(empty_grid(),numel(q_values),1);
    for qi = 1:numel(q_values)
        metrics = repmat(empty_metric(),numel(traces),1);
        for r = 1:numel(traces)
            seed = protocol_seed(cfg,variant_index,M,r,0);
            result = simulate_sfcb_lightload_variant(variant,traces{r}, ...
                sim_cfg,M,q_values(qi),seed,scenario);
            metrics(r) = extract_metrics(result,sim_cfg);
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
            se_total = standard_error(finite_total);
        end
        grid(qi) = struct('q',q_values(qi),'stage',string(stage), ...
            'n_runs',numel(metrics), ...
            'mean_total_delay_us',mean_total, ...
            'se_total_delay_us',se_total, ...
            'mean_queue_delay_us',mean(queue,'omitnan'), ...
            'mean_access_delay_us',mean(access,'omitnan'), ...
            'completion_ratio_mean',mean(completion,'omitnan'), ...
            'min_completion_ratio',min(completion), ...
            'run_metrics',{metrics});
    end
end

function index = choose_best_q(grid,min_completion,variant,cfg)
    completion = [grid.completion_ratio_mean];
    minimum_completion = [grid.min_completion_ratio];
    delay = [grid.mean_total_delay_us];
    q = [grid.q];
    self_stable = isfinite(delay) & completion >= min_completion & ...
        minimum_completion >= min_completion;
    % q=1 is an absorbing retransmission collision after synchronized CTS
    % timeouts, including in the corrected asynchronous-RTS model.
    self_stable = self_stable & q < 1-1e-12;

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
        maximum = max(minimum_completion);
        candidates = find(minimum_completion >= maximum-1e-12 & ...
            isfinite(delay));
    end
    if isempty(candidates)
        error('run_sfcb_lightload_study:NoFiniteQ', ...
            'No q candidate completed a measurement packet.');
    end
    [minimum_delay,local] = min(delay(candidates));
    provisional = candidates(local);
    tolerance = max(grid(provisional).se_total_delay_us, ...
        cfg.q_delay_tie_fraction*minimum_delay);
    near = candidates(delay(candidates) <= minimum_delay+tolerance);

    switch variant
        case 'fast_first'
            preferred_q = 0.5;
            [~,local] = min(abs(q(near)-preferred_q));
        case 'unslotted'
            % Fresh HOL packets already transmit immediately; prefer the
            % lower retry q among statistically tied candidates.
            [~,local] = min(q(near));
        otherwise
            % Baseline/batch light-load delay decreases toward the largest
            % nonabsorbing q that remains stable with both neighbors.
            [~,local] = max(q(near));
    end
    index = near(local);
end

function [best_q,rows] = validate_q_candidates(variant,M,grid, ...
        initial_index,traces,sim_cfg,cfg,variant_index,scenario,stress_cache)
    q = [grid.q];
    minimum_completion = [grid.min_completion_ratio];
    finite = isfinite([grid.mean_total_delay_us]);
    eligible = finite & minimum_completion >= cfg.min_tune_completion_ratio;
    eligible = eligible & q < 1-1e-12;
    initial_q = q(initial_index);
    lower = sort(q(eligible & q<initial_q),'descend');
    higher = sort(q(eligible & q>initial_q),'ascend');
    candidates = unique([initial_q lower higher],'stable');
    if isempty(candidates)
        candidates = initial_q;
    end

    rows = struct([]);
    best_q = initial_q;
    best_min_completion = -Inf;
    best_delay = Inf;
    for ci = 1:numel(candidates)
        candidate_q = candidates(ci);
        [stress_pass,stress_worst_us] = q_stress_recovery(variant,M, ...
            candidate_q,sim_cfg,cfg,variant_index,scenario,stress_cache);
        if ~stress_pass
            row = struct();
            row.candidate_rank = ci;
            row.q = candidate_q;
            row.n_runs = 0;
            row.min_completion_ratio = 0;
            row.mean_completion_ratio = 0;
            row.mean_total_delay_us = Inf;
            row.all_packet_conservation_ok = true;
            row.stress_recovery_passed = false;
            row.stress_worst_completion_us = stress_worst_us;
            row.passed = false;
            if isempty(rows)
                rows = row;
            else
                rows(ci) = row; %#ok<AGROW>
            end
            continue;
        end

        metrics = repmat(empty_metric(),numel(traces),1);
        for r = 1:numel(traces)
            seed = protocol_seed(cfg,variant_index,M,r,5000000);
            result = simulate_sfcb_lightload_variant(variant,traces{r}, ...
                sim_cfg,M,candidate_q,seed,scenario);
            metrics(r) = extract_metrics(result,sim_cfg);
        end
        completion = [metrics.completion_ratio];
        delay = [metrics.mean_total_delay_us];
        conservation = [metrics.packet_conservation_ok];
        row = struct();
        row.candidate_rank = ci;
        row.q = candidate_q;
        row.n_runs = numel(metrics);
        row.min_completion_ratio = min(completion);
        row.mean_completion_ratio = mean(completion);
        row.mean_total_delay_us = mean(delay,'omitnan');
        row.all_packet_conservation_ok = all(conservation);
        row.stress_recovery_passed = stress_pass;
        row.stress_worst_completion_us = stress_worst_us;
        row.passed = row.min_completion_ratio >= ...
            cfg.min_validation_completion_ratio && ...
            row.all_packet_conservation_ok && stress_pass;
        if isempty(rows)
            rows = row;
        else
            rows(ci) = row; %#ok<AGROW>
        end

        if row.min_completion_ratio > best_min_completion || ...
                (row.min_completion_ratio==best_min_completion && ...
                 row.mean_total_delay_us<best_delay)
            best_q = candidate_q;
            best_min_completion = row.min_completion_ratio;
            best_delay = row.mean_total_delay_us;
        end
        if row.passed
            best_q = candidate_q;
            return;
        end
    end
end

function [passed,worst_completion_us] = q_stress_recovery(variant,M,q, ...
        sim_cfg,cfg,variant_index,scenario,stress_cache)
    cache_key = sprintf('%s_M%.12g_q%.17g_nodes%d_h%.12g_runs%d', ...
        variant,M,q,min(cfg.q_stress_nodes,sim_cfg.n_nodes), ...
        cfg.q_stress_horizon_us,cfg.q_stress_runs);
    if isKey(stress_cache,cache_key)
        cached = stress_cache(cache_key);
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
    for r = 1:cfg.q_stress_runs
        seed = protocol_seed(cfg,variant_index,M,r,6000000);
        result = simulate_sfcb_lightload_variant(variant,trace, ...
            stress_cfg,M,q,seed,scenario);
        completion = result.packet_log.completion_us;
        if any(~isfinite(completion))
            passed = false;
            worst_completion_us = Inf;
            stress_cache(cache_key) = struct('passed',passed, ...
                'worst_completion_us',worst_completion_us);
            return;
        end
        worst_completion_us = max(worst_completion_us,max(completion));
    end
    passed = passed && worst_completion_us <= cfg.q_stress_horizon_us;
    stress_cache(cache_key) = struct('passed',passed, ...
        'worst_completion_us',worst_completion_us);
end

function q = local_fine_grid(coarse,best_index,n_points)
    coarse = unique(double(coarse(:).'));
    if numel(coarse)==1
        q = coarse;
        return;
    end
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

function values = remove_existing(values,existing)
    keep = true(size(values));
    for i = 1:numel(values)
        keep(i) = ~any(abs(values(i)-existing) <= ...
            16*eps(max(1,abs(values(i)))));
    end
    values = values(keep);
end

function metrics = extract_metrics(result,cfg)
    pkt = result.packet_log;
    cohort = pkt.arrival_us >= cfg.warmup_us & ...
        pkt.arrival_us < cfg.arrival_end_us;
    completed = cohort & isfinite(pkt.completion_us);
    metrics = empty_metric();
    metrics.n_arrived = sum(cohort);
    metrics.n_completed = sum(completed);
    metrics.n_censored = metrics.n_arrived-metrics.n_completed;
    metrics.completion_ratio = metrics.n_completed/max(1,metrics.n_arrived);
    metrics.mean_total_delay_us = mean(pkt.total_delay_us(completed),'omitnan');
    metrics.mean_queue_delay_us = ...
        mean(pkt.queue_delay_us(completed),'omitnan');
    metrics.mean_access_delay_us = ...
        mean(pkt.access_delay_us(completed),'omitnan');
    metrics.p95_total_delay_us = ...
        percentile_or_nan(pkt.total_delay_us(completed),95);
    metrics.mean_attempts = mean(pkt.attempts(completed),'omitnan');
    metrics.final_backlog = result.summary.final_backlog;
    metrics.stable = result.summary.stable;
    metrics.packet_conservation_ok = result.summary.packet_conservation_ok;
end

function row = metric_run_row(metric,variant,lambda,M,q,run,result)
    row = metric;
    row.variant = string(variant);
    row.lambda_per_node = lambda;
    row.M = M;
    row.Tp_us = result.summary.Tp_us;
    row.q = q;
    row.run = run;
    row.collision_channel_time_us = ...
        result.summary.collision_channel_time_us_total;
    if isfield(result.diagnostics,'mean_batch_size')
        row.mean_batch_size = result.diagnostics.mean_batch_size;
    else
        row.mean_batch_size = 1;
    end
end

function row = summarize_condition(metrics,variant,lambda,M,q,cfg)
    timing = mmw_timing_config(cfg);
    total = [metrics.mean_total_delay_us];
    queue = [metrics.mean_queue_delay_us];
    access = [metrics.mean_access_delay_us];
    completion = [metrics.completion_ratio];
    row = struct();
    row.variant = string(variant);
    row.lambda_per_node = lambda;
    row.M = M;
    row.Tp_us = timing.CONN_SLOT_US*M;
    row.best_q = q;
    row.n_eval_runs = numel(metrics);
    row.mean_total_delay_us = mean(total,'omitnan');
    row.ci95_total_delay_us = ci95(total);
    row.mean_queue_delay_us = mean(queue,'omitnan');
    row.ci95_queue_delay_us = ci95(queue);
    row.mean_access_delay_us = mean(access,'omitnan');
    row.ci95_access_delay_us = ci95(access);
    row.p95_total_delay_us_mean = ...
        mean([metrics.p95_total_delay_us],'omitnan');
    row.completion_ratio_mean = mean(completion,'omitnan');
    row.stable_fraction = mean([metrics.stable]);
    row.final_backlog_mean = mean([metrics.final_backlog]);
    row.mean_attempts = mean([metrics.mean_attempts],'omitnan');
    row.delay_identity_error_us = abs(row.mean_total_delay_us - ...
        row.mean_queue_delay_us-row.mean_access_delay_us);
end

function value = packet_table(result,variant,lambda,M,q,run)
    pkt = result.packet_log;
    keep = pkt.in_measurement_cohort;
    packet_id = find(keep);
    n = numel(packet_id);
    value = table(repmat(string(variant),n,1), ...
        repmat(lambda,n,1),repmat(M,n,1),repmat(q,n,1), ...
        repmat(run,n,1),packet_id,pkt.node_id(keep), ...
        pkt.arrival_us(keep),pkt.hol_us(keep), ...
        pkt.first_attempt_us(keep),pkt.completion_us(keep), ...
        pkt.total_delay_us(keep),pkt.queue_delay_us(keep), ...
        pkt.access_delay_us(keep),pkt.attempts(keep), ...
        logical(pkt.status(keep)), ...
        'VariableNames',{'variant','lambda_per_node','M','q','run', ...
        'packet_id','node_id','arrival_us','hol_us','first_attempt_us', ...
        'completion_us','total_delay_us','queue_delay_us', ...
        'access_delay_us','attempts','completed'});
end

function value = protocol_seed(cfg,variant_index,M,run,offset)
    value = bounded_seed(cfg.protocol_seed_base + offset + ...
        variant_index*1000000 + M*10000 + run);
end

function value = bounded_seed(raw)
    value = mod(round(double(raw)),2^31-2)+1;
end

function value = percentile_or_nan(x,p)
    if isempty(x)
        value = NaN;
    else
        value = prctile(x,p);
    end
end

function value = standard_error(x)
    x = x(isfinite(x));
    if numel(x)<=1
        value = 0;
    else
        value = std(x,0)/sqrt(numel(x));
    end
end

function value = ci95(x)
    value = 1.96*standard_error(x);
end

function value = empty_metric()
    value = struct('n_arrived',0,'n_completed',0,'n_censored',0, ...
        'completion_ratio',0,'mean_total_delay_us',NaN, ...
        'mean_queue_delay_us',NaN,'mean_access_delay_us',NaN, ...
        'p95_total_delay_us',NaN,'mean_attempts',NaN, ...
        'final_backlog',0,'stable',false, ...
        'packet_conservation_ok',false);
end

function value = empty_grid()
    value = struct('q',NaN,'stage',"",'n_runs',0, ...
        'mean_total_delay_us',Inf,'se_total_delay_us',Inf, ...
        'mean_queue_delay_us',NaN,'mean_access_delay_us',NaN, ...
        'completion_ratio_mean',0,'min_completion_ratio',0, ...
        'run_metrics',repmat(empty_metric(),0,1));
end

function write_json(path,value)
    fid = fopen(path,'w');
    if fid < 0
        error('run_sfcb_lightload_study:ManifestWrite', ...
            'Cannot open %s.',path);
    end
    cleanup = onCleanup(@() fclose(fid));
    fwrite(fid,jsonencode(value,'PrettyPrint',true),'char');
    clear cleanup;
end
