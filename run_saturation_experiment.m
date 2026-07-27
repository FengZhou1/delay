function experiment = run_saturation_experiment(cfg)
%RUN_SATURATION_EXPERIMENT Tune q and evaluate saturated v2 throughput.
%
% The current protocol state machines are reused with one persistent virtual
% HOL packet per MLO station.  q is selected independently for every
% (protocol,M) condition by maximizing actual successful payload
% throughput. Fractional requested M values are mapped to integer mmWave
% DATA slots by saturation_payload_timing.

    if nargin < 1 || isempty(cfg)
        cfg = default_saturation_config('smoke');
    end
    cfg = validate_saturation_config(cfg);
    [cfg_hash,code_fingerprint] = experiment_config_hash(cfg);

    if isfield(cfg,'output_dir') && ~isempty(cfg.output_dir)
        output_dir = char(cfg.output_dir);
    else
        stamp = char(datetime('now','Format','yyyyMMdd_HHmmss'));
        output_dir = fullfile(cfg.results_root,[stamp '_' cfg_hash]);
    end
    prepare_output_directory(output_dir,cfg,cfg_hash);
    checkpoint_dir = fullfile(output_dir,'checkpoints');
    if ~exist(checkpoint_dir,'dir'), mkdir(checkpoint_dir); end

    verification_status = 'UNVERIFIED';
    manifest = make_manifest(cfg,cfg_hash,code_fingerprint,output_dir, ...
        'running',verification_status);
    write_json(fullfile(output_dir,'manifest.json'),manifest);
    save(fullfile(output_dir,'config.mat'),'cfg');

    fprintf('\n=== Saturation experiment %s | profile=%s ===\n', ...
        cfg_hash,cfg.profile);
    fprintf('Output: %s\n',output_dir);
    started = tic;

    if cfg.run_preflight_tests
        verification_dir = fullfile(output_dir,'verification');
        run_saturation_tests(verification_dir);
        verification_status = 'VERIFIED';
        manifest = make_manifest(cfg,cfg_hash,code_fingerprint,output_dir, ...
            'running',verification_status);
        write_json(fullfile(output_dir,'manifest.json'),manifest);
    end

    scenario = prepare_scenario_v2(cfg,cfg.topology_seed);
    trace = make_saturation_trace(cfg);
    save(fullfile(output_dir,'scenario.mat'),'scenario','-v7.3');
    maybe_start_pool(cfg);

    summary_rows = struct([]);
    q_scan_rows = struct([]);
    condition_files = cell(0,1);
    summary_idx = 0;
    q_row_idx = 0;
    total = numel(cfg.protocols)*numel(cfg.M_values);
    done = 0;

    for mi = 1:numel(cfg.M_values)
        M = cfg.M_values(mi);
        for pi = 1:numel(cfg.protocols)
            protocol = cfg.protocols{pi};
            tag = sprintf('%s_M%s',protocol,format_M_tag(M));
            if ~isempty(cfg.condition_filter) && ...
                    ~ismember(tag,cfg.condition_filter)
                continue;
            end
            done = done + 1;
            fprintf('[%d/%d] %s\n',done,total,tag);
            checkpoint = fullfile(checkpoint_dir,[tag '.mat']);
            condition_started = tic;

            if cfg.resume && exist(checkpoint,'file')
                condition = load_checkpoint(checkpoint,cfg_hash,code_fingerprint);
                fprintf('  resumed checkpoint\n');
            else
                coarse_q = cfg.protocol_q_grids.(protocol);
                coarse = evaluate_q_grid(protocol,M,coarse_q,'coarse', ...
                    cfg.n_tune_runs,0,scenario,trace,cfg,pi);
                [coarse_best_idx,~] = select_grid_entry(coarse);
                fine_q = build_fine_grid(coarse_q,coarse_best_idx, ...
                    cfg.q_fine_points,cfg.q_refine_floor);
                fine_q = remove_existing_q(fine_q,[coarse.q]);
                if isempty(fine_q)
                    fine = struct([]);
                else
                    fine = evaluate_q_grid(protocol,M,fine_q,'fine', ...
                        cfg.n_tune_runs,0,scenario,trace,cfg,pi);
                end
                if isempty(fine)
                    grid = sort_grid(coarse(:));
                else
                    grid = sort_grid([coarse(:); fine(:)]);
                end
                [best_idx,selection] = select_grid_entry(grid);
                best_q = grid(best_idx).q;

                eval_results = evaluate_runs(protocol,M,best_q, ...
                    cfg.n_eval_runs,10000,scenario,trace,cfg,pi);
                condition = summarize_condition(protocol,M,best_q,grid, ...
                    eval_results,selection,cfg);
                condition.elapsed_s = toc(condition_started);
                condition.row.condition_elapsed_s = condition.elapsed_s;
                condition.row.timeout_exceeded = ...
                    condition.elapsed_s > cfg.condition_timeout_s;
                condition.config_hash = cfg_hash;
                condition.code_fingerprint = code_fingerprint;
                save_checkpoint_atomic(checkpoint,condition);
            end

            summary_idx = summary_idx + 1;
            if isempty(summary_rows)
                summary_rows = condition.row;
            else
                summary_rows(summary_idx) = condition.row; %#ok<AGROW>
            end
            condition_files{summary_idx,1} = checkpoint; %#ok<AGROW>
            for gi = 1:numel(condition.grid)
                q_row_idx = q_row_idx + 1;
                qrow = grid_row(protocol,M,condition.grid(gi), ...
                    condition.best_q);
                if isempty(q_scan_rows)
                    q_scan_rows = qrow;
                else
                    q_scan_rows(q_row_idx) = qrow; %#ok<AGROW>
                end
            end
        end
    end

    summary_table = structs_to_table(summary_rows);
    q_scan_table = structs_to_table(q_scan_rows);
    writetable(summary_table,fullfile(output_dir,'saturation_summary.csv'));
    writetable(q_scan_table,fullfile(output_dir,'q_scan.csv'));
    save(fullfile(output_dir,'saturation_experiment.mat'), ...
        'summary_table','q_scan_table','condition_files','cfg','-v7.3');

    plot_result = plot_saturation_throughput_v2(output_dir);

    manifest = make_manifest(cfg,cfg_hash,code_fingerprint,output_dir, ...
        'completed',verification_status);
    manifest.duration_s = toc(started);
    manifest.n_conditions = height(summary_table);
    manifest.plot_png = plot_result.png_path;
    manifest.plot_pdf = plot_result.pdf_path;
    manifest.intersections_csv = plot_result.intersections_path;
    write_json(fullfile(output_dir,'manifest.json'),manifest);

    experiment = struct('output_dir',output_dir,'config',cfg, ...
        'summary',summary_table,'q_scan',q_scan_table, ...
        'plot',plot_result,'manifest',manifest);
    fprintf('=== saturation experiment completed in %.1f s ===\n', ...
        manifest.duration_s);
end

function grid = evaluate_q_grid(protocol,M,q_values,stage,n_runs,seed_offset, ...
        scenario,trace,cfg,protocol_idx)
    q_values = unique(double(q_values(:).'));
    n_q = numel(q_values);
    cells = cell(n_q,1);
    use_parallel = cfg.parallel && n_q > 1 && ...
        license('test','Distrib_Computing_Toolbox');
    if use_parallel
        parfor qi = 1:n_q
            runs = evaluate_runs(protocol,M,q_values(qi),n_runs,seed_offset, ...
                scenario,trace,cfg,protocol_idx);
            cells{qi} = summarize_q(q_values(qi),stage,runs,cfg);
        end
    else
        for qi = 1:n_q
            runs = evaluate_runs(protocol,M,q_values(qi),n_runs,seed_offset, ...
                scenario,trace,cfg,protocol_idx);
            cells{qi} = summarize_q(q_values(qi),stage,runs,cfg);
        end
    end
    grid = vertcat(cells{:});
end

function runs = evaluate_runs(protocol,M,q,n_runs,seed_offset, ...
        scenario,trace,cfg,protocol_idx)
    runs = cell(n_runs,1);
    for r = 1:n_runs
        % The same run-index seed is used at every q so the q comparison is
        % paired and does not depend on q scan order.
        seed = bounded_seed(cfg.protocol_seed_base + seed_offset + ...
            100000*protocol_idx + 1000*M + r);
        runs{r} = run_protocol_v2(protocol,trace,scenario,cfg,M,q,seed);
    end
end

function row = summarize_q(q,stage,runs,cfg)
    summary = cellfun(@(x) x.summary,runs,'UniformOutput',false);
    th = cellfun(@(x) x.effective_payload_fraction,summary);
    pkt_s = cellfun(@(x) x.completed_pkt_s,summary);
    fairness = cellfun(@(x) x.jain_fairness,summary);
    collision = cellfun(@(x) collision_fraction(x.diagnostics,cfg),runs);
    row = struct('q',q,'stage',char(stage),'n_runs',numel(runs), ...
        'mean_throughput',mean(th),'se_throughput',standard_error(th), ...
        'mean_completed_pkt_s',mean(pkt_s), ...
        'mean_collision_fraction',mean(collision,'omitnan'), ...
        'mean_jain_fairness',mean(fairness,'omitnan'),'runs',{runs});
end

function [best_idx,meta] = select_grid_entry(grid)
    means = [grid.mean_throughput];
    means(~isfinite(means)) = -inf;
    [maximum,best_max] = max(means);
    if ~isfinite(maximum)
        error('run_saturation_experiment:NoFiniteQ', ...
            'No q candidate produced a finite saturation throughput.');
    end
    tolerance = grid(best_max).se_throughput;
    if ~isfinite(tolerance), tolerance = 0; end
    candidates = find(means >= maximum-tolerance-1e-15);
    collision = [grid(candidates).mean_collision_fraction].';
    collision(~isfinite(collision)) = inf;
    fairness = [grid(candidates).mean_jain_fairness].';
    fairness(~isfinite(fairness)) = -inf;
    q = [grid(candidates).q].';
    keys = [collision,-fairness,q];
    [~,order] = sortrows(keys,[1 2 3]);
    best_idx = candidates(order(1));
    all_q = [grid.q];
    meta = struct();
    meta.selection_mode = 'maximum_effective_payload_throughput';
    if numel(candidates) > 1
        meta.selection_mode = 'one_se_tie_collision_fairness_q';
    end
    meta.boundary_hit = grid(best_idx).q == min(all_q) || ...
        grid(best_idx).q == max(all_q);
    if numel(all_q) == 1
        meta.boundary_hit = false;
        meta.selection_mode = 'fixed_theoretical_q';
    end
end

function q = build_fine_grid(coarse,best_idx,n_points,q_floor)
    coarse = unique(double(coarse(:).'));
    if numel(coarse) < 2
        q = coarse;
        return;
    end
    best_idx = max(1,min(numel(coarse),best_idx));
    if best_idx == 1
        lo = max(q_floor,coarse(1)/10);
        hi = coarse(2);
    elseif best_idx == numel(coarse)
        lo = coarse(end-1);
        hi = min(1,max(coarse(end)*2,coarse(end)+eps(coarse(end))));
    else
        lo = coarse(best_idx-1);
        hi = coarse(best_idx+1);
    end
    if hi <= lo
        q = coarse(best_idx);
    else
        q = unique(logspace(log10(lo),log10(hi),n_points));
    end
end

function values = remove_existing_q(values,existing)
    keep = true(size(values));
    for i = 1:numel(values)
        keep(i) = ~any(abs(existing-values(i)) <= ...
            16*eps(max(1,abs(values(i)))));
    end
    values = values(keep);
end

function grid = sort_grid(grid)
    if isempty(grid), return; end
    [~,order] = sort([grid.q]);
    grid = grid(order);
end

function condition = summarize_condition(protocol,M,best_q,grid,runs,selection,cfg)
    summaries = cellfun(@(x) x.summary,runs,'UniformOutput',false);
    th = cellfun(@(x) x.payload_airtime_fraction,summaries);
    effective_th = cellfun(@(x) x.effective_payload_fraction,summaries);
    pkt_s = cellfun(@(x) x.completed_pkt_s,summaries);
    norm_s = cellfun(@(x) x.normalized_goodput_units_s,summaries);
    bits = cellfun(@(x) x.goodput_bit_s,summaries);
    fairness = cellfun(@(x) x.jain_fairness,summaries);
    collision = cellfun(@(x) collision_fraction(x.diagnostics,cfg),runs);
    slo_pkt_s = cellfun(@(x) slo_metric(x.diagnostics, ...
        'slo_payload_success_measure',cfg.measure_us*1e-6),runs);
    slo_airtime = cellfun(@(x) slo_metric(x.diagnostics, ...
        'slo_payload_overlap_us',cfg.measure_us),runs);

    payload_timing = saturation_payload_timing(cfg,M);
    row = struct();
    row.protocol = string(protocol);
    row.study_type = "saturation_throughput";
    row.M = M;
    row.requested_Tp_us = payload_timing.nominal_payload_us;
    row.Tp_us = payload_timing.actual_payload_us;
    row.payload_slots = payload_timing.payload_slots;
    row.effective_M = payload_timing.effective_M;
    row.payload_quantization_error_us = ...
        payload_timing.quantization_error_us;
    row.best_q = best_q;
    row.q_selection_mode = string(selection.selection_mode);
    row.q_search_boundary_hit = selection.boundary_hit;
    row.n_eval_runs = numel(runs);
    row.payload_airtime_fraction_mean = mean(th);
    row.payload_airtime_fraction_ci95 = ci95(th);
    row.effective_payload_fraction_mean = mean(effective_th);
    row.effective_payload_fraction_ci95 = ci95(effective_th);
    row.completed_pkt_s_mean = mean(pkt_s);
    row.completed_pkt_s_ci95 = ci95(pkt_s);
    row.normalized_goodput_units_s_mean = mean(norm_s);
    row.normalized_goodput_units_s_ci95 = ci95(norm_s);
    row.goodput_bit_s_mean = mean(bits,'omitnan');
    row.jain_fairness_mean = mean(fairness,'omitnan');
    row.collision_channel_fraction_mean = mean(collision,'omitnan');
    row.slo_completed_pkt_s_mean = mean(slo_pkt_s,'omitnan');
    row.slo_payload_airtime_fraction_mean = mean(slo_airtime,'omitnan');
    row.condition_elapsed_s = NaN;
    row.timeout_exceeded = false;

    condition = struct('row',row,'best_q',best_q,'grid',grid, ...
        'eval_results',{runs},'selection',selection);
end

function row = grid_row(protocol,M,item,best_q)
    row = struct('protocol',string(protocol),'M',M,'q',item.q, ...
        'stage',string(item.stage),'n_runs',item.n_runs, ...
        'mean_throughput',item.mean_throughput, ...
        'se_throughput',item.se_throughput, ...
        'mean_completed_pkt_s',item.mean_completed_pkt_s, ...
        'mean_collision_fraction',item.mean_collision_fraction, ...
        'mean_jain_fairness',item.mean_jain_fairness, ...
        'selected',abs(item.q-best_q) <= 16*eps(max(1,abs(best_q))));
end

function fraction = collision_fraction(diagnostics,cfg)
    fraction = NaN;
    aliases = {'collision_channel_time_measure_us', ...
        'collision_wasted_measure_us','collision_waste_measure_us'};
    for i = 1:numel(aliases)
        if isfield(diagnostics,aliases{i})
            fraction = double(diagnostics.(aliases{i})) / cfg.measure_us;
            return;
        end
    end
end

function value = slo_metric(diagnostics,field,denominator)
    if isfield(diagnostics,field)
        value = double(diagnostics.(field))/denominator;
    else
        value = NaN;
    end
end

function value = standard_error(x)
    x = x(isfinite(x));
    if numel(x) <= 1
        value = 0;
    else
        value = std(x,0)/sqrt(numel(x));
    end
end

function value = ci95(x)
    x = x(isfinite(x));
    if numel(x) <= 1
        value = 0;
    else
        value = 1.96*std(x,0)/sqrt(numel(x));
    end
end

function prepare_output_directory(output_dir,cfg,cfg_hash)
    if exist(output_dir,'dir')
        entries = dir(output_dir);
        entries = entries(~ismember({entries.name},{'.','..'}));
        if isempty(entries), return; end
        manifest_path = fullfile(output_dir,'manifest.json');
        if ~exist(manifest_path,'file')
            error('run_saturation_experiment:UnsafeOutputDirectory', ...
                'Non-empty output_dir has no manifest: %s',output_dir);
        end
        old = jsondecode(fileread(manifest_path));
        if ~isfield(old,'config_hash') || ...
                ~strcmp(char(old.config_hash),cfg_hash)
            error('run_saturation_experiment:ConfigHashMismatch', ...
                'output_dir belongs to a different configuration.');
        end
        if ~cfg.resume
            error('run_saturation_experiment:ExistingOutputNoResume', ...
                'Set cfg.resume=true or select another output directory.');
        end
    else
        mkdir(output_dir);
    end
end

function condition = load_checkpoint(path,cfg_hash,code_fingerprint)
    saved = load(path,'condition');
    if ~isfield(saved,'condition') || ...
            ~strcmp(saved.condition.config_hash,cfg_hash) || ...
            ~strcmp(saved.condition.code_fingerprint,code_fingerprint)
        error('run_saturation_experiment:CheckpointMismatch', ...
            'Checkpoint does not match the current config/code: %s',path);
    end
    condition = saved.condition;
end

function save_checkpoint_atomic(path,condition)
    folder = fileparts(path);
    tmp = [tempname(folder) '.mat'];
    save(tmp,'condition','-v7.3');
    [ok,msg] = movefile(tmp,path,'f');
    if ~ok
        error('run_saturation_experiment:CheckpointWrite','%s',msg);
    end
end

function table_value = structs_to_table(rows)
    if isempty(rows)
        table_value = table();
    else
        table_value = struct2table(rows);
    end
end

function maybe_start_pool(cfg)
    if ~cfg.parallel || ~license('test','Distrib_Computing_Toolbox')
        return;
    end
    pool = gcp('nocreate');
    if isempty(pool)
        parpool('local',cfg.n_workers);
    elseif pool.NumWorkers ~= cfg.n_workers
        warning('run_saturation_experiment:WorkerCount', ...
            'Using existing pool with %d workers (requested %d).', ...
            pool.NumWorkers,cfg.n_workers);
    end
end

function seed = bounded_seed(value)
    seed = mod(round(double(value)),2^31-2)+1;
end

function tag = format_M_tag(M)
    tag = sprintf('%.12g',double(M));
    tag = strrep(tag,'-','m');
    tag = strrep(tag,'.','p');
    tag = strrep(tag,'+','');
end

function manifest = make_manifest(cfg,cfg_hash,code_fingerprint,output_dir, ...
        status,verification_status)
    manifest = struct('schema_version','2.2-saturation', ...
        'study_type','saturation_throughput', ...
        'config_hash',cfg_hash,'code_fingerprint',code_fingerprint, ...
        'profile',cfg.profile,'status',status, ...
        'verification_status',verification_status, ...
        'output_dir',output_dir, ...
        'updated_at',char(datetime('now','Format','yyyy-MM-dd HH:mm:ss')), ...
        'origin_skill','experiment-agent','origin_mode','run/validate');
end

function write_json(path,value)
    fid = fopen(path,'w');
    if fid < 0
        error('run_saturation_experiment:ManifestWrite', ...
            'Cannot open %s for writing.',path);
    end
    cleanup = onCleanup(@() fclose(fid));
    fwrite(fid,jsonencode(value,'PrettyPrint',true),'char');
    clear cleanup;
end
