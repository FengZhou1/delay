function out = run_delay_comparison(cfg)
%RUN_DELAY_COMPARISON Non-saturated end-to-end delay comparison.
%   out = run_delay_comparison()          % analysis profile
%   out = run_delay_comparison(cfg)       % custom / smoke config
%
% For each protocol (sf_cb, batch_clear, unslotted, sb_cb), lambda in
% [1 5 10] and M in 1:6, scan q: a coarse grid with one tuning run per
% point, then a local refinement around the best coarse point, and
% finally n_eval_runs independent seeds on the fine grid.  Among candidates
% whose measurement-cohort completion ratio is >= 0.99 the condition with
% the smallest conditional mean end-to-end delay is chosen; the reported
% delay is the mean over the evaluation seeds.
%
% Performance notes: the q scans run in parallel (parfor, 16 workers when
% available); results are saved incrementally after every (lambda, M,
% protocol) cell so a crashed run can be resumed, and the unslotted/sb_cb
% high-q region (which costs tens of seconds per run at high load) is
% capped by q_max_light when cfg.q_max_light is set.
%
% Outputs: delay_data.mat (results + best-q table), delay_comparison.png
% (3 stacked subplots, one per lambda, x = M, log y = delay in us).

    if nargin < 1 || isempty(cfg)
        cfg = default_lightload_sfcb_config('analysis','delay');
    end
    if ~isfield(cfg,'mode') || ~strcmpi(char(cfg.mode),'delay')
        error('run_delay_comparison:BadMode', ...
            'Expected a delay-mode config (mode = ''delay'').');
    end

    timing = protocol_timing(cfg);
    scenario = prepare_scenario_v2(cfg, cfg.topology_seed);
    protocols = {'sf_cb','batch_clear','unslotted','sb_cb'};
    n_protocols = numel(protocols);
    coarse_q = double(cfg.q_coarse(:).');
    n_fine = double(cfg.q_fine_points);
    n_eval = double(cfg.n_eval_runs);
    tune_min_completion = double(cfg.min_tune_completion_ratio);
    eval_min_completion = double(cfg.min_eval_completion_ratio);
    output_root = char(cfg.output_root);
    output_root = fullfile(output_root, datestr(now, 'yyyymmdd_HHMMSS'));

    if ~exist(output_root,'dir'), mkdir(output_root); end
    prof_tag = 'smoke';
    if isfield(cfg,'profile') && ~isempty(cfg.profile)
        prof_tag = lower(char(cfg.profile));
    end
    partial_file = fullfile(output_root, sprintf('delay_partial_%s.mat', prof_tag));
    if exist(partial_file,'file')
        partial = load(partial_file);
        done_keys = partial.keys_save;
        partial_rows = partial.rows_save;
        partial_qrows = partial.qrows_save;
        fprintf('[delay] resuming: %d cells already complete\n', ...
            numel(done_keys));
    else
        done_keys = {};
        partial_rows = cell(0,1);
        partial_qrows = cell(0,1);
    end

    tune_cfg = set_window(cfg, cfg.tune_warmup_us, cfg.tune_measure_us, ...
        cfg.tune_drain_max_us);
    eval_cfg = cfg;

    % Cache one tune trace and n_eval eval traces per lambda.
    tune_traces = cell(numel(cfg.lambda_values),1);
    eval_traces = cell(numel(cfg.lambda_values), n_eval);

    rows = partial_rows;
    qrows = partial_qrows;
    for li = 1:numel(cfg.lambda_values)
        lambda = double(cfg.lambda_values(li));
        fprintf('[delay] lambda=%g: building arrival traces\n', lambda);
        tune_traces{li} = generate_arrival_trace( ...
            lambda, tune_cfg, cfg.traffic_seed_base);
        for s = 1:n_eval
            eval_traces{li,s} = generate_arrival_trace( ...
                lambda, eval_cfg, cfg.traffic_seed_base + 100*s);
        end

        for Mi = 1:numel(cfg.M_values)
            M = double(cfg.M_values(Mi));
            for pi = 1:n_protocols
                protocol = protocols{pi};
                proto_seed_base = cfg.protocol_seed_base + 100*pi;
                fprintf('[delay] %s lambda=%g M=%d: coarse scan (%d q)\n', ...
                    protocol, lambda, M, numel(coarse_q));

                cell_key = sprintf('%s|%g|%d', protocol, lambda, M);
                if ismember(cell_key, done_keys)
                    fprintf('[delay] %s lambda=%g M=%d: cached\n', ...
                        protocol, lambda, M);
                    continue;
                end

                % ---- coarse tuning pass (one run per q) ----
                cell_q = coarse_q;
                if isfield(cfg,'q_max_light') && ~isempty(cfg.q_max_light) && ...
                        (strcmp(protocol,'unslotted') || strcmp(protocol,'sb_cb'))
                    cell_q = cell_q(cell_q <= cfg.q_max_light);
                    if isempty(cell_q)
                        cell_q = min(coarse_q);
                    end
                end
                coarse_best = run_coarse_scan(protocol, tune_traces{li}, ...
                    scenario, tune_cfg, M, cell_q, ...
                    cfg.protocol_seed_base + pi, tune_min_completion);

                % ---- local refinement around the best coarse point ----
                [fine_q, fine_meta] = build_refined_q_grid(cell_q, ...
                    coarse_best.best_idx, n_fine, cfg.q_refine_scale, ...
                    cfg.q_refine_floor, 1);

                fprintf('[delay] %s lambda=%g M=%d: fine eval (%d q x %d seeds)\n', ...
                    protocol, lambda, M, numel(fine_q), n_eval);
                fine_best = eval_fine_grid(protocol, eval_traces(li,:), ...
                    scenario, eval_cfg, M, fine_q, proto_seed_base, ...
                    eval_min_completion);

                % Fallback: when the refined neighbourhood around the coarse
                % best is entirely unstable (no candidate meets the
                % completion floor, e.g. batch_clear bistability at high
                % load), re-scan the full coarse grid on the evaluation
                % window so a stable operating point far from the coarse
                % best is not missed.
                if ~isfinite(fine_best.best_delay_us) || ...
                        fine_best.best_completion_ratio < eval_min_completion
                    coarse_eval = eval_fine_grid(protocol, ...
                        eval_traces(li,:), scenario, eval_cfg, M, ...
                        coarse_q, proto_seed_base, eval_min_completion);
                    if isfinite(coarse_eval.best_delay_us) && ...
                            coarse_eval.best_completion_ratio >= ...
                            eval_min_completion
                        fprintf(['[delay] %s lambda=%g M=%d: refined region ' ...
                            'unstable; coarse-grid fallback q=%g\n'], ...
                            protocol, lambda, M, coarse_eval.best_q);
                        fine_best = coarse_eval;
                    end
                end

                best_q = fine_best.best_q;
                best_delay = fine_best.best_delay_us;
                best_completion = fine_best.best_completion_ratio;
                best_std = fine_best.best_std_us;

                rows{end+1,1} = struct( ... %#ok<AGROW>
                    'protocol', protocol, ...
                    'lambda', lambda, ...
                    'M', M, ...
                    'Tp_us', timing.CONN_SLOT_US * M, ...
                    'best_q', best_q, ...
                    'delay_us', best_delay, ...
                    'delay_std_us', best_std, ...
                    'completion_ratio', best_completion, ...
                    'n_eval_runs', n_eval);
                qrows{end+1,1} = struct( ... %#ok<AGROW>
                    'protocol', protocol, ...
                    'lambda', lambda, ...
                    'M', M, ...
                    'q_coarse_best', coarse_best.best_q, ...
                    'q_coarse_delay_us', coarse_best.best_delay_us, ...
                    'q_fine_best', best_q, ...
                    'q_fine_delay_us', best_delay, ...
                    'q_fine_completion_ratio', best_completion, ...
                    'fine_q', fine_q, ...
                    'fine_delay_us', fine_best.fine_delay_us, ...
                    'fine_completion_ratio', fine_best.fine_completion_ratio);
                done_keys{end+1,1} = cell_key; %#ok<AGROW>
                rows_save = rows; qrows_save = qrows; keys_save = done_keys;
                save(partial_file, 'rows_save', 'qrows_save', 'keys_save', ...
                    '-v7.3');
            end
        end
    end

    table_rows = vertcat(rows{:});
    q_table = vertcat(qrows{:});
    data = struct();
    data.config = eval_cfg;
    data.timing = timing;
    data.results = table_rows;
    data.q_table = q_table;
    data.protocols = protocols;
    data.lambda_values = double(cfg.lambda_values(:).');
    data.M_values = double(cfg.M_values(:).');

    if ~exist(output_root,'dir'), mkdir(output_root); end
    save(fullfile(output_root,'delay_data.mat'), 'data');

    qcsv = q_table_to_table(q_table);
    writetable(qcsv, fullfile(output_root,'delay_q_table.csv'));

    delay_png = plot_delay_comparison(data, ...
        fullfile(output_root,'delay_comparison.png'));
    fprintf('[delay] saved %s and delay_q_table.csv\n', delay_png);

    out = struct();
    out.data = data;
    out.plot_file = delay_png;
end

% ---------------- coarse tuning ----------------
function best = run_coarse_scan(protocol, trace, scenario, cfg, M, q_grid, ...
        seed, min_completion)
    n = numel(q_grid);
    delay = nan(n,1);
    completion = zeros(n,1);
    parfor i = 1:n
        result = simulate_sfcb_lightload_variant(protocol, trace, ...
            scenario, cfg, M, q_grid(i), seed);
        s = result.summary;
        completion(i) = s.completion_ratio;
        if s.stable && s.completion_ratio >= min_completion
            delay(i) = s.mean_delay_us;
        end
    end
    stable_idx = find(isfinite(delay) & completion >= min_completion);
    if ~isempty(stable_idx)
        [~, idx_in] = min(delay(stable_idx));
        best_idx = stable_idx(idx_in);
    else
        [~, best_idx] = max(completion);
    end
    best = struct();
    best.best_idx = best_idx;
    best.best_q = q_grid(best_idx);
    best.best_delay_us = delay(best_idx);
    best.grid_delay_us = delay;
    best.grid_completion_ratio = completion;
end

% ---------------- fine evaluation ----------------
function best = eval_fine_grid(protocol, traces_row, scenario, cfg, M, ...
        q_grid, seed_base, min_completion)
    n = numel(q_grid);
    n_eval = size(traces_row,2);
    delay = nan(n, n_eval);
    completion = zeros(n, n_eval);
    for i = 1:n
        if n_eval <= 1
            result = simulate_sfcb_lightload_variant(protocol, ...
                traces_row{1}, scenario, cfg, M, q_grid(i), ...
                seed_base + 1);
            sumr = result.summary;
            completion(i,1) = sumr.completion_ratio;
            if sumr.stable && sumr.completion_ratio >= min_completion
                delay(i,1) = sumr.mean_delay_us;
            end
        else
            parfor s = 1:n_eval
                result = simulate_sfcb_lightload_variant(protocol, ...
                    traces_row{s}, scenario, cfg, M, q_grid(i), ...
                    seed_base + s);
                sumr = result.summary;
                completion(i,s) = sumr.completion_ratio;
                if sumr.stable && sumr.completion_ratio >= min_completion
                    delay(i,s) = sumr.mean_delay_us;
                end
            end
        end
    end
    mean_delay = nanmean(delay,2);
    mean_completion = nanmean(completion,2);
    valid = mean_completion >= min_completion & isfinite(mean_delay);
    if any(valid)
        [~, best_i] = min(mean_delay(valid));
        valid_idx = find(valid);
        best_i = valid_idx(best_i);
    else
        [~, best_i] = max(mean_completion);
    end
    best = struct();
    best.best_q = q_grid(best_i);
    best.best_delay_us = mean_delay(best_i);
    best.best_completion_ratio = mean_completion(best_i);
    best.best_std_us = std(delay(best_i,:),0,2);
    best.fine_delay_us = mean_delay;
    best.fine_completion_ratio = mean_completion;
end

% ---------------- helpers ----------------
function c = set_window(cfg, warmup, measure, drain)
    c = cfg;
    c.warmup_us = warmup;
    c.measure_us = measure;
    c.drain_max_us = drain;
    c.arrival_end_us = warmup + measure;
    c.sim_hard_end_us = c.arrival_end_us + drain;
end

function t = q_table_to_table(q_table)
    t = table();
    t.protocol = cellfun(@char, {q_table.protocol}.', 'UniformOutput', false);
    t.lambda = [q_table.lambda].';
    t.M = [q_table.M].';
    t.q_coarse_best = [q_table.q_coarse_best].';
    t.q_coarse_delay_us = [q_table.q_coarse_delay_us].';
    t.q_fine_best = [q_table.q_fine_best].';
    t.q_fine_delay_us = [q_table.q_fine_delay_us].';
    t.q_fine_completion_ratio = [q_table.q_fine_completion_ratio].';
end


