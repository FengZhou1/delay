function analysis = analyze_experiment_v2(output_dir)
%ANALYZE_EXPERIMENT_V2 Analyze a versioned run_experiment result directory.
%   analysis = analyze_experiment_v2(output_dir) reads summary.csv and the
%   saved condition checkpoints, then writes:
%     figures/*.png
%     theory_validation.csv
%     aloha_capacity_theory.csv
%     csma_diagnostics.csv
%     cca_ablation_diagnostics.csv
%     topology_cluster_ci.csv
%     acceptance_checks.csv
%     涓枃鐞嗚-浠跨湡鎶ュ憡.md
%
%   The analyzer is deliberately tolerant of partial experiments: missing
%   protocols, missing conditions, empty evaluation cells, and diagnostics
%   introduced by only one protocol do not make the complete analysis fail.
%   A finite delay is displayed only when every evaluation run for that
%   condition was classified stable.  Conditional delay from an unstable or
%   mixed condition is never presented as a steady-state mean.

    if nargin < 1 || isempty(output_dir)
        error('analyze_experiment_v2:MissingDirectory', ...
              'A run_experiment output directory is required.');
    end
    output_dir = char(output_dir);
    if ~isfolder(output_dir)
        error('analyze_experiment_v2:DirectoryNotFound', ...
              'Result directory does not exist: %s', output_dir);
    end

    summary_path = fullfile(output_dir, 'summary.csv');
    if ~isfile(summary_path)
        error('analyze_experiment_v2:SummaryNotFound', ...
              'summary.csv was not found in %s.', output_dir);
    end
    summary = readtable(summary_path, 'VariableNamingRule', 'preserve');
    cfg = read_saved_config(output_dir);
    conditions = read_checkpoints(fullfile(output_dir, 'checkpoints'));
    cca_conditions = read_checkpoints(fullfile(output_dir, 'checkpoints_cca'));
    topology_conditions = read_checkpoints(fullfile(output_dir, 'checkpoints_topology'));
    cca_summary = read_optional_table(fullfile(output_dir, 'cca_ablation.csv'));
    topology_summary = read_optional_table(fullfile(output_dir, 'topology_robustness.csv'));

    theory = build_theory_validation(conditions, cfg);
    theory_path = fullfile(output_dir, 'theory_validation.csv');
    writetable(theory, theory_path);

    capacity = build_aloha_capacity_theory(cfg, summary);
    capacity_path = fullfile(output_dir, 'aloha_capacity_theory.csv');
    writetable(capacity, capacity_path);

    csma = build_csma_diagnostics(conditions, cfg);
    csma_path = fullfile(output_dir, 'csma_diagnostics.csv');
    writetable(csma, csma_path);

    controlled_aloha = read_controlled_aloha_verification(output_dir, cfg);
    acceptance = build_acceptance_checks(summary, theory, controlled_aloha, cfg);
    acceptance_path = fullfile(output_dir, 'acceptance_checks.csv');
    writetable(acceptance, acceptance_path);

    cca_ablation = build_cca_ablation_diagnostics( ...
        cca_conditions, cca_summary, cfg);
    cca_ablation_path = fullfile(output_dir, 'cca_ablation_diagnostics.csv');
    writetable(cca_ablation, cca_ablation_path);

    topology_clusters = build_topology_cluster_ci( ...
        topology_conditions, topology_summary, cfg);
    topology_path = fullfile(output_dir, 'topology_cluster_ci.csv');
    writetable(topology_clusters, topology_path);

    figure_dir = fullfile(output_dir, 'figures');
    if ~isfolder(figure_dir), mkdir(figure_dir); end
    figure_paths = strings(0,1);
    figure_paths = append_path(figure_paths, ...
        plot_summary_metric(summary, 'mean_delay_us', ...
            'Mean delay (us)', 'Steady-state mean delay', ...
            fullfile(figure_dir, 'delay_by_M.png'), true));
    figure_paths = append_path(figure_paths, ...
        plot_summary_metric(summary, 'mean_queue_delay_us', ...
            'Mean queue delay (us)', 'Steady-state mean queue delay', ...
            fullfile(figure_dir, 'queue_delay_by_M.png'), true));
    figure_paths = append_path(figure_paths, ...
        plot_summary_metric(summary, 'mean_access_delay_us', ...
            'Mean access delay (us)', 'Steady-state mean access delay', ...
            fullfile(figure_dir, 'access_delay_by_M.png'), true));
    figure_paths = append_path(figure_paths, ...
        plot_delay_with_unstable(summary, ...
            fullfile(figure_dir, 'delay_by_M_with_unstable.png')));
    figure_paths = append_path(figure_paths, ...
        plot_summary_metric(summary, 'normalized_goodput_units_s', ...
            'Normalized payload units/s', 'Normalized goodput', ...
            fullfile(figure_dir, 'normalized_goodput_by_M.png'), false));
    figure_paths = append_path(figure_paths, ...
        plot_summary_metric(summary, 'stable_fraction', ...
            'Stable run fraction', 'Stability classification', ...
            fullfile(figure_dir, 'stability_by_M.png'), false));
    figure_paths = append_path(figure_paths, ...
        plot_theory_validation(theory, ...
            fullfile(figure_dir, 'sf_cb_success_probability.png')));
    figure_paths = append_path(figure_paths, ...
        plot_csma_diagnostics(csma, ...
            fullfile(figure_dir, 'csma_cca_diagnostics.png')));
    figure_paths = append_path(figure_paths, ...
        plot_cca_ablation(cca_ablation, ...
            fullfile(figure_dir, 'cca_ablation_diagnostics.png')));
    figure_paths = append_path(figure_paths, ...
        plot_topology_clusters(topology_clusters, ...
            fullfile(figure_dir, 'topology_cluster_ci.png')));

    report_path = fullfile(output_dir, '涓枃鐞嗚-浠跨湡鎶ュ憡.md');
    write_chinese_report(report_path, output_dir, cfg, summary, theory, capacity, ...
        csma, acceptance, cca_ablation, topology_clusters, conditions, ...
        cca_conditions, topology_conditions, figure_paths);

    analysis = struct();
    analysis.output_dir = output_dir;
    analysis.summary = summary;
    analysis.theory_validation = theory;
    analysis.aloha_capacity_theory = capacity;
    analysis.csma_diagnostics = csma;
    analysis.acceptance_checks = acceptance;
    analysis.aloha_controlled_verification = controlled_aloha;
    analysis.cca_ablation_diagnostics = cca_ablation;
    analysis.topology_cluster_ci = topology_clusters;
    analysis.figure_paths = cellstr(figure_paths);
    analysis.report_path = report_path;
    analysis.n_checkpoints_loaded = numel(conditions);
    analysis.n_cca_checkpoints_loaded = numel(cca_conditions);
    analysis.n_topology_checkpoints_loaded = numel(topology_conditions);
end

function cfg = read_saved_config(output_dir)
    cfg = struct();
    path = fullfile(output_dir, 'config.mat');
    if ~isfile(path), return; end
    saved = load(path, 'cfg');
    if isfield(saved, 'cfg'), cfg = saved.cfg; end
end

function conditions = read_checkpoints(checkpoint_dir)
    conditions = cell(0,1);
    if ~isfolder(checkpoint_dir), return; end
    files = dir(fullfile(checkpoint_dir, '*.mat'));
    [~, order] = sort({files.name});
    files = files(order);
    for i = 1:numel(files)
        path = fullfile(files(i).folder, files(i).name);
        try
            saved = load(path, 'condition');
            if isfield(saved, 'condition') && isstruct(saved.condition)
                conditions{end+1,1} = saved.condition; %#ok<AGROW>
            else
                warning('analyze_experiment_v2:InvalidCheckpoint', ...
                        'Skipping checkpoint without condition: %s', path);
            end
        catch cause
            warning('analyze_experiment_v2:CheckpointReadFailed', ...
                    'Skipping unreadable checkpoint %s (%s).', ...
                    path, cause.message);
        end
    end
end

function value = read_optional_table(path)
    value = table();
    if ~isfile(path), return; end
    try
        value = readtable(path, 'VariableNamingRule', 'preserve');
    catch cause
        warning('analyze_experiment_v2:TableReadFailed', ...
                'Skipping unreadable table %s (%s).', path, cause.message);
    end
end

function capacity = build_aloha_capacity_theory(cfg, summary)
    conn_slot_us = analysis_conn_slot_us(cfg);
    n_nodes = max(1, round(config_scalar(cfg, 'n_nodes', 40)));
    M_values = config_numeric_vector(cfg, 'M_values');
    if isempty(M_values) && has_variables(summary, {'M'})
        M_values = unique(double(summary.M(isfinite(summary.M)))).';
    end
    if isempty(M_values), M_values = 1:6; end
    M_values = unique(M_values(isfinite(M_values) & M_values >= 1));

    lambda_values = config_numeric_vector(cfg, 'lambda_values');
    if isempty(lambda_values) && has_variables(summary, {'lambda_base'})
        lambda_values = unique(double(summary.lambda_base(isfinite(summary.lambda_base)))).';
    end
    if isempty(lambda_values), lambda_values = [5 15 30]; end

    load_modes = config_text_vector(cfg, 'load_modes');
    if isempty(load_modes) && has_variables(summary, {'load_mode'})
        load_modes = unique(string(summary.load_mode), 'stable').';
    end
    if isempty(load_modes), load_modes = ["fixed_packet" "fixed_payload"]; end

    q_opt = 1/n_nodes;
    ps_opt = n_nodes*q_opt*(1-q_opt)^(n_nodes-1);
    rows = cell(numel(M_values)*numel(lambda_values)*numel(load_modes),1);
    index = 0;
    for mode = load_modes
        for lambda_base = lambda_values
            for M = M_values
                index = index + 1;
                service_us = conn_slot_us*M + conn_slot_us/ps_opt;
                capacity_system = 1e6/service_us;
                if strcmpi(mode, 'fixed_payload')
                    lambda_effective = lambda_base/M;
                else
                    lambda_effective = lambda_base;
                end
                offered = n_nodes.*lambda_effective;
                rho = offered./capacity_system;
                rows{index} = struct( ...
                    'load_mode',string(mode), ...
                    'lambda_base',lambda_base, ...
                    'lambda_effective',lambda_effective, ...
                    'M',M, 'Tp_us',conn_slot_us*M, 'n_nodes',n_nodes, ...
                    'q_opt',q_opt, 'ps_opt',ps_opt, ...
                    'service_cycle_us',service_us, ...
                    'capacity_system_pkt_s',capacity_system, ...
                    'capacity_per_node_pkt_s',capacity_system/n_nodes, ...
                    'offered_aggregate_pkt_s',offered, ...
                    'offered_normalized_units_s',offered*M, ...
                    'rho',rho, 'theory_stable',rho < 1);
            end
        end
    end
    if index == 0
        capacity = empty_capacity_table();
    else
        capacity = struct2table(vertcat(rows{1:index}));
    end
end

function value = config_numeric_vector(cfg, field)
    value = [];
    if isstruct(cfg) && isfield(cfg,field) && isnumeric(cfg.(field))
        value = double(cfg.(field)(:)).';
    end
end

function value = config_text_vector(cfg, field)
    value = strings(1,0);
    if isstruct(cfg) && isfield(cfg,field) && ~isempty(cfg.(field))
        candidate = cfg.(field);
        if iscell(candidate) || isstring(candidate) || ischar(candidate)
            value = string(candidate(:)).';
        end
    end
end

function value = empty_capacity_table()
    names = {'load_mode','lambda_base','lambda_effective','M','Tp_us', ...
        'n_nodes','q_opt','ps_opt','service_cycle_us', ...
        'capacity_system_pkt_s','capacity_per_node_pkt_s', ...
        'offered_aggregate_pkt_s','offered_normalized_units_s','rho', ...
        'theory_stable'};
    types = [{'string'},repmat({'double'},1,13),{'logical'}];
    value = table('Size',[0 numel(names)],'VariableTypes',types, ...
                  'VariableNames',names);
end

function theory = build_theory_validation(conditions, cfg)
    conn_slot_us = analysis_conn_slot_us(cfg);
    node_capacity = max(1, round(config_scalar(cfg, 'n_nodes', 128)) + 2);
    rows = cell(max(1,numel(conditions)*node_capacity),1);
    row_count = 0;
    for ci = 1:numel(conditions)
        condition = conditions{ci};
        info = condition_info(condition, cfg);
        if ~strcmp(info.protocol, 'sf_cb'), continue; end
        runs = evaluation_runs(condition);
        if isempty(runs), continue; end

        all_k = zeros(0,1);
        all_frames = zeros(0,1);
        all_success = zeros(0,1);
        all_attempt_frames = zeros(0,1);
        all_attempts = zeros(0,1);
        observed_q = zeros(0,1);
        intercompletion = zeros(0,1);
        n_diag_runs = 0;

        for ri = 1:numel(runs)
            run = runs{ri};
            if ~isstruct(run), continue; end
            if isfield(run, 'diagnostics') && isstruct(run.diagnostics)
                d = run.diagnostics;
                k = numeric_vector(d, 'reservation_k_values');
                frames = numeric_vector(d, 'reservation_full_frames_by_k');
                successes = numeric_vector(d, 'reservation_success_frames_by_k');
                attempts = numeric_vector(d, 'reservation_attempts_by_k');
                attempts_available = ~isempty(attempts);
                attempt_frames = numeric_vector(d, 'reservation_frames_by_k');
                n = min([numel(k), numel(frames), numel(successes)]);
                if n > 0
                    k = k(1:n); frames = frames(1:n); successes = successes(1:n);
                    if numel(attempts) < n
                        attempts(end+1:n,1) = NaN;
                    else
                        attempts = attempts(1:n);
                    end
                    if numel(attempt_frames) < n
                        attempt_frames = frames;
                    else
                        attempt_frames = attempt_frames(1:n);
                    end
                    valid = isfinite(k) & isfinite(frames) & ...
                            isfinite(successes) & frames >= 0 & successes >= 0;
                    all_k = [all_k; k(valid)]; %#ok<AGROW>
                    all_frames = [all_frames; frames(valid)]; %#ok<AGROW>
                    all_success = [all_success; successes(valid)]; %#ok<AGROW>
                    all_attempt_frames = [all_attempt_frames; attempt_frames(valid)]; %#ok<AGROW>
                    all_attempts = [all_attempts; attempts(valid)]; %#ok<AGROW>
                    if ~attempts_available
                        all_attempts(end-nnz(valid)+1:end) = NaN;
                    end
                    n_diag_runs = n_diag_runs + 1;
                end
                q_run = scalar_field(d, {'q'});
                if isfinite(q_run), observed_q(end+1,1) = q_run; end %#ok<AGROW>
            end
            intercompletion = [intercompletion; ...
                run_intercompletion_intervals(run, cfg)]; %#ok<AGROW>
        end
        if isempty(all_k), continue; end

        max_k = max(all_k);
        if ~isfinite(max_k) || max_k < 0, continue; end
        indices = round(all_k) + 1;
        frame_by_k = accumarray(indices, all_frames, [round(max_k)+1,1], @nansum_local, 0);
        success_by_k = accumarray(indices, all_success, [round(max_k)+1,1], @nansum_local, 0);
        valid_attempt = isfinite(all_attempts);
        attempt_by_k = accumarray(indices(valid_attempt), all_attempts(valid_attempt), ...
            [round(max_k)+1,1], @sum, 0);
        if ~any(valid_attempt), attempt_by_k(:) = NaN; end
        attempt_frame_by_k = accumarray(indices, all_attempt_frames, ...
            [round(max_k)+1,1], @nansum_local, 0);

        q = info.best_q;
        if ~isfinite(q) && ~isempty(observed_q), q = mean(observed_q); end
        if ~isfinite(q) || q < 0 || q > 1, q = NaN; end
        empirical_intercompletion = safe_mean(intercompletion);

        positive_frame_total = 0;
        positive_success_total = 0;
        mixture_theory_numerator = 0;
        positive_attempt_total = 0;
        positive_attempt_trials = 0;

        for K = 1:max_k
            n_frames = frame_by_k(K+1);
            if n_frames <= 0, continue; end
            n_success = success_by_k(K+1);
            empirical_ps = n_success / n_frames;
            theory_ps = K*q*(1-q)^(K-1);
            [ci_low, ci_high, ci_method] = binomial_ci95(n_success, n_frames);
            if isfinite(theory_ps)
                in_ci = double(theory_ps >= ci_low && theory_ps <= ci_high);
            else
                in_ci = NaN;
            end
            attempts = attempt_by_k(K+1);
            n_attempt_frames = attempt_frame_by_k(K+1);
            attempt_trials = K*n_attempt_frames;
            if isfinite(attempts)
                empirical_attempt_probability = attempts/max(attempt_trials,1);
            else
                empirical_attempt_probability = NaN;
            end
            row_count = row_count + 1;
            rows{row_count,1} = theory_row(info, 'by_K', K, n_diag_runs, ...
                n_frames, n_success, empirical_ps, ci_low, ci_high, ...
                ci_method, theory_ps, in_ci, attempts, ...
                attempt_trials, empirical_attempt_probability, ...
                service_cycle_approx(info.Tp_us, theory_ps, conn_slot_us), ...
                service_cycle_approx(info.Tp_us, empirical_ps, conn_slot_us), NaN);

            positive_frame_total = positive_frame_total + n_frames;
            positive_success_total = positive_success_total + n_success;
            mixture_theory_numerator = mixture_theory_numerator + n_frames*theory_ps;
            if isfinite(attempts)
                positive_attempt_total = positive_attempt_total + attempts;
                positive_attempt_trials = positive_attempt_trials + attempt_trials;
            end
        end

        if positive_frame_total > 0
            empirical_ps = positive_success_total/positive_frame_total;
            mixture_theory_ps = mixture_theory_numerator/positive_frame_total;
            row_count = row_count + 1;
            if positive_attempt_trials > 0
                mixture_attempt_probability = positive_attempt_total/positive_attempt_trials;
                mixture_attempts = positive_attempt_total;
                mixture_attempt_trials = positive_attempt_trials;
            else
                mixture_attempt_probability = NaN;
                mixture_attempts = NaN;
                mixture_attempt_trials = NaN;
            end
            rows{row_count,1} = theory_row(info, 'condition_mixture', NaN, ...
                n_diag_runs, positive_frame_total, positive_success_total, ...
                empirical_ps, NaN, NaN, 'not_applicable_mixture', ...
                mixture_theory_ps, NaN, mixture_attempts, ...
                mixture_attempt_trials, ...
                mixture_attempt_probability, ...
                service_cycle_approx(info.Tp_us, mixture_theory_ps, conn_slot_us), ...
                service_cycle_approx(info.Tp_us, empirical_ps, conn_slot_us), ...
                empirical_intercompletion);
        end
    end

    if row_count == 0
        theory = empty_theory_table();
    else
        theory = struct2table(vertcat(rows{1:row_count}));
    end
end

function row = theory_row(info, row_type, K, n_runs, n_frames, n_success, ...
        empirical_ps, ci_low, ci_high, ci_method, theory_ps, in_ci, attempts, ...
        attempt_bernoulli_trials, empirical_attempt_probability, theory_cycle, empirical_ps_cycle, ...
        empirical_intercompletion)
    row = struct();
    row.row_type = string(row_type);
    row.protocol = string(info.protocol);
    row.load_mode = string(info.load_mode);
    row.lambda_base = info.lambda_base;
    row.lambda_effective = info.lambda_effective;
    row.M = info.M;
    row.Tp_us = info.Tp_us;
    row.q = info.best_q;
    row.K = K;
    row.n_eval_runs = n_runs;
    row.n_frames = n_frames;
    row.n_success = n_success;
    row.empirical_ps = empirical_ps;
    row.ci95_low = ci_low;
    row.ci95_high = ci_high;
    row.ci_method = string(ci_method);
    row.theoretical_ps = theory_ps;
    row.theory_inside_ci95 = in_ci;
    row.attempts = attempts;
    row.attempt_bernoulli_trials = attempt_bernoulli_trials;
    row.empirical_attempt_probability = empirical_attempt_probability;
    row.approx_service_cycle_theory_us = theory_cycle;
    row.approx_service_cycle_empirical_ps_us = empirical_ps_cycle;
    row.empirical_intercompletion_us = empirical_intercompletion;
end

function table_out = empty_theory_table()
    names = {'row_type','protocol','load_mode','lambda_base','lambda_effective', ...
        'M','Tp_us','q','K','n_eval_runs','n_frames','n_success','empirical_ps', ...
        'ci95_low','ci95_high','ci_method','theoretical_ps', ...
        'theory_inside_ci95','attempts','attempt_bernoulli_trials', ...
        'empirical_attempt_probability', ...
        'approx_service_cycle_theory_us', ...
        'approx_service_cycle_empirical_ps_us','empirical_intercompletion_us'};
    types = [{'string','string','string'}, repmat({'double'},1,12), ...
             {'string'}, repmat({'double'},1,8)];
    table_out = table('Size',[0 numel(names)], 'VariableTypes',types, ...
                      'VariableNames',names);
end

function [low, high, method] = binomial_ci95(successes, trials)
    low = NaN; high = NaN; method = 'not_available';
    if ~isfinite(successes) || ~isfinite(trials) || trials <= 0 || ...
            successes < 0 || successes > trials
        return;
    end
    successes = round(successes); trials = round(trials);
    alpha = 0.05;
    if exist('betainv', 'file') == 2
        if successes == 0
            low = 0;
        else
            low = betainv(alpha/2, successes, trials-successes+1);
        end
        if successes == trials
            high = 1;
        else
            high = betainv(1-alpha/2, successes+1, trials-successes);
        end
        method = 'Clopper-Pearson exact';
    else
        z = 1.95996398454005;
        p = successes/trials;
        denom = 1 + z^2/trials;
        center = (p + z^2/(2*trials))/denom;
        half = z*sqrt(p*(1-p)/trials + z^2/(4*trials^2))/denom;
        low = max(0, center-half);
        high = min(1, center+half);
        method = 'Wilson score';
    end
end

function value = service_cycle_approx(Tp_us, ps, conn_slot_us)
    if isfinite(Tp_us) && isfinite(ps) && ps > 0
        value = Tp_us + conn_slot_us/ps;
    else
        value = NaN;
    end
end

function intervals = run_intercompletion_intervals(run, cfg)
    intervals = zeros(0,1);
    if ~isfield(run, 'packet_log') || ~isstruct(run.packet_log) || ...
            ~isfield(run.packet_log, 'completion_us')
        return;
    end
    completion = double(run.packet_log.completion_us(:));
    completion = completion(isfinite(completion));
    left = config_scalar(cfg, 'warmup_us', -Inf);
    right = config_scalar(cfg, 'arrival_end_us', Inf);
    completion = sort(completion(completion >= left & completion < right));
    if numel(completion) >= 2
        intervals = diff(completion);
        intervals = intervals(isfinite(intervals) & intervals >= 0);
    end
end

function csma = build_csma_diagnostics(conditions, cfg)
    rows = cell(max(1,numel(conditions)),1);
    row_count = 0;
    for ci = 1:numel(conditions)
        condition = conditions{ci};
        info = condition_info(condition, cfg);
        if ~ismember(info.protocol, {'sb_cf','sb_cb'}), continue; end
        runs = evaluation_runs(condition);
        runs = runs(cellfun(@(r) isstruct(r) && isfield(r,'diagnostics') && ...
                                     isstruct(r.diagnostics), runs));
        if isempty(runs), continue; end

        row = struct();
        row.protocol = string(info.protocol);
        row.load_mode = string(info.load_mode);
        row.lambda_base = info.lambda_base;
        row.lambda_effective = info.lambda_effective;
        row.M = info.M;
        row.Tp_us = info.Tp_us;
        row.q = info.best_q;
        row.n_eval_runs = numel(runs);
        row.cca_mode = string(first_text_field(runs, 'cca_mode', ...
            config_text(cfg, 'cca_mode', 'unknown')));
        row.rx_sens_dbm = first_scalar_field(runs, {'rx_sens_dbm'}, ...
            config_scalar(cfg, 'rx_sens_dbm', NaN));
        if strcmp(info.protocol, 'sb_cf')
            row.cca_truth_definition = ...
                "classic collision: a new DATA frame overlaps any active DATA frame";
        else
            row.cca_truth_definition = ...
                "classic RTS overlap or counterfactual CTS/DATA SINR corruption";
        end

        row.raw_busy_opportunities = sum_metric(runs, ...
            {'raw_listening_busy_opportunities','cca_raw_busy_samples'});
        row.raw_misses = sum_metric(runs, ...
            {'raw_listening_misses','cca_raw_miss_samples'});
        row.raw_miss_rate = safe_ratio(row.raw_misses, row.raw_busy_opportunities);
        row.eligible_tp = sum_metric(runs, {'eligible_cca_tp','cca_eligible_tp'});
        row.eligible_fn = sum_metric(runs, {'eligible_cca_fn','cca_eligible_fn'});
        row.eligible_fp = sum_metric(runs, {'eligible_cca_fp','cca_eligible_fp'});
        row.eligible_tn = sum_metric(runs, {'eligible_cca_tn','cca_eligible_tn'});
        row.eligible_fnr = safe_ratio(row.eligible_fn, row.eligible_tp+row.eligible_fn);
        row.eligible_fpr = safe_ratio(row.eligible_fp, row.eligible_fp+row.eligible_tn);
        row.eligible_decodable_negative = sum_metric(runs, ...
            {'cca_eligible_decodable_negative'});
        row.eligible_self_undecodable = sum_metric(runs, ...
            {'eligible_self_undecodable_opportunities', ...
             'cca_eligible_self_undecodable'});
        row.eligible_control_harm = sum_metric(runs, ...
            {'cca_eligible_control_harm'});
        row.eligible_data_harm = sum_metric(runs, ...
            {'cca_eligible_data_harm'});
        row.eligible_rts_harm = sum_metric(runs, ...
            {'cca_eligible_rts_harm'});
        row.harmful_missed_opportunities = row.eligible_fn;
        row.false_alarm_opportunities = row.eligible_fp;
        row.sinr_harmful_start_attempts = sum_metric(runs, ...
            {'sinr_harmful_start_attempts'});
        row.single_user_harmful_start_attempts = sum_metric(runs, ...
            {'single_user_only_harmful_start_attempts'});
        row.late_start_handshake = sum_metric(runs, ...
            {'late_start_handshake'});
        row.late_start_data = sum_metric(runs, {'late_start_data'});
        row.late_start_attempts = sum_metric(runs, {'late_start_attempts'});
        row.simultaneous_start_events = sum_metric(runs, ...
            {'simultaneous_start_events','rts_simultaneous_events'});
        row.simultaneous_start_attempts = sum_metric(runs, ...
            {'simultaneous_start_attempts','rts_simultaneous_attempts'});
        row.capture_successes = sum_metric(runs, ...
            {'capture_successes','rts_capture_success'});
        row.classic_collision_events = sum_metric(runs, ...
            {'classic_collision_events','rts_collision_events'});
        row.classic_collision_attempts = sum_metric(runs, ...
            {'classic_collision_attempts','rts_collision_attempts'});
        row.rts_success = sum_metric(runs, {'rts_success'});
        row.rts_fail_collision = sum_metric(runs, {'rts_fail_collision'});
        if strcmp(info.protocol,'sb_cb')
            row.cts_sinr_th_db = first_scalar_field(runs, ...
                {'cts_sinr_th_db'},config_scalar(cfg,'cts_sinr_th_db',NaN));
            row.data_sinr_th_db = first_scalar_field(runs, ...
                {'data_sinr_th_db'},config_scalar(cfg,'data_sinr_th_db',NaN));
        else
            row.cts_sinr_th_db = NaN;
            row.data_sinr_th_db = NaN;
        end
        row.partial_collision_events = sum_metric(runs, ...
            {'partial_collisions','data_partial_collision_events'});
        row.full_collision_events = sum_metric(runs, ...
            {'data_full_collision_events'});
        row.icr_expected = sum_metric(runs, {'icr_expected'});
        row.icr_decoded = sum_metric(runs, {'icr_decoded'});
        row.icr_miss_halfduplex = sum_metric(runs, {'icr_miss_halfduplex'});
        row.icr_miss_low_sinr = sum_metric(runs, {'icr_miss_low_sinr'});
        row.icr_miss_sector_timing = sum_metric(runs, {'icr_miss_timing'});
        row.icr_winner_miss = sum_metric(runs, {'icr_winner_miss'});
        row.nav_expected = sum_metric(runs, {'nav_expected'});
        row.nav_set = sum_metric(runs, {'nav_set'});
        row.nav_not_set = sum_metric(runs, {'nav_fail'});
        row.nav_protection_violations = sum_metric(runs, ...
            {'nav_protected_violations'});
        row.failed_attempts_or_events = sum_available_metrics(runs, ...
            {{'failed_attempts'}, {'rts_fail_total'}, {'data_fail'}});
        row.rts_fail_total = sum_metric(runs, {'rts_fail_total'});
        row.rts_failure_detection_delay_us = sum_metric(runs, ...
            {'rts_failure_detection_delay_us'});
        row.mean_rts_failure_detection_delay_us = safe_ratio( ...
            row.rts_failure_detection_delay_us,row.rts_fail_total);
        row.data_fail_sinr = sum_metric(runs, {'data_fail_sinr'});
        row.data_failure_transaction_delay_us = sum_metric(runs, ...
            {'data_failure_transaction_delay_us'});
        row.mean_data_failure_transaction_delay_us = safe_ratio( ...
            row.data_failure_transaction_delay_us,row.data_fail_sinr);
        row.collision_waste_us = sum_metric(runs, ...
            {'collision_waste_us','data_wasted_us'});
        row.collision_channel_time_us = sum_metric(runs, ...
            {'collision_channel_time_us'});
        row.collision_tx_airtime_us = sum_metric(runs, ...
            {'collision_tx_airtime_us'});
        row_count = row_count + 1;
        rows{row_count,1} = row;
    end

    if row_count == 0
        csma = empty_csma_table();
    else
        csma = struct2table(vertcat(rows{1:row_count}));
    end
end

function table_out = empty_csma_table()
    names = {'protocol','load_mode','lambda_base','lambda_effective','M','Tp_us', ...
        'q','n_eval_runs','cca_mode','rx_sens_dbm','cca_truth_definition', ...
        'raw_busy_opportunities','raw_misses','raw_miss_rate','eligible_tp', ...
        'eligible_fn','eligible_fp','eligible_tn','eligible_fnr','eligible_fpr', ...
        'eligible_decodable_negative','eligible_self_undecodable', ...
        'eligible_control_harm','eligible_data_harm','eligible_rts_harm', ...
        'harmful_missed_opportunities','false_alarm_opportunities', ...
        'sinr_harmful_start_attempts','single_user_harmful_start_attempts', ...
        'late_start_handshake','late_start_data','late_start_attempts', ...
        'simultaneous_start_events','simultaneous_start_attempts', ...
        'capture_successes','classic_collision_events', ...
        'classic_collision_attempts','rts_success','rts_fail_collision', ...
        'cts_sinr_th_db','data_sinr_th_db', ...
        'partial_collision_events','full_collision_events', ...
        'icr_expected','icr_decoded','icr_miss_halfduplex','icr_miss_low_sinr', ...
        'icr_miss_sector_timing','icr_winner_miss','nav_expected','nav_set', ...
        'nav_not_set','nav_protection_violations','failed_attempts_or_events', ...
        'rts_fail_total','rts_failure_detection_delay_us', ...
        'mean_rts_failure_detection_delay_us','data_fail_sinr', ...
        'data_failure_transaction_delay_us', ...
        'mean_data_failure_transaction_delay_us','collision_waste_us'};
    names=[names,{'collision_channel_time_us','collision_tx_airtime_us'}];
    string_names = {'protocol','load_mode','cca_mode','cca_truth_definition'};
    types = repmat({'double'}, 1, numel(names));
    for i = 1:numel(string_names)
        types{strcmp(names,string_names{i})} = 'string';
    end
    table_out = table('Size',[0 numel(names)], 'VariableTypes',types, ...
                      'VariableNames',names);
end

function controlled = read_controlled_aloha_verification(output_dir, cfg)
    path = fullfile(output_dir,'verification','aloha_controlled', ...
                    'aloha_theory_validation.csv');
    controlled = struct( ...
        'source',string(path),'file_status',"missing",'available',0, ...
        'schema_valid',0,'preregistered_parameters_valid',0, ...
        'n_nodes_expected',max(1,round(config_scalar(cfg,'n_nodes',40))), ...
        'K',NaN,'q',NaN,'trials',NaN,'successes',NaN, ...
        'empirical_ps',NaN,'theoretical_ps',NaN,'ci_low',NaN,'ci_high',NaN, ...
        'probability_pass',NaN,'service_relative_error',NaN, ...
        'probability_status',"not_applicable", ...
        'service_status',"not_applicable", ...
        'hard_gate_status',"not_applicable");
    if ~isfile(path), return; end
    controlled.file_status = "present";
    try
        data = readtable(path,'VariableNamingRule','preserve');
    catch
        controlled.file_status = "unreadable";
        controlled.hard_gate_status = "fail";
        return;
    end
    required = {'K','q','trials','successes','empirical_ps','theoretical_ps', ...
        'ci_low','ci_high','probability_pass','service_relative_error'};
    if height(data) ~= 1 || ~has_variables(data,required)
        controlled.file_status = "invalid_schema";
        controlled.hard_gate_status = "fail";
        return;
    end
    row = table2struct(data(1,:));
    for i = 1:numel(required)
        controlled.(required{i}) = numeric_alias(row,required(i),NaN);
    end
    controlled.schema_valid = double(all(isfinite([controlled.K,controlled.q, ...
        controlled.trials,controlled.successes,controlled.empirical_ps, ...
        controlled.theoretical_ps,controlled.ci_low,controlled.ci_high, ...
        controlled.probability_pass,controlled.service_relative_error])));
    expected_q = 1/controlled.n_nodes_expected;
    controlled.preregistered_parameters_valid = double( ...
        controlled.schema_valid && controlled.K == controlled.n_nodes_expected && ...
        abs(controlled.q-expected_q) <= 1e-12);
    if ~controlled.schema_valid
        controlled.file_status = "invalid_values";
        controlled.hard_gate_status = "fail";
        return;
    end
    controlled.available = 1;
    controlled.probability_status = pass_fail(1-controlled.probability_pass,0);
    controlled.service_status = pass_fail(abs(controlled.service_relative_error),0.05);
    if controlled.preregistered_parameters_valid && ...
            controlled.probability_status == "pass" && ...
            controlled.service_status == "pass"
        controlled.hard_gate_status = "pass";
    else
        controlled.hard_gate_status = "fail";
    end
end

function checks = build_acceptance_checks(summary, theory, controlled_aloha, cfg)
    if isempty(summary)
        checks = empty_acceptance_table();
        return;
    end
    rate_threshold = 0.05;
    little_threshold = 0.05;
    rows = cell(height(summary),1);
    for i = 1:height(summary)
        source = table2struct(summary(i,:));
        protocol = lower(text_value(source,'protocol','unknown'));
        load_mode = lower(text_value(source,'load_mode','unknown'));
        lambda_base = numeric_alias(source,{'lambda_base'},NaN);
        lambda_effective = numeric_alias(source,{'lambda_effective'},NaN);
        M = numeric_alias(source,{'M'},NaN);
        if ~isfinite(lambda_effective) && isfinite(lambda_base) && isfinite(M)
            if strcmp(load_mode,'fixed_payload')
                lambda_effective = lambda_base/M;
            else
                lambda_effective = lambda_base;
            end
        end
        stable_fraction = numeric_alias(source,{'stable_fraction'},NaN);
        stability_class = classify_stability(stable_fraction);
        arrival_rate = numeric_alias(source,{'arrival_rate_pkt_s'},NaN);
        goodput_rate = numeric_alias(source,{'goodput_pkt_s'},NaN);
        little_error = abs(numeric_alias(source,{'little_relative_error'},NaN));

        if stability_class == "stable" && isfinite(arrival_rate) && ...
                arrival_rate > 0 && isfinite(goodput_rate)
            rate_error = abs(goodput_rate-arrival_rate)/arrival_rate;
            rate_status = pass_fail(rate_error,rate_threshold);
        else
            rate_error = NaN;
            rate_status = "not_applicable";
        end
        if stability_class == "stable" && isfinite(little_error)
            little_status = pass_fail(little_error,little_threshold);
        else
            little_status = "not_applicable";
        end

        [n_probability_tests,coverage,all_inside,aloha_diagnostic_status] = ...
            aloha_probability_diagnostic(theory,protocol,load_mode, ...
                lambda_base,M);
        [controlled_fields,aloha_hard_status] = controlled_fields_for_protocol( ...
            controlled_aloha,protocol);
        overall = overall_acceptance(stability_class,protocol,rate_status, ...
            little_status,aloha_hard_status);
        rows{i} = struct( ...
            'protocol',string(protocol),'load_mode',string(load_mode), ...
            'lambda_base',lambda_base,'lambda_effective',lambda_effective, ...
            'M',M,'Tp_us',numeric_alias(source,{'Tp_us'}, ...
                analysis_conn_slot_us(cfg)*M), ...
            'best_q',numeric_alias(source,{'best_q'},NaN), ...
            'stable_fraction',stable_fraction, ...
            'stability_class',stability_class, ...
            'arrival_rate_pkt_s',arrival_rate, ...
            'goodput_pkt_s',goodput_rate, ...
            'rate_relative_error',rate_error, ...
            'rate_threshold',rate_threshold, ...
            'rate_check_status',rate_status, ...
            'little_relative_error',little_error, ...
            'little_threshold',little_threshold, ...
            'little_check_status',little_status, ...
            'n_aloha_probability_tests',n_probability_tests, ...
            'aloha_ci95_coverage_fraction',coverage, ...
            'aloha_ci95_all_inside',all_inside, ...
            'aloha_probability_check_status',aloha_diagnostic_status, ...
            'aloha_controlled_file_status',controlled_fields.file_status, ...
            'aloha_controlled_available',controlled_fields.available, ...
            'aloha_controlled_K',controlled_fields.K, ...
            'aloha_controlled_q',controlled_fields.q, ...
            'aloha_controlled_trials',controlled_fields.trials, ...
            'aloha_controlled_probability_pass',controlled_fields.probability_pass, ...
            'aloha_controlled_service_relative_error', ...
                controlled_fields.service_relative_error, ...
            'aloha_controlled_preregistered_parameters_valid', ...
                controlled_fields.preregistered_parameters_valid, ...
            'aloha_controlled_probability_status', ...
                controlled_fields.probability_status, ...
            'aloha_controlled_service_status',controlled_fields.service_status, ...
            'aloha_controlled_hard_gate_status',aloha_hard_status, ...
            'overall_status',overall);
    end
    checks = struct2table(vertcat(rows{:}));
end

function value = classify_stability(stable_fraction)
    if ~isfinite(stable_fraction)
        value = "unknown";
    elseif stable_fraction >= 1-1e-12
        value = "stable";
    elseif stable_fraction <= 1e-12
        value = "unstable";
    else
        value = "mixed";
    end
end

function status = pass_fail(value, threshold)
    if ~isfinite(value)
        status = "not_applicable";
    elseif value <= threshold+1e-12
        status = "pass";
    else
        status = "fail";
    end
end

function [n_tests,coverage,all_inside,status] = aloha_probability_diagnostic( ...
        theory,protocol,load_mode,lambda_base,M)
    n_tests = 0; coverage = NaN; all_inside = NaN;
    status = "not_applicable";
    if ~strcmp(protocol,'sf_cb') || isempty(theory) || ...
            ~has_variables(theory,{'row_type','protocol','load_mode', ...
                'lambda_base','M','n_frames','theory_inside_ci95'})
        return;
    end
    mask = theory.row_type == "by_K" & theory.protocol == string(protocol) & ...
        theory.load_mode == string(load_mode) & theory.n_frames >= 10 & ...
        abs(theory.lambda_base-lambda_base) <= 1e-9*max(1,abs(lambda_base)) & ...
        abs(theory.M-M) <= 1e-12 & isfinite(theory.theory_inside_ci95);
    values = double(theory.theory_inside_ci95(mask));
    n_tests = numel(values);
    if n_tests == 0, return; end
    coverage = mean(values);
    all_inside = double(all(values >= 1-1e-12));
    status = "diagnostic_only";
end

function [fields,status] = controlled_fields_for_protocol(controlled,protocol)
    fields = controlled;
    if strcmp(protocol,'sf_cb')
        status = controlled.hard_gate_status;
    else
        status = "not_applicable";
        numeric_fields = {'available','K','q','trials','probability_pass', ...
            'service_relative_error','preregistered_parameters_valid'};
        for i = 1:numel(numeric_fields), fields.(numeric_fields{i}) = NaN; end
        fields.file_status = "not_applicable";
        fields.probability_status = "not_applicable";
        fields.service_status = "not_applicable";
    end
end

function status = overall_acceptance(stability_class,protocol,rate_status, ...
        little_status,aloha_controlled_status)
    statuses = [rate_status little_status];
    if strcmp(protocol,'sf_cb'), statuses(end+1) = aloha_controlled_status; end
    if any(statuses == "fail")
        status = "fail";
    elseif stability_class ~= "stable" || any(statuses == "not_applicable")
        status = "not_applicable";
    else
        status = "pass";
    end
end

function output = empty_acceptance_table()
    names = {'protocol','load_mode','lambda_base','lambda_effective','M', ...
        'Tp_us','best_q','stable_fraction','stability_class', ...
        'arrival_rate_pkt_s','goodput_pkt_s','rate_relative_error', ...
        'rate_threshold','rate_check_status','little_relative_error', ...
        'little_threshold','little_check_status','n_aloha_probability_tests', ...
        'aloha_ci95_coverage_fraction','aloha_ci95_all_inside', ...
        'aloha_probability_check_status','aloha_controlled_file_status', ...
        'aloha_controlled_available','aloha_controlled_K','aloha_controlled_q', ...
        'aloha_controlled_trials','aloha_controlled_probability_pass', ...
        'aloha_controlled_service_relative_error', ...
        'aloha_controlled_preregistered_parameters_valid', ...
        'aloha_controlled_probability_status','aloha_controlled_service_status', ...
        'aloha_controlled_hard_gate_status','overall_status'};
    string_names = {'protocol','load_mode','stability_class', ...
        'rate_check_status','little_check_status', ...
        'aloha_probability_check_status','aloha_controlled_file_status', ...
        'aloha_controlled_probability_status','aloha_controlled_service_status', ...
        'aloha_controlled_hard_gate_status','overall_status'};
    types = repmat({'double'},1,numel(names));
    for i = 1:numel(string_names)
        types{strcmp(names,string_names{i})} = 'string';
    end
    output = table('Size',[0 numel(names)],'VariableTypes',types, ...
                   'VariableNames',names);
end

function output = build_cca_ablation_diagnostics(conditions, csv_summary, cfg)
    rows = cell(max(1,numel(conditions)+height(csv_summary)),1);
    keys = strings(0,1);
    count = 0;
    for i = 1:numel(conditions)
        row = cca_row_from_condition(conditions{i}, cfg);
        if isempty(row), continue; end
        key = cca_row_key(row);
        if any(keys == key), continue; end
        count = count + 1;
        rows{count} = row;
        keys(count,1) = key;
    end
    for i = 1:height(csv_summary)
        row = cca_row_from_struct(table2struct(csv_summary(i,:)), cfg);
        if isempty(row), continue; end
        key = cca_row_key(row);
        if any(keys == key), continue; end
        count = count + 1;
        rows{count} = row;
        keys(count,1) = key;
    end
    if count == 0
        output = empty_cca_ablation_table();
    else
        output = struct2table(vertcat(rows{1:count}));
        output = sortrows(output, ...
            {'protocol','load_mode','lambda_base','M','cca_variant','rx_sens_dbm'});
    end
end

function row = cca_row_from_condition(condition, cfg)
    row = [];
    info = condition_info(condition, cfg);
    if ~ismember(info.protocol, {'sb_cf','sb_cb'}), return; end
    source = struct();
    if isfield(condition,'row') && isstruct(condition.row)
        source = condition.row;
    end
    row = cca_row_from_struct(source, cfg);
    row.protocol = string(info.protocol);
    row.load_mode = string(info.load_mode);
    row.lambda_base = info.lambda_base;
    row.lambda_effective = info.lambda_effective;
    row.M = info.M;
    row.Tp_us = info.Tp_us;
    row.best_q = info.best_q;

    diagnostics = build_csma_diagnostics({condition}, cfg);
    if isempty(diagnostics), return; end
    row.n_eval_runs = diagnostics.n_eval_runs(1);
    if row.cca_mode == "unknown" || strlength(row.cca_mode) == 0
        row.cca_mode = diagnostics.cca_mode(1);
    end
    if ~isfinite(row.rx_sens_dbm)
        row.rx_sens_dbm = diagnostics.rx_sens_dbm(1);
    end
    if strlength(row.cca_variant) == 0 || row.cca_variant == "unknown"
        row.cca_variant = row.cca_mode;
    end
    fields = {'raw_busy_opportunities','raw_misses','raw_miss_rate', ...
        'eligible_tp','eligible_fn','eligible_fp','eligible_tn', ...
        'eligible_fnr','eligible_fpr','harmful_missed_opportunities', ...
        'false_alarm_opportunities','late_start_handshake', ...
        'late_start_data','late_start_attempts','failed_attempts_or_events', ...
        'rts_fail_total','rts_failure_detection_delay_us', ...
        'mean_rts_failure_detection_delay_us','data_fail_sinr', ...
        'data_failure_transaction_delay_us', ...
        'mean_data_failure_transaction_delay_us', ...
        'collision_channel_time_us','collision_tx_airtime_us'};
    for fi = 1:numel(fields)
        row.(fields{fi}) = diagnostics.(fields{fi})(1);
    end
end

function row = cca_row_from_struct(source, cfg)
    protocol = lower(text_value(source,'protocol','unknown'));
    if ~ismember(protocol, {'sb_cf','sb_cb'})
        row = [];
        return;
    end
    load_mode = lower(text_value(source,'load_mode','unknown'));
    lambda_base = numeric_alias(source, {'lambda_base'}, NaN);
    M = numeric_alias(source, {'M'}, NaN);
    lambda_effective = numeric_alias(source, {'lambda_effective'}, NaN);
    if ~isfinite(lambda_effective) && isfinite(lambda_base) && isfinite(M)
        if strcmp(load_mode,'fixed_payload')
            lambda_effective = lambda_base/M;
        else
            lambda_effective = lambda_base;
        end
    end
    cca_mode = text_alias(source, {'cca_mode'}, config_text(cfg,'cca_mode','unknown'));
    cca_variant = text_alias(source, {'cca_variant'}, cca_mode);
    row = struct( ...
        'protocol',string(protocol), 'load_mode',string(load_mode), ...
        'lambda_base',lambda_base, 'lambda_effective',lambda_effective, ...
        'M',M, 'Tp_us',numeric_alias(source,{'Tp_us'}, ...
            analysis_conn_slot_us(cfg)*M), ...
        'best_q',numeric_alias(source,{'best_q','q'},NaN), ...
        'q_source',string(text_alias(source,{'q_source'},'unknown')), ...
        'cca_variant',string(cca_variant), 'cca_mode',string(cca_mode), ...
        'rx_sens_dbm',numeric_alias(source,{'rx_sens_dbm'}, ...
            config_scalar(cfg,'rx_sens_dbm',NaN)), ...
        'n_eval_runs',numeric_alias(source,{'n_eval_runs'},NaN), ...
        'stable_fraction',numeric_alias(source,{'stable_fraction'},NaN), ...
        'mean_delay_us',numeric_alias(source,{'mean_delay_us'},NaN), ...
        'p95_delay_us',numeric_alias(source,{'p95_delay_us'},NaN), ...
        'normalized_goodput_units_s',numeric_alias(source, ...
            {'normalized_goodput_units_s'},NaN), ...
        'backlog_slope_pkt_s',numeric_alias(source,{'backlog_slope_pkt_s'},NaN), ...
        'raw_busy_opportunities',numeric_alias(source,{'raw_busy_opportunities'},NaN), ...
        'raw_misses',numeric_alias(source,{'raw_misses'},NaN), ...
        'raw_miss_rate',numeric_alias(source,{'raw_miss_rate'},NaN), ...
        'eligible_tp',numeric_alias(source,{'eligible_tp'},NaN), ...
        'eligible_fn',numeric_alias(source,{'eligible_fn'},NaN), ...
        'eligible_fp',numeric_alias(source,{'eligible_fp'},NaN), ...
        'eligible_tn',numeric_alias(source,{'eligible_tn'},NaN), ...
        'eligible_fnr',numeric_alias(source,{'eligible_fnr'},NaN), ...
        'eligible_fpr',numeric_alias(source,{'eligible_fpr'},NaN), ...
        'harmful_missed_opportunities',numeric_alias(source, ...
            {'harmful_missed_opportunities'},NaN), ...
        'false_alarm_opportunities',numeric_alias(source, ...
            {'false_alarm_opportunities'},NaN), ...
        'late_start_handshake',numeric_alias(source,{'late_start_handshake'},NaN), ...
        'late_start_data',numeric_alias(source,{'late_start_data'},NaN), ...
        'late_start_attempts',numeric_alias(source,{'late_start_attempts'},NaN), ...
        'failed_attempts_or_events',numeric_alias(source, ...
            {'failed_attempts_or_events'},NaN), ...
        'rts_fail_total',numeric_alias(source,{'rts_fail_total'},NaN), ...
        'rts_failure_detection_delay_us',numeric_alias(source, ...
            {'rts_failure_detection_delay_us'},NaN), ...
        'mean_rts_failure_detection_delay_us',numeric_alias(source, ...
            {'mean_rts_failure_detection_delay_us'},NaN), ...
        'data_fail_sinr',numeric_alias(source,{'data_fail_sinr'},NaN), ...
        'data_failure_transaction_delay_us',numeric_alias(source, ...
            {'data_failure_transaction_delay_us'},NaN), ...
        'mean_data_failure_transaction_delay_us',numeric_alias(source, ...
            {'mean_data_failure_transaction_delay_us'},NaN), ...
        'collision_channel_time_us',numeric_alias(source, ...
            {'collision_channel_time_us','collision_channel_time_us_total'},NaN), ...
        'collision_tx_airtime_us',numeric_alias(source, ...
            {'collision_tx_airtime_us','collision_tx_airtime_us_total'},NaN));
    if ~isfinite(row.raw_miss_rate)
        row.raw_miss_rate = safe_ratio(row.raw_misses,row.raw_busy_opportunities);
    end
    if ~isfinite(row.eligible_fnr)
        row.eligible_fnr = safe_ratio(row.eligible_fn,row.eligible_tp+row.eligible_fn);
    end
    if ~isfinite(row.eligible_fpr)
        row.eligible_fpr = safe_ratio(row.eligible_fp,row.eligible_fp+row.eligible_tn);
    end
    if ~isfinite(row.mean_rts_failure_detection_delay_us)
        row.mean_rts_failure_detection_delay_us = safe_ratio( ...
            row.rts_failure_detection_delay_us,row.rts_fail_total);
    end
    if ~isfinite(row.mean_data_failure_transaction_delay_us)
        row.mean_data_failure_transaction_delay_us = safe_ratio( ...
            row.data_failure_transaction_delay_us,row.data_fail_sinr);
    end
end

function key = cca_row_key(row)
    key = string(sprintf('%s|%s|%.17g|%.17g|%s|%s|%.17g', ...
        char(row.protocol),char(row.load_mode),row.lambda_base,row.M, ...
        char(row.cca_variant),char(row.cca_mode),row.rx_sens_dbm));
end

function output = empty_cca_ablation_table()
    row = cca_row_from_struct(struct('protocol','sb_cf'), struct());
    fields = fieldnames(row);
    string_fields = {'protocol','load_mode','q_source','cca_variant','cca_mode'};
    types = repmat({'double'},1,numel(fields));
    for i = 1:numel(string_fields)
        types{strcmp(fields,string_fields{i})} = 'string';
    end
    output = table('Size',[0 numel(fields)],'VariableTypes',types, ...
                   'VariableNames',fields);
end

function output = build_topology_cluster_ci(conditions, csv_summary, cfg)
    samples = collect_topology_samples(conditions, csv_summary, cfg);
    if isempty(samples)
        output = empty_topology_cluster_table();
        return;
    end
    condition_keys = strings(height(samples),1);
    for i = 1:height(samples)
        condition_keys(i) = topology_condition_key(samples(i,:));
    end
    keys = unique(condition_keys,'stable');
    rows = cell(numel(keys),1);
    count = 0;
    for ki = 1:numel(keys)
        sub = samples(condition_keys == keys(ki),:);
        seeds = unique(sub.topology_seed(isfinite(sub.topology_seed)),'stable');
        if isempty(seeds), continue; end
        cluster_rows = cell(numel(seeds),1);
        for si = 1:numel(seeds)
            cluster_rows{si} = collapse_topology_seed(sub(sub.topology_seed == seeds(si),:));
        end
        clusters = struct2table(vertcat(cluster_rows{:}));
        stable = clusters.stable_fraction;
        stable_mask = isfinite(stable) & stable >= 1-1e-12;
        all_stable = numel(stable_mask) == numel(seeds) && all(stable_mask);
        count = count + 1;
        row = struct( ...
            'protocol',clusters.protocol(1), ...
            'load_mode',clusters.load_mode(1), ...
            'lambda_base',clusters.lambda_base(1), ...
            'lambda_effective',safe_mean(clusters.lambda_effective), ...
            'M',clusters.M(1), 'Tp_us',clusters.Tp_us(1), ...
            'n_topology_clusters',numel(seeds), ...
            'topology_seeds',join(string(seeds.'),';'), ...
            'stable_topology_fraction',mean(stable_mask), ...
            'all_topologies_stable',all_stable);
        metrics = {'stable_fraction','mean_delay_us','p95_delay_us', ...
            'normalized_goodput_units_s','goodput_pkt_s', ...
            'backlog_slope_pkt_s','completion_ratio','jain_fairness'};
        for mi = 1:numel(metrics)
            values = clusters.(metrics{mi});
            if ismember(metrics{mi},{'mean_delay_us','p95_delay_us'}) && ~all_stable
                values(:) = NaN;
            end
            [mean_value,ci_value,n_value] = cluster_mean_ci(values);
            row.([metrics{mi} '_mean']) = mean_value;
            row.([metrics{mi} '_ci95']) = ci_value;
            row.([metrics{mi} '_n_clusters']) = n_value;
        end
        rows{count} = row;
    end
    if count == 0
        output = empty_topology_cluster_table();
    else
        output = struct2table(vertcat(rows{1:count}));
        output = sortrows(output,{'load_mode','lambda_base','M','protocol'});
    end
end

function samples = collect_topology_samples(conditions, csv_summary, cfg)
    rows = cell(max(1,numel(conditions)+height(csv_summary)),1);
    keys = strings(0,1);
    count = 0;
    for i = 1:numel(conditions)
        if ~isfield(conditions{i},'row') || ~isstruct(conditions{i}.row), continue; end
        row = topology_sample_from_struct(conditions{i}.row, cfg);
        if isempty(row), continue; end
        key = topology_sample_key(row);
        if any(keys == key), continue; end
        count = count + 1; rows{count} = row; keys(count,1) = key;
    end
    for i = 1:height(csv_summary)
        row = topology_sample_from_struct(table2struct(csv_summary(i,:)), cfg);
        if isempty(row), continue; end
        key = topology_sample_key(row);
        if any(keys == key), continue; end
        count = count + 1; rows{count} = row; keys(count,1) = key;
    end
    if count == 0
        samples = empty_topology_samples();
    else
        samples = struct2table(vertcat(rows{1:count}));
    end
end

function row = topology_sample_from_struct(source, cfg)
    protocol = lower(text_value(source,'protocol','unknown'));
    load_mode = lower(text_value(source,'load_mode','unknown'));
    topology_seed = numeric_alias(source,{'topology_seed'},NaN);
    M = numeric_alias(source,{'M'},NaN);
    lambda_base = numeric_alias(source,{'lambda_base'},NaN);
    if strcmp(protocol,'unknown') || strcmp(load_mode,'unknown') || ...
            ~isfinite(topology_seed) || ~isfinite(M) || ~isfinite(lambda_base)
        row = [];
        return;
    end
    lambda_effective = numeric_alias(source,{'lambda_effective'},NaN);
    if ~isfinite(lambda_effective)
        if strcmp(load_mode,'fixed_payload')
            lambda_effective = lambda_base/M;
        else
            lambda_effective = lambda_base;
        end
    end
    row = struct( ...
        'protocol',string(protocol),'load_mode',string(load_mode), ...
        'lambda_base',lambda_base,'lambda_effective',lambda_effective, ...
        'M',M,'Tp_us',numeric_alias(source,{'Tp_us'}, ...
            analysis_conn_slot_us(cfg)*M), ...
        'topology_seed',topology_seed, ...
        'stable_fraction',numeric_alias(source,{'stable_fraction'},NaN), ...
        'mean_delay_us',numeric_alias(source,{'mean_delay_us'},NaN), ...
        'p95_delay_us',numeric_alias(source,{'p95_delay_us'},NaN), ...
        'normalized_goodput_units_s',numeric_alias(source, ...
            {'normalized_goodput_units_s'},NaN), ...
        'goodput_pkt_s',numeric_alias(source,{'goodput_pkt_s'},NaN), ...
        'backlog_slope_pkt_s',numeric_alias(source,{'backlog_slope_pkt_s'},NaN), ...
        'completion_ratio',numeric_alias(source,{'completion_ratio'},NaN), ...
        'jain_fairness',numeric_alias(source,{'jain_fairness'},NaN));
end

function key = topology_sample_key(row)
    key = string(sprintf('%s|%s|%.17g|%.17g|%.17g', ...
        char(row.protocol),char(row.load_mode),row.lambda_base,row.M, ...
        row.topology_seed));
end

function key = topology_condition_key(row)
    key = string(sprintf('%s|%s|%.17g|%.17g', ...
        char(string(row.protocol)),char(string(row.load_mode)), ...
        double(row.lambda_base),double(row.M)));
end

function row = collapse_topology_seed(sub)
    row = struct('protocol',string(sub.protocol(1)), ...
        'load_mode',string(sub.load_mode(1)), ...
        'lambda_base',double(sub.lambda_base(1)), ...
        'lambda_effective',safe_mean(double(sub.lambda_effective)), ...
        'M',double(sub.M(1)),'Tp_us',double(sub.Tp_us(1)), ...
        'topology_seed',double(sub.topology_seed(1)));
    metrics = {'stable_fraction','mean_delay_us','p95_delay_us', ...
        'normalized_goodput_units_s','goodput_pkt_s', ...
        'backlog_slope_pkt_s','completion_ratio','jain_fairness'};
    for i = 1:numel(metrics)
        row.(metrics{i}) = safe_mean(double(sub.(metrics{i})));
    end
end

function [mean_value,ci_value,n] = cluster_mean_ci(values)
    values = double(values(:));
    values = values(isfinite(values));
    n = numel(values);
    if n == 0
        mean_value = NaN; ci_value = NaN;
    elseif n == 1
        mean_value = values; ci_value = NaN;
    else
        mean_value = mean(values);
        ci_value = tinv(0.975,n-1)*std(values)/sqrt(n);
    end
end

function output = empty_topology_samples()
    names = {'protocol','load_mode','lambda_base','lambda_effective','M','Tp_us', ...
        'topology_seed','stable_fraction','mean_delay_us','p95_delay_us', ...
        'normalized_goodput_units_s','goodput_pkt_s','backlog_slope_pkt_s', ...
        'completion_ratio','jain_fairness'};
    types = [{'string','string'},repmat({'double'},1,numel(names)-2)];
    output = table('Size',[0 numel(names)],'VariableTypes',types, ...
                   'VariableNames',names);
end

function output = empty_topology_cluster_table()
    base_names = {'protocol','load_mode','lambda_base','lambda_effective','M', ...
        'Tp_us','n_topology_clusters','topology_seeds', ...
        'stable_topology_fraction','all_topologies_stable'};
    metrics = {'stable_fraction','mean_delay_us','p95_delay_us', ...
        'normalized_goodput_units_s','goodput_pkt_s', ...
        'backlog_slope_pkt_s','completion_ratio','jain_fairness'};
    names = base_names;
    for i = 1:numel(metrics)
        names = [names,{[metrics{i} '_mean'],[metrics{i} '_ci95'], ...
                        [metrics{i} '_n_clusters']}]; %#ok<AGROW>
    end
    types = repmat({'double'},1,numel(names));
    types{strcmp(names,'protocol')} = 'string';
    types{strcmp(names,'load_mode')} = 'string';
    types{strcmp(names,'topology_seeds')} = 'string';
    types{strcmp(names,'all_topologies_stable')} = 'logical';
    output = table('Size',[0 numel(names)],'VariableTypes',types, ...
                   'VariableNames',names);
end

function path = plot_summary_metric(summary, metric, y_label, title_prefix, path, stable_only)
    if isempty(summary) || ~has_variables(summary, ...
            {'protocol','load_mode','lambda_base','M',metric})
        path = '';
        return;
    end
    protocol = string(summary.protocol);
    load_mode = string(summary.load_mode);
    lambda = double(summary.lambda_base);
    M = double(summary.M);
    y = double(summary.(metric));
    if stable_only
        if ~ismember('stable_fraction', summary.Properties.VariableNames)
            y(:) = NaN;
        else
            stable_fraction = double(summary.stable_fraction);
            y(stable_fraction < 1-1e-12) = NaN;
        end
    end
    valid_panel = ~ismissing(load_mode) & isfinite(lambda);
    panel_keys = unique(load_mode(valid_panel) + "|" + string(lambda(valid_panel)), 'stable');
    if isempty(panel_keys)
        path = '';
        return;
    end

    fig = figure('Visible','off','Color','w','Position',[100 100 1200 700]);
    cleanup = onCleanup(@() close(fig));
    layout = tiledlayout(fig, 'flow', 'TileSpacing','compact', 'Padding','compact');
    protocols = unique(protocol, 'stable');
    colors = lines(max(numel(protocols),1));
    for pi = 1:numel(panel_keys)
        parts = split(panel_keys(pi), '|');
        mode_i = parts(1); lambda_i = str2double(parts(2));
        ax = nexttile(layout);
        hold(ax, 'on'); grid(ax, 'on'); box(ax, 'on');
        for ri = 1:numel(protocols)
            mask = protocol == protocols(ri) & load_mode == mode_i & lambda == lambda_i;
            x_i = M(mask); y_i = y(mask);
            [x_i, order] = sort(x_i); y_i = y_i(order);
            if isempty(x_i), continue; end
            plot(ax, x_i, y_i, '-o', 'LineWidth',1.25, 'MarkerSize',4, ...
                'Color',colors(ri,:), 'DisplayName',display_protocol(protocols(ri)));
        end
        xlabel(ax, 'M'); ylabel(ax, y_label);
        title(ax, sprintf('%s, \\lambda_{base}=%g', ...
              display_load_mode(mode_i), lambda_i), 'Interpreter','tex');
        xticks(ax, unique(M(isfinite(M))));
        if strcmp(metric, 'mean_delay_us')
            set(ax, 'YScale','log');
        elseif strcmp(metric, 'stable_fraction')
            ylim(ax, [-0.05 1.05]);
        end
        if pi == 1, legend(ax, 'Location','best','Interpreter','none'); end
    end
    title(layout, title_prefix);
    exportgraphics(fig, path, 'Resolution',180);
end

function path = plot_delay_with_unstable(summary, path)
%PLOT_DELAY_WITH_UNSTABLE Overlay steady-state and conditional delay values.
% Stable points use the steady-state mean. Mixed/unstable points use only
% packets completed before the simulation cutoff, so they must not be read
% as estimates of stationary mean delay.
    required = {'protocol','load_mode','lambda_base','M', ...
                'stable_fraction','mean_delay_us'};
    if isempty(summary) || ~has_variables(summary, required)
        path = '';
        return;
    end

    protocol = string(summary.protocol);
    load_mode = string(summary.load_mode);
    lambda = double(summary.lambda_base);
    M = double(summary.M);
    stable_fraction = double(summary.stable_fraction);
    steady_delay = double(summary.mean_delay_us);
    delay = steady_delay;
    if ismember('conditional_mean_delay_us', summary.Properties.VariableNames)
        delay = double(summary.conditional_mean_delay_us);
    end
    stable_rows = stable_fraction >= 1-1e-12 & isfinite(steady_delay);
    delay(stable_rows) = steady_delay(stable_rows);

    valid_panel = ~ismissing(load_mode) & isfinite(lambda);
    panel_keys = unique(load_mode(valid_panel) + "|" + ...
                        string(lambda(valid_panel)), 'stable');
    if isempty(panel_keys)
        path = '';
        return;
    end

    protocols = unique(protocol, 'stable');
    colors = lines(max(numel(protocols),1));
    fig = figure('Visible','off','Color','w','Position',[80 80 1400 820]);
    cleanup = onCleanup(@() close(fig));
    layout = tiledlayout(fig, 'flow', 'TileSpacing','compact', ...
                         'Padding','compact');

    for pi = 1:numel(panel_keys)
        parts = split(panel_keys(pi), '|');
        mode_i = parts(1);
        lambda_i = str2double(parts(2));
        panel_mask = load_mode == mode_i & lambda == lambda_i;
        ax = nexttile(layout);
        hold(ax, 'on'); grid(ax, 'on'); box(ax, 'on');

        if pi == 1
            for ri = 1:numel(protocols)
                plot(ax,NaN,NaN,':','LineWidth',1.2, ...
                    'Color',colors(ri,:), ...
                    'DisplayName',display_protocol(protocols(ri)));
            end
            plot(ax,NaN,NaN,'o','LineStyle','none','MarkerSize',5, ...
                'Color',[0.1 0.1 0.1],'MarkerFaceColor',[0.1 0.1 0.1], ...
                'DisplayName','Stable mean');
            plot(ax,NaN,NaN,'^','LineStyle','none','MarkerSize',6, ...
                'Color',[0.1 0.1 0.1],'MarkerFaceColor','w', ...
                'DisplayName','Mixed: conditional mean');
            plot(ax,NaN,NaN,'x','LineStyle','none','MarkerSize',7, ...
                'LineWidth',1.5,'Color',[0.1 0.1 0.1], ...
                'DisplayName','Unstable: conditional mean');
        end

        for ri = 1:numel(protocols)
            mask = panel_mask & protocol == protocols(ri);
            x_i = M(mask);
            y_i = delay(mask);
            sf_i = stable_fraction(mask);
            [x_i, order] = sort(x_i);
            y_i = y_i(order);
            sf_i = sf_i(order);
            finite_i = isfinite(x_i) & isfinite(y_i) & y_i > 0;
            if ~any(finite_i), continue; end

            pale = 0.55*colors(ri,:) + 0.45*[1 1 1];
            plot(ax,x_i(finite_i),y_i(finite_i),':','LineWidth',1.0, ...
                'Color',pale,'HandleVisibility','off');

            stable_i = finite_i & sf_i >= 1-1e-12;
            mixed_i = finite_i & sf_i > 1e-12 & sf_i < 1-1e-12;
            unstable_i = finite_i & sf_i <= 1e-12;
            plot(ax,x_i(stable_i),y_i(stable_i),'o','LineStyle','none', ...
                'MarkerSize',5,'Color',colors(ri,:), ...
                'MarkerFaceColor',colors(ri,:),'HandleVisibility','off');
            plot(ax,x_i(mixed_i),y_i(mixed_i),'^','LineStyle','none', ...
                'MarkerSize',6,'LineWidth',1.25,'Color',colors(ri,:), ...
                'MarkerFaceColor','w','HandleVisibility','off');
            plot(ax,x_i(unstable_i),y_i(unstable_i),'x','LineStyle','none', ...
                'MarkerSize',7,'LineWidth',1.5,'Color',colors(ri,:), ...
                'HandleVisibility','off');
        end

        missing_n = sum(panel_mask & (~isfinite(delay) | delay <= 0));
        xlabel(ax, 'M');
        ylabel(ax, 'Delay (us, log scale)');
        title(ax, sprintf('%s, \\lambda_{base}=%g; no finite delay=%d', ...
              display_load_mode(mode_i), lambda_i, missing_n), ...
              'Interpreter','tex');
        xticks(ax, unique(M(isfinite(M))));
        finite_M = M(isfinite(M));
        if ~isempty(finite_M)
            xlim(ax,[min(finite_M)-0.15 max(finite_M)+0.15]);
        end
        set(ax, 'YScale','log');
        if pi == 1
            lgd = legend(ax,'Location','best','Interpreter','none');
            lgd.NumColumns = 2;
        end
    end
    title(layout, ['Steady-state delay plus conditional completed-packet delay ' ...
                   '(mixed/unstable markers are not steady-state means)']);
    exportgraphics(fig, path, 'Resolution',180);
end

function path = plot_theory_validation(theory, path)
    if isempty(theory), path = ''; return; end
    mask = theory.row_type == "by_K" & theory.K >= 1 & theory.n_frames > 0 & ...
           isfinite(theory.theoretical_ps) & isfinite(theory.empirical_ps);
    t = theory(mask,:);
    if isempty(t), path = ''; return; end
    fig = figure('Visible','off','Color','w','Position',[100 100 720 620]);
    cleanup = onCleanup(@() close(fig));
    ax = axes(fig); hold(ax,'on'); grid(ax,'on'); box(ax,'on');
    lower = t.empirical_ps - t.ci95_low;
    upper = t.ci95_high - t.empirical_ps;
    errorbar(ax, t.theoretical_ps, t.empirical_ps, lower, upper, 'o', ...
        'LineStyle','none','MarkerSize',4,'CapSize',3, ...
        'Color',[0.1 0.45 0.75], 'MarkerFaceColor',[0.1 0.45 0.75]);
    plot(ax, [0 1], [0 1], '--', 'Color',[0.25 0.25 0.25], 'LineWidth',1.2);
    xlim(ax,[0 1]); ylim(ax,[0 1]); axis(ax,'square');
    xlabel(ax, 'Theory  Kq(1-q)^{K-1}');
    ylabel(ax, 'Empirical reservation success probability');
    title(ax, 'SF-CB reservation-success validation (binomial 95% CI)');
    exportgraphics(fig, path, 'Resolution',180);
end

function path = plot_csma_diagnostics(csma, path)
    if isempty(csma), path = ''; return; end
    protocols = unique(csma.protocol, 'stable');
    values = nan(numel(protocols),3);
    for i = 1:numel(protocols)
        sub = csma(csma.protocol == protocols(i),:);
        values(i,1) = safe_ratio(sum_finite(sub.raw_misses), ...
                                 sum_finite(sub.raw_busy_opportunities));
        values(i,2) = safe_ratio(sum_finite(sub.eligible_fn), ...
                                 sum_finite(sub.eligible_tp)+sum_finite(sub.eligible_fn));
        values(i,3) = safe_ratio(sum_finite(sub.eligible_fp), ...
                                 sum_finite(sub.eligible_fp)+sum_finite(sub.eligible_tn));
    end
    if all(~isfinite(values),'all'), path = ''; return; end
    fig = figure('Visible','off','Color','w','Position',[100 100 800 520]);
    cleanup = onCleanup(@() close(fig));
    ax = axes(fig);
    hold(ax,'on');
    n_metrics = size(values,2);
    group_width = 0.78;
    bar_width = group_width/n_metrics;
    bar_handles = gobjects(n_metrics,1);
    for metric_index = 1:n_metrics
        offset = (metric_index-(n_metrics+1)/2)*bar_width;
        bar_handles(metric_index) = bar(ax, (1:numel(protocols))+offset, ...
            values(:,metric_index), bar_width, 'grouped');
    end
    grid(ax,'on'); box(ax,'on'); ylim(ax,[0 1]);
    xticks(ax,1:numel(protocols));
    xticklabels(ax,arrayfun(@display_protocol,protocols,'UniformOutput',false));
    ylabel(ax,'Rate');
    legend(ax,bar_handles, ...
           {'Raw listening miss','Eligible harmful miss (FN)','Eligible false alarm (FP)'}, ...
           'Location','best');
    title(ax,'Conn-CSMA CCA diagnostics (count-weighted across conditions)');
    exportgraphics(fig, path, 'Resolution',180);
end

function path = plot_cca_ablation(cca, path)
    if isempty(cca), path = ''; return; end
    plot_data = summarize_cca_variants(cca);
    if isempty(plot_data), path = ''; return; end
    x = 1:height(plot_data);
    labels = cellstr(plot_data.label);
    fig = figure('Visible','off','Color','w','Position',[100 100 1250 760]);
    cleanup = onCleanup(@() close(fig));
    layout = tiledlayout(fig,2,2,'TileSpacing','compact','Padding','compact');

    ax = nexttile(layout); hold(ax,'on'); grid(ax,'on'); box(ax,'on');
    bar(ax,x,[plot_data.eligible_fnr plot_data.eligible_fpr],'grouped');
    ylim(ax,[0 1]); ylabel(ax,'Rate'); title(ax,'Eligible CCA errors');
    legend(ax,{'Harmful miss (FN)','False alarm (FP)'},'Location','best');
    set_cca_plot_labels(ax,x,labels);

    ax = nexttile(layout); grid(ax,'on'); box(ax,'on');
    bar(ax,x,plot_data.stable_fraction,'FaceColor',[0.25 0.60 0.35]);
    ylim(ax,[0 1]); ylabel(ax,'Stable condition fraction');
    title(ax,'Stability across matched conditions');
    set_cca_plot_labels(ax,x,labels);

    ax = nexttile(layout); grid(ax,'on'); box(ax,'on');
    bar(ax,x,plot_data.relative_goodput,'FaceColor',[0.20 0.48 0.75]);
    ylabel(ax,'Goodput / best matched variant');
    title(ax,'Matched-condition normalized goodput');
    set_cca_plot_labels(ax,x,labels);

    ax = nexttile(layout); grid(ax,'on'); box(ax,'on');
    bar(ax,x,plot_data.relative_delay,'FaceColor',[0.85 0.48 0.16]);
    ylabel(ax,'Delay / lowest matched stable delay');
    title(ax,'Matched-condition normalized delay');
    set_cca_plot_labels(ax,x,labels);

    title(layout,'Conn-CSMA CCA ablation (conditions matched by protocol/load/lambda/M)');
    exportgraphics(fig,path,'Resolution',180);
end

function output = summarize_cca_variants(cca)
    n = height(cca);
    goodput_ratio = nan(n,1);
    delay_ratio = nan(n,1);
    base_keys = strings(n,1);
    for i = 1:n
        base_keys(i) = string(sprintf('%s|%s|%.17g|%.17g', ...
            char(cca.protocol(i)),char(cca.load_mode(i)), ...
            cca.lambda_base(i),cca.M(i)));
    end
    unique_base = unique(base_keys,'stable');
    for i = 1:numel(unique_base)
        mask = base_keys == unique_base(i);
        good = double(cca.normalized_goodput_units_s(mask));
        valid_good = good(isfinite(good));
        if ~isempty(valid_good) && max(valid_good) > 0
            goodput_ratio(mask) = good/max(valid_good);
        end
        delay = double(cca.mean_delay_us(mask));
        stable = double(cca.stable_fraction(mask)) >= 1-1e-12;
        valid_delay = delay(isfinite(delay) & stable);
        if ~isempty(valid_delay) && min(valid_delay) > 0
            local = nan(size(delay));
            local(stable) = delay(stable)/min(valid_delay);
            delay_ratio(mask) = local;
        end
    end
    variant_keys = cca.protocol + "|" + cca.cca_variant;
    keys = unique(variant_keys,'stable');
    rows = cell(numel(keys),1);
    for i = 1:numel(keys)
        mask = variant_keys == keys(i);
        first = find(mask,1);
        rows{i} = struct( ...
            'label',string(sprintf('%s / %s', ...
                display_protocol(cca.protocol(first)),char(cca.cca_variant(first)))), ...
            'n_conditions',nnz(mask), ...
            'eligible_fnr',safe_ratio(sum_finite(cca.eligible_fn(mask)), ...
                sum_finite(cca.eligible_tp(mask))+sum_finite(cca.eligible_fn(mask))), ...
            'eligible_fpr',safe_ratio(sum_finite(cca.eligible_fp(mask)), ...
                sum_finite(cca.eligible_fp(mask))+sum_finite(cca.eligible_tn(mask))), ...
            'mean_rts_failure_detection_delay_us',safe_ratio( ...
                sum_finite(cca.rts_failure_detection_delay_us(mask)), ...
                sum_finite(cca.rts_fail_total(mask))), ...
            'mean_data_failure_transaction_delay_us',safe_ratio( ...
                sum_finite(cca.data_failure_transaction_delay_us(mask)), ...
                sum_finite(cca.data_fail_sinr(mask))), ...
            'stable_fraction',safe_mean(double(cca.stable_fraction(mask))), ...
            'relative_goodput',safe_mean(goodput_ratio(mask)), ...
            'relative_delay',safe_mean(delay_ratio(mask)));
    end
    if isempty(rows), output = table(); else, output = struct2table(vertcat(rows{:})); end
end

function set_cca_plot_labels(ax,x,labels)
    xticks(ax,x); xticklabels(ax,labels); xtickangle(ax,30);
    set(ax,'TickLabelInterpreter','none');
end

function path = plot_topology_clusters(topology, path)
    if isempty(topology), path = ''; return; end
    delay = double(topology.mean_delay_us_mean);
    goodput = double(topology.normalized_goodput_units_s_mean);
    if all(~isfinite(delay)) && all(~isfinite(goodput)), path = ''; return; end
    labels = strings(height(topology),1);
    for i = 1:height(topology)
        labels(i) = string(sprintf('%s/%s/lambda=%g/M=%g', ...
            display_protocol(topology.protocol(i)), ...
            display_load_mode(topology.load_mode(i)), ...
            topology.lambda_base(i),topology.M(i)));
    end
    x = 1:height(topology);
    fig = figure('Visible','off','Color','w','Position',[100 100 1250 720]);
    cleanup = onCleanup(@() close(fig));
    layout = tiledlayout(fig,2,1,'TileSpacing','compact','Padding','compact');
    ax = nexttile(layout); hold(ax,'on'); grid(ax,'on'); box(ax,'on');
    errorbar(ax,x,delay,topology.mean_delay_us_ci95,'o', ...
        'LineStyle','none','CapSize',4,'Color',[0.12 0.45 0.72], ...
        'MarkerFaceColor',[0.12 0.45 0.72]);
    ylabel(ax,'Mean delay (us)'); title(ax,'Topology-cluster steady delay (t 95% CI)');
    set_topology_plot_labels(ax,x,labels);
    ax = nexttile(layout); hold(ax,'on'); grid(ax,'on'); box(ax,'on');
    errorbar(ax,x,goodput,topology.normalized_goodput_units_s_ci95,'o', ...
        'LineStyle','none','CapSize',4,'Color',[0.25 0.62 0.34], ...
        'MarkerFaceColor',[0.25 0.62 0.34]);
    ylabel(ax,'Normalized units/s'); title(ax,'Topology-cluster normalized goodput (t 95% CI)');
    set_topology_plot_labels(ax,x,labels);
    title(layout,'Robustness across independent topology seeds');
    exportgraphics(fig,path,'Resolution',180);
end

function set_topology_plot_labels(ax,x,labels)
    xticks(ax,x); xticklabels(ax,cellstr(labels)); xtickangle(ax,30);
    set(ax,'TickLabelInterpreter','none');
end

function write_chinese_report(path, output_dir, cfg, summary, theory, capacity, csma, ...
        acceptance, cca_ablation, topology, conditions, cca_conditions, ...
        topology_conditions, figure_paths)
    fid = fopen(path, 'w', 'n', 'UTF-8');
    if fid < 0
        error('analyze_experiment_v2:ReportWriteFailed', ...
              'Cannot write report: %s', path);
    end
    cleanup = onCleanup(@() fclose(fid));
    line = @(varargin) fprintf(fid, varargin{:});

    line('# 褰撳墠 Conn-Aloha 鐞嗚鈥斾豢鐪熷鐓ф姤鍛奬n\n');
    line('- 鐢熸垚鏃堕棿锛?s锛堟湰鏈烘椂鍖猴級\n', ...
         char(datetime('now','Format','yyyy-MM-dd HH:mm:ss')));
    line('- 鏁版嵁鐩綍锛歚%s`\n', strrep(output_dir, '\\', '/'));
    line('- `summary.csv` 鏉′欢鏁帮細%d锛涙垚鍔熻鍙栨鏌ョ偣锛?d銆俓n', ...
         height(summary), numel(conditions));
    line('- 鐩戝惉娑堣瀺妫€鏌ョ偣锛?d锛涙嫇鎵戦瞾妫掓€ф鏌ョ偣锛?d銆傜己澶辨鏌ョ偣鏃讹紝鍒嗘瀽鍣ㄤ細浠ョ浉搴?CSV 鐨勬潯浠剁骇姹囨€讳綔涓洪檷绾ц緭鍏ャ€俓n', ...
         numel(cca_conditions),numel(topology_conditions));
    line('- 绋虫€佹椂寤跺彛寰勶細鍙湁涓€涓潯浠剁殑鍏ㄩ儴鐙珛璇勪及 run 鍧囪鍒や负绋冲畾鏃讹紝鎵嶆姤鍛婅鏉′欢鐨勬湁闄愬潎鍊硷紱娣峰悎鎴栦笉绋冲畾鏉′欢涓嶄互瀹屾垚鍖呮潯浠跺潎鍊煎啋鍏呯ǔ鎬佸潎鍊笺€俓n');
    if isfield(cfg,'profile')
        line('- 杩愯妗ｄ綅锛歚%s`銆俓n',char(string(cfg.profile)));
    end
    if isfield(cfg,'profile') && strcmpi(char(string(cfg.profile)),'scaled')
        line(['\n> **宸ョ▼楠岃瘉闄愬畾**锛氭湰鐩綍鏉ヨ嚜鐭椂杞?`scaled` 妗ｄ綅', ...
            '锛坵arm-up %.0f us銆佹祴閲?%.0f us銆佹瘡鐐?%d 涓瘎浼?run銆?, ...
            '宸ョ▼绋冲畾閫熺巼瀹瑰樊 %.0f%%锛夈€傚畠鐢ㄤ簬瑕嗙洊鎵€鏈夊崗璁?M/璐熻浇杞淬€?, ...
            '鍙戠幇閫昏緫鍜屾満鍒惰秼鍔匡紝涓嶆浛浠?`full` 鐨?2 s warm-up銆?0 s ', ...
            '娴嬮噺銆?0 涓嫭绔嬫祦閲忕瀛愪笌 5%% 绋冲畾鎬х粨璁恒€備笅鏂硅嚜鍔ㄩ獙鏀?, ...
            '浠嶆晠鎰忎娇鐢ㄤ弗鏍?5%% 闂ㄦ锛屽洜姝ら€熺巼/Little 澶辫触涓昏琛ㄧず褰撳墠', ...
            '鏍锋湰绐椾笉瓒筹紝涓嶈兘瑙ｉ噴鎴愬寘瀹堟亽鎴栧崗璁椂搴忓け璐ャ€俓n\n'], ...
            cfg.warmup_us,cfg.measure_us,cfg.n_eval_runs, ...
            100*cfg.stability_rate_tolerance);
    elseif isfield(cfg,'profile') && strcmpi(char(string(cfg.profile)),'analysis')
        line(['\n> **鍒嗘瀽妗ｄ綅闄愬畾**锛氭湰鐩綍淇濈暀瀹屾暣216鐐逛富鐭╅樀锛屼娇鐢?, ...
            'warm-up %.0f us銆佹祴閲?%.0f us銆佹帓绌?%.0f us銆佹瘡鐐?%d 涓?, ...
            '鐙珛璇勪及 run鍜屽伐绋嬮€熺巼瀹瑰樊 %.0f%%銆傚畠姣?`scaled` 鏇撮€傚悎', ...
            '姣旇緝鏈哄埗瓒嬪娍锛屼絾鐙珛鏍锋湰浠嶅彧鏈変袱涓紝涔熶笉閲嶅CCA/鎷撴墤娑堣瀺锛?, ...
            '姝ｅ紡璁烘枃绋冲畾杈圭晫浠嶄互 `full` 鎴栦笓椤归暱鏃堕獙璇佷负鍑嗐€備笅鏂逛弗鏍?, ...
            '5%%楠屾敹澶辫触搴旂粨鍚堟牱鏈獥鍜岀疆淇″尯闂磋В閲娿€傝皟浼樻寜鑱氬悎璐熻浇浣跨敤', ...
            '杞?涓?閲嶄笁缁?q 缃戞牸锛涗綆鍒拌揪鐜囪皟浼樻渶澶氬欢闀垮埌 %.0f us锛屼互', ...
            '鍑忓皯鐭獥鍙ｉ浂鍒拌揪鍜屽浐瀹氫綆 q 鍋忓樊銆俓n\n'], ...
            cfg.warmup_us,cfg.measure_us,cfg.drain_max_us,cfg.n_eval_runs, ...
            100*cfg.stability_rate_tolerance,cfg.tune_measure_max_us);
    else
        line('\n');
    end

    line('## 1. 妯″瀷杈圭晫涓庡叕骞冲彛寰刓n\n');
    report_mmw_slot_us = analysis_mmw_slot_us(cfg);
    report_conn_slot_us = analysis_conn_slot_us(cfg);
    report_phase_count = round(report_conn_slot_us/report_mmw_slot_us);
    report_phase_wait_us = (report_conn_slot_us-report_mmw_slot_us)/2;
    line(['涓诲疄楠岀殑鎵€鏈夊崗璁叡浜?%.0f us 鐗╃悊鍒拌揪杞ㄨ抗锛涘崗璁彧鑳藉湪鑷繁鐨勫悎娉曠珵浜夎竟鐣岃鍔紝鍥犳涓棿鍒拌揪浜х敓鐨勮竟鐣岀瓑寰呮槸鐪熷疄鎺ュ叆鏃跺欢鐨勪竴閮ㄥ垎銆?, ...
        '鑻ュ埌杈剧浉浣嶅湪 %d 涓?%.0f us 鐩镐綅涓婂潎鍖€锛岀瓑寰呬笅涓€涓?%.0f us 杈圭晫鐨勫潎鍊间负 %.1f us锛屽嵆 %.4f 涓绾﹀抚銆?, ...
        '鐞嗚杈圭晫鏍￠獙鎵嶅簲鎶婂埌杈惧己鍒跺榻愬埌 %.0f us锛涙寮忓叕骞冲姣斾笉搴旀寜鍚勫崗璁椂闅欏彟閫犲埌杈俱€俓n\n'], ...
        report_mmw_slot_us,report_phase_count,report_mmw_slot_us, ...
        report_conn_slot_us,report_phase_wait_us, ...
        report_phase_wait_us/report_conn_slot_us,report_conn_slot_us);
    line('- `fixed_packet`锛氭瘡涓妭鐐圭殑鍖呭埌杈剧巼鍥哄畾锛孧 澧炲ぇ鏃朵笟鍔￠噺闅忓寘闀垮澶с€俓n');
    line('- `fixed_payload`锛氫娇鐢?`lambda_effective=lambda_base/M`锛屼娇褰掍竴鍖栨湁鏁堣浇鑽疯緭鍏ヨ繎浼煎浐瀹氥€俓n');
    line('杩欎袱绉嶈礋杞藉畾涔夊湪鎵€鏈夎〃鍜屽浘涓弗鏍煎垎寮€锛屼笉鑳芥贩鍚堝钩鍧囥€俓n\n');

    write_stability_section(line, summary);
    write_acceptance_section(line, acceptance);
    write_theory_section(line, theory);
    write_capacity_section(line, capacity, cfg);
    write_csma_section(line, csma);
    write_cca_ablation_section(line, cca_ablation);
    write_conn_comparison_section(line, summary, cfg);
    write_topology_section(line, topology);

    line('## 8. 璁烘枃鎵归噺妯″瀷涓庡綋鍓嶅疄鐜颁笉鑳界洿鎺ヤ簰鎹n\n');
    line(['璁烘枃妯″瀷鍦ㄤ竴娆¤繛鎺ュ缓绔嬪悗鍙戦€佺敱 M 涓姹傛椂闅欏搴旂殑鎵归噺鏁版嵁锛屽苟鍖呭惈褰㈡垚璇ユ壒娆＄殑绛夊緟鏈哄埗銆?, ...
        '褰撳墠 SF-CB 鏄€滀竴涓?%.0f us 棰勭害甯ф垚鍔熷悗锛屽彂閫佷竴涓寔缁?`Tp=%.0fM us` 鐨勯暱鍖呪€濓紝娌℃湁褰㈡垚 M 鍖呮壒娆＄殑绛夊緟銆?, ...
        '涓よ€呯殑鎺у埗寮€閿€鎽婇攢鏂瑰悜鐩镐技锛屼絾闃熷垪鐘舵€併€佹壒閲忓舰鎴愮瓑寰呫€佷竴娆℃湇鍔＄Щ闄ょ殑鍖呮暟浠ュ強鍒拌揪鐩镐綅绛夊緟涓嶅悓銆?, ...
        '鍥犳鍙互姣旇緝棰勭害鎴愬姛姒傜巼鍜屽紑閿€鎽婇攢瓒嬪娍锛屽嵈涓嶈兘鎶婅鏂囨€绘椂寤跺叕寮忕洿鎺ュ綋浣滃綋鍓嶅疄鐜扮殑鐞嗚鏇茬嚎锛?, ...
        '鍑虹幇 1鈥? 涓?M 鐨勬渶浼樼偣鍋忕Щ骞朵笉鍗曠嫭璇佹槑浠ｇ爜閿欒銆俓n\n'], ...
        report_conn_slot_us,report_conn_slot_us);

    line('## 9. 鏈嶅姟鍛ㄦ湡杩戜技鐨勯€傜敤鑼冨洿\n\n');
    line(['`Tp + %.0f/Ps` 鏄浐瀹氱Н鍘嬭妭鐐规暟 K銆佺嫭绔?Bernoulli 灏濊瘯銆佹瘡娆″崟渚嬮绾﹀悗绔嬪嵆鍙戦€佷竴涓暱鍖呮椂鐨勮繎浼笺€?, ...
        '鐪熷疄浠跨湡涓?K 浼氶殢鍒拌揪涓庡畬鎴愬彉鍖栵紝鎴愬姛鍚庣殑 Tp 鏁版嵁闃舵浼氬喕缁撲笅涓€娆￠绾︼紝绌虹郴缁熼樁娈靛拰鎺掔┖鏈熶篃浼氭敼鍙樼浉閭诲畬鎴愰棿闅斻€?, ...
        '鍥犳鎶ュ憡鍚屾椂缁欏嚭锛氭寜缁忛獙 K 鍒嗗竷鍔犳潈鐨勭悊璁?Ps銆佺敱缁忛獙 Ps 浠ｅ叆鐨勫懆鏈熶及璁★紝浠ュ強瀹屾垚鏃堕棿鎴崇洿鎺ュ緱鍒扮殑缁忛獙鐩搁偦瀹屾垚闂撮殧銆?, ...
        '鍚庝袱鑰呬笉鏄悓涓€涓粺璁￠噺锛屼笉搴旀湡寰呴€愮偣涓ユ牸鐩哥瓑銆俓n\n'], ...
        report_conn_slot_us);

    line('## 10. 杈撳嚭鏂囦欢涓庤В璇婚檺鍒禱n\n');
    line('- `theory_validation.csv`锛氭寜 K 鐨勯绾︽垚鍔熺巼銆佷簩椤?95%% CI銆佺悊璁哄€煎強鏈嶅姟鍛ㄦ湡杩戜技锛沗condition_mixture` 琛屾槸缁忛獙 K 娣峰悎锛屼笉浣跨敤鍚屽垎甯冧簩椤?CI銆俓n');
    line('- `aloha_capacity_theory.csv`锛氫互 `q*=1/N` 鍜屽浐瀹氱Н鍘?K=N 鎺ㄥ鐨?SF-CB 楗卞拰鏈嶅姟鑳藉姏銆佷笟鍔¤緭鍏ャ€乺ho 涓庣悊璁虹ǔ瀹氭爣璁般€俓n');
    line('- `csma_diagnostics.csv`锛氫粠璇勪及妫€鏌ョ偣鎸夋潯浠舵眹鎬荤殑 CCA銆佹櫄鍚姩銆佺粡鍏窻TS/DATA纰版挒銆丆TS/DATA SINR銆両CR鍜孨AV璇婃柇锛沗collision_channel_time_us` 鏄鎾炲尯闂村苟闆嗙殑澧欓挓鏃堕棿锛宍collision_tx_airtime_us` 鏄け璐ュ彂閫佽€呯┖鍙ｆ椂闂翠箣鍜岋紝鍚庤€呭湪澶氬彂閫佽€呯鎾炴椂鍙互鏇村ぇ銆俓n');
    line('- `cca_ablation_diagnostics.csv`锛氫繚鐣?`cca_variant/cca_mode/rx_sens_dbm` 鐨勭洃鍚秷铻嶆€ц兘銆佺ǔ瀹氭€у拰鏈夋晥 TP/FN/FP/TN銆俓n');
    line('- `topology_cluster_ci.csv`锛氬厛鎶婂悓涓€ topology seed 鍐呯殑 run 鍘嬬缉鎴愪竴涓潯浠跺潎鍊硷紝鍐嶄互 topology seed 涓虹嫭绔嬫牱鏈绠?t 鍒嗗竷 95%% CI锛涚粷涓嶆寜鍖呰绠楁€ц兘缃俊鍖洪棿銆俓n');
    line('- `acceptance_checks.csv`锛氶€愪富鏉′欢缁欏嚭绋冲畾鎬у垎绫汇€佸埌杈?瀹屾垚閫熺巼鐩稿璇樊銆丩ittle 瀹氬緥璇樊銆佷富瀹為獙 Aloha K-bin 璇婃柇锛屼互鍙婄嫭绔嬪彈鎺?Aloha 纭棬鐘舵€併€俓n');
    if isempty(figure_paths)
        line('- 褰撳墠閮ㄥ垎缁撴灉涓嶈冻浠ョ敓鎴愬浘銆俓n');
    else
        line('- 宸茬敓鎴?%d 寮犲浘锛屼綅浜?`figures/`銆俓n', numel(figure_paths));
    end
    line('\n涓诲疄楠?`summary.csv` 鐨?CI 浠ョ嫭绔?run 涓哄崟浣嶏紱鎷撴墤椴佹鎬?CI 浠?topology seed 涓哄崟浣嶏紱棰勭害姒傜巼鏍￠獙鐨勪簩椤?CI 鍙拡瀵瑰悓涓€ K 鐨勯绾﹀抚璇曢獙銆備笁绉嶅尯闂寸殑鎶芥牱鍗曚綅涓嶅悓锛屼笉鑳戒簰鐩告浛浠ｃ€俓n');
end

function write_stability_section(line, summary)
    line('## 2. 绋冲畾鎬т笌鎬ц兘缁撴灉\n\n');
    needed = {'protocol','load_mode','stable_fraction'};
    if isempty(summary) || ~has_variables(summary, needed)
        line('褰撳墠姹囨€讳腑娌℃湁瓒冲鐨勭ǔ瀹氭€у瓧娈点€俓n\n');
        return;
    end
    protocol = string(summary.protocol);
    mode = string(summary.load_mode);
    sf = double(summary.stable_fraction);
    line('| 璐熻浇鍙ｅ緞 | 鍗忚 | 鍏ㄩ儴 run 绋冲畾 | 娣峰悎 | 鍏ㄩ儴涓嶇ǔ瀹?|\n');
    line('|---|---:|---:|---:|---:|\n');
    modes = unique(mode,'stable');
    protocols = unique(protocol,'stable');
    for mi = 1:numel(modes)
        for pi = 1:numel(protocols)
            mask = mode == modes(mi) & protocol == protocols(pi);
            if ~any(mask), continue; end
            stable_n = sum(sf(mask) >= 1-1e-12);
            unstable_n = sum(sf(mask) <= 1e-12);
            mixed_n = sum(sf(mask) > 1e-12 & sf(mask) < 1-1e-12);
            line('| %s | %s | %d | %d | %d |\n', ...
                 display_load_mode(modes(mi)), display_protocol(protocols(pi)), ...
                 stable_n, mixed_n, unstable_n);
        end
    end
    line('\n鍚炲悙鍜岀Н鍘嬫枩鐜囦粛鍙敤浜庤瘑鍒笉绋冲畾鏉′欢锛屼絾涓嶇ǔ瀹氭潯浠朵笅鈥滃凡瀹屾垚鍖呯殑鏈夐檺骞冲潎鏃跺欢鈥濆彈鍒犲け鍋忓樊褰卞搷锛屾晠鏈姤鍛婁笉鎶婂畠浣滀负绋虫€佹椂寤躲€俓n\n');
end

function write_acceptance_section(line, checks)
    line('## 2.1 鑷姩楠屾敹闂ㄦ\n\n');
    if isempty(checks)
        line('褰撳墠涓绘眹鎬讳负绌猴紝鏃犳硶鎵ц鏉′欢绾ч獙鏀躲€俓n\n');
        return;
    end
    n_pass = nnz(checks.overall_status == "pass");
    n_fail = nnz(checks.overall_status == "fail");
    n_na = nnz(checks.overall_status == "not_applicable");
    rate_fail = nnz(checks.rate_check_status == "fail");
    little_fail = nnz(checks.little_check_status == "fail");
    aloha_fail = nnz(checks.aloha_controlled_hard_gate_status == "fail");
    line('鍏辨鏌?%d 涓富鏉′欢锛氶€氳繃 %d锛屽け璐?%d锛宍not_applicable` %d銆傞€熺巼瀹堟亽澶辫触 %d锛孡ittle 瀹氬緥澶辫触 %d锛孲F-CB 鍙楁帶纭棬澶辫触 %d銆俓n\n', ...
         height(checks),n_pass,n_fail,n_na,rate_fail,little_fail,aloha_fail);
    line('閫熺巼涓?Little 瀹氬緥闂ㄦ鍧囦负鐩稿璇樊涓嶈秴杩?5%%锛屼笖鍙湪 `stable_fraction=1` 鏃堕€傜敤銆備富瀹為獙涓姩鎬?K 鐨勫垎绠变笉鏄娉ㄥ唽鐙珛妫€楠岋細浠呬繚鐣?`n_frames>=10` 鐨?coverage 璇婃柇锛屼笉杩涘叆 overall 纭棬锛屼篃涓嶈兘瑕佹眰鎵€鏈夋湭鏍℃ 95%% CI 鍚屾椂瑕嗙洊銆係F-CB 鐨勬鐜囩‖闂ㄥ彧璇诲彇 `verification/aloha_controlled/aloha_theory_validation.csv` 涓崟涓€棰勬敞鍐?`K=N銆乹=1/N` 鍙楁帶璇曢獙锛屽苟鍚屾椂妫€鏌ユ湇鍔″懆鏈熻宸笉瓒呰繃 5%%銆俓n\n');
    sf = checks.protocol == "sf_cb";
    if any(sf & checks.aloha_controlled_file_status == "missing")
        line('> 褰撳墠鐩綍缂哄皯鍙楁帶楠岃瘉鏂囦欢锛涚浉鍏?SF-CB 鏉′欢鐨勭‖闂ㄤ负 `not_applicable`锛屽繀椤诲崟鐙繍琛?`validate_aloha_theory_v2` 鎴栫敱瀹為獙棰勬鐢熸垚璇ユ枃浠讹紝涓嶈兘鎹璇姤閫氳繃鎴栧け璐ャ€俓n\n');
    end
    line('瀛楁缂哄け銆侀潪 SF-CB 姒傜巼椤广€佹贩鍚堟垨涓嶇ǔ瀹氭潯浠舵槑纭涓?`not_applicable`锛屼笉浼氳褰撲綔閫氳繃銆俓n\n');

    failed = checks(checks.overall_status == "fail",:);
    if isempty(failed)
        line('褰撳墠鍙墽琛岄棬妲涗腑娌℃湁澶辫触鏉′欢銆俓n\n');
        return;
    end
    line('澶辫触鏉′欢锛歕n\n');
    line('| 鍗忚/鏉′欢 | 绋冲畾鎬?| 閫熺巼璇樊/鐘舵€?| Little璇樊/鐘舵€?| 涓诲疄楠孠-bin璇婃柇coverage | 鍙楁帶纭棬 |\n');
    line('|---|---:|---:|---:|---:|---:|\n');
    max_rows = min(30,height(failed));
    for i = 1:max_rows
        label = sprintf('%s/%s/lambda=%g/M=%g', ...
            display_protocol(failed.protocol(i)), ...
            display_load_mode(failed.load_mode(i)), ...
            failed.lambda_base(i),failed.M(i));
        line('| %s | %s | %s / %s | %s / %s | %s / %s | %s |\n', ...
            label,failed.stability_class(i), ...
            format_percent(failed.rate_relative_error(i)), ...
            failed.rate_check_status(i), ...
            format_percent(failed.little_relative_error(i)), ...
            failed.little_check_status(i), ...
            format_percent(failed.aloha_ci95_coverage_fraction(i)), ...
            failed.aloha_probability_check_status(i), ...
            failed.aloha_controlled_hard_gate_status(i));
    end
    if height(failed) > max_rows
        line('| 鈥?| 鈥?| 鈥?| 鈥?| 鈥?| 鈥?|\n');
    end
    line('\n');
end

function write_theory_section(line, theory)
    line('## 3. SF-CB 棰勭害鎴愬姛姒傜巼楠岃瘉\n\n');
    if isempty(theory)
        line('褰撳墠妫€鏌ョ偣涓病鏈夊彲鐢ㄧ殑 SF-CB 璇勪及璇婃柇銆俓n\n');
        return;
    end
    mask = theory.row_type == "by_K" & theory.K >= 1 & theory.n_frames > 0 & ...
           isfinite(theory.empirical_ps) & isfinite(theory.theoretical_ps);
    t = theory(mask,:);
    if isempty(t)
        line('娌℃湁 K>0 鐨勫畬鏁撮绾﹀抚鍙敤浜庢牎楠屻€俓n\n');
        return;
    end
    enough = t.n_frames >= 10;
    if any(enough)
        coverage = mean(t.theory_inside_ci95(enough),'omitnan');
        weights = t.n_frames(enough);
        rmse = sqrt(sum(weights.*(t.empirical_ps(enough)-t.theoretical_ps(enough)).^2) ...
                    /sum(weights));
        line('鍏辨湁 %d 涓?`(鏉′欢,K)` 鐐癸紝鍏朵腑 %d 涓嚦灏戝寘鍚?10 涓畬鏁撮绾﹀抚銆傚杩欎簺鐐癸紝鐞嗚鍊艰惤鍏ヤ簩椤?95%% CI 鐨勬瘮渚嬩负 %s锛屽姞鏉?RMSE 涓?%s銆俓n\n', ...
             height(t), sum(enough), format_percent(coverage), format_number(rmse));
    else
        line('宸叉湁 %d 涓?`(鏉′欢,K)` 鐐癸紝浣嗘瘡鐐瑰畬鏁撮绾﹀抚鍧囧皯浜?10锛屽綋鍓嶆牱鏈笉瓒充互鍒ゆ柇姒傜巼妯″瀷銆俓n\n', height(t));
    end
    q_error = abs(t.empirical_attempt_probability-t.q);
    q_valid = isfinite(q_error) & t.n_frames >= 10;
    if any(q_valid)
        line('Bernoulli 灏濊瘯姒傜巼鐨勫姞鏉冨钩鍧囩粷瀵瑰亸宸负 %s锛涘畠鐢ㄤ簬鍏堟牳鏌ラ殢鏈哄皾璇曞疄鐜帮紝鍐嶈В閲婃垚鍔熺巼鍋忓樊銆俓n\n', ...
             format_number(sum(t.n_frames(q_valid).*q_error(q_valid))/sum(t.n_frames(q_valid))));
    end
    line('杩欓噷鐨勫姩鎬?K 鍒嗙鍙敤浜庢ā鍨嬭瘖鏂€傜敱浜庡悓鏃舵鏌ヨ澶?K-bin锛屼笉鑳芥妸鈥滄墍鏈夋湭鏍℃ 95%% CI 閮借鐩栤€濅綔涓轰富瀹為獙纭獙鏀讹紱绋€鐤忓垎绠变篃涓嶅弬涓?coverage 姹囨€汇€傛寮忔鐜囩‖闂ㄦ潵鑷嫭绔嬮娉ㄥ唽鐨?`K=N銆乹=1/N` 鍙楁帶璇曢獙銆俓n\n');
end

function write_capacity_section(line, capacity, cfg)
    line('## 4. SF-CB 鍥哄畾绉帇瀹归噺杈圭晫\n\n');
    if isempty(capacity)
        line('褰撳墠閰嶇疆涓嶈冻浠ョ敓鎴愬閲忚竟鐣屻€俓n\n');
        return;
    end
    n_nodes = capacity.n_nodes(1);
    q_opt = capacity.q_opt(1);
    ps_opt = capacity.ps_opt(1);
    line('鎸夊浐瀹氱Н鍘?`K=N=%d` 涓?`q*=1/N=%.6g`锛屽崟涓?%.0f us 棰勭害甯х殑鏈€浼樺崟渚嬫垚鍔熸鐜囦负 `Ps*=%.6g`銆傝杈圭晫鍙弿杩伴ケ鍜屻€佺嫭绔?Bernoulli 灏濊瘯涓嬬殑鏈嶅姟涓婇檺锛屼笉绛夊悓浜庢湁闄愯礋杞界殑绮剧‘闃熷垪鏃跺欢銆俓n\n', ...
         n_nodes,q_opt,analysis_conn_slot_us(cfg),ps_opt);

    target_lambda = 30;
    available = unique(capacity.lambda_base(isfinite(capacity.lambda_base)));
    if ~any(abs(available-target_lambda) < 1e-12) && ~isempty(available)
        target_lambda = max(available);
    end
    target = capacity(abs(capacity.lambda_base-target_lambda) < 1e-12,:);
    line('瀵?`lambda_base=%g pkt/STA/s`锛歕n\n',target_lambda);
    line('| 璐熻浇鍙ｅ緞 | M | 绯荤粺瀹归噺 pkt/s | 姣忚妭鐐瑰閲?pkt/s | 鑱氬悎杈撳叆 pkt/s | rho | 鐞嗚绋冲畾 |\n');
    line('|---|---:|---:|---:|---:|---:|---:|\n');
    for i = 1:height(target)
        line('| %s | %g | %.3f | %.3f | %.3f | %.3f | %s |\n', ...
            display_load_mode(target.load_mode(i)),target.M(i), ...
            target.capacity_system_pkt_s(i),target.capacity_per_node_pkt_s(i), ...
            target.offered_aggregate_pkt_s(i),target.rho(i), ...
            yes_no(target.theory_stable(i)));
    end
    modes = unique(target.load_mode,'stable');
    line('\n');
    for i = 1:numel(modes)
        sub = target(target.load_mode == modes(i),:);
        stable_M = sub.M(sub.theory_stable);
        unstable_M = sub.M(~sub.theory_stable);
        line('- %s锛氱悊璁虹ǔ瀹?M=%s锛涚悊璁轰笉绋冲畾 M=%s銆俓n', ...
            display_load_mode(modes(i)),number_list(stable_M),number_list(unstable_M));
    end
    line('\n鐗瑰埆鍦帮紝鍦?N=%d銆乴ambda_base=%g 鐨?fixed-packet 鍙ｅ緞锛岃仛鍚堣緭鍏ヤ负 %g pkt/s锛涘閲忛殢 M 澧炲ぇ鑰屼笅闄嶏紝鍥犳棰勬湡鍙湁杈冨皬鐨?M 鑳界ǔ瀹氥€俧ixed-payload 鎶婃瘡鑺傜偣鍒拌揪鐜囬櫎浠?M锛屼笉鑳戒笌 fixed-packet 鐨勬洸绾挎贩涓哄悓涓€璐熻浇銆俓n\n', ...
         n_nodes,target_lambda,n_nodes*target_lambda);
end

function write_csma_section(line, csma)
    line('## 5. Conn-CSMA 鐩戝惉涓庡け璐ラ摼璺痋n\n');
    if isempty(csma)
        line('褰撳墠妫€鏌ョ偣涓病鏈夊彲鐢ㄧ殑 Conn-CSMA 璇勪及璇婃柇銆俓n\n');
        return;
    end
    line('| 鍗忚 | 鍘熷蹇欐椂婕忓惉鐜?| 鏈夋晥 CCA 鏈夊婕忔鐜?| 鏈夋晥 CCA 璇姤鐜?| 鏅氬惎鍔ㄨ鏁?| RTS澶辫触妫€娴嬮檮鍔犳椂寤?娆?us | 鏁版嵁澶辫触浜嬪姟闄勫姞鏃跺欢/娆?us |\n');
    line('|---|---:|---:|---:|---:|---:|---:|\n');
    protocols = unique(csma.protocol,'stable');
    for pi = 1:numel(protocols)
        sub = csma(csma.protocol == protocols(pi),:);
        raw_rate = safe_ratio(sum_finite(sub.raw_misses), ...
                              sum_finite(sub.raw_busy_opportunities));
        fn_rate = safe_ratio(sum_finite(sub.eligible_fn), ...
                             sum_finite(sub.eligible_tp)+sum_finite(sub.eligible_fn));
        fp_rate = safe_ratio(sum_finite(sub.eligible_fp), ...
                             sum_finite(sub.eligible_fp)+sum_finite(sub.eligible_tn));
        late = sum_finite(sub.late_start_attempts) + ...
               sum_finite(sub.late_start_handshake) + sum_finite(sub.late_start_data);
        rts_failure_delay = safe_ratio( ...
            sum_finite(sub.rts_failure_detection_delay_us), ...
            sum_finite(sub.rts_fail_total));
        data_failure_delay = safe_ratio( ...
            sum_finite(sub.data_failure_transaction_delay_us), ...
            sum_finite(sub.data_fail_sinr));
        line('| %s | %s | %s | %s | %s | %s | %s |\n', display_protocol(protocols(pi)), ...
             format_percent(raw_rate), format_percent(fn_rate), ...
             format_percent(fp_rate), format_number(late), ...
             format_number(rts_failure_delay),format_number(data_failure_delay));
    end
    line('\n鈥滃師濮嬬洃鍚笉鍑嗙‘鐜団€濅笌鈥滄湁 HOL銆佺┖闂蹭笖 NAV=0 鏃剁殑鏈夋晥 CCA 閿欒鐜団€濆垎姣嶄笉鍚屻€傚師濮嬫紡鍚嵆浣胯秴杩?90%%锛屼篃鍙兘鍙戠敓鍦ㄨ妭鐐瑰皻鏈噯澶囩珵浜夌殑鏃跺埢锛涘垽鏂椂寤舵満鍒跺繀椤昏繘涓€姝ユ煡鐪嬫湁瀹?FN 鏄惁瀹為檯杞寲涓烘櫄鍚姩銆丷TS/鏁版嵁澶辫触鍜岀鎾炴氮璐广€係B-CF閲囩敤鍏ㄥ悜缁忓吀纰版挒鐪熷€硷細鏂癉ATA鍙涓庝换涓€鍦ㄩ€擠ATA閲嶅彔锛岀浉鍏冲抚鍏ㄩ儴澶辫触锛屼笉浣跨敤AP渚INR銆係B-CB鐨凴TS鍚屾牱閲囩敤缁忓吀纰版挒锛涘弽浜嬪疄CCA杩樻鏌ユ柊RTS鏄惁浼氫娇褰撳墠鎵囧尯CTS浣庝簬6 dB锛屾垨浣垮畾鍚慏ATA浣庝簬21 dB銆備袱椤瑰け璐ラ檮鍔犳椂寤跺垎鍒弗鏍间娇鐢?`rts_failure_detection_delay_us/rts_fail_total` 涓?`data_failure_transaction_delay_us/data_fail_sinr`锛涙棫妫€鏌ョ偣缂哄皯瀛楁鎴栧垎姣嶄负闆舵椂鏄剧ず N/A銆俓n\n');
end

function write_cca_ablation_section(line, cca)
    line('## 6. Conn-CSMA 鐩戝惉娑堣瀺\n\n');
    if isempty(cca)
        line('鏈彂鐜板彲鐢ㄧ殑 `checkpoints_cca` 鎴?`cca_ablation.csv` 鏉′欢銆俓n\n');
        return;
    end
    data = summarize_cca_variants(cca);
    line('| 鍗忚/鍙樹綋 | 鏉′欢鏁?| 绋冲畾鏉′欢姣斾緥 | 鏈夋晥FN鐜?| 鏈夋晥FP鐜?| RTS澶辫触妫€娴嬮檮鍔犳椂寤?娆?us | 鏁版嵁澶辫触浜嬪姟闄勫姞鏃跺欢/娆?us | 鍖归厤鏉′欢鐩稿鍚炲悙 | 鍖归厤鏉′欢鐩稿鏃跺欢 |\n');
    line('|---|---:|---:|---:|---:|---:|---:|---:|---:|\n');
    for i = 1:height(data)
        line('| %s | %d | %s | %s | %s | %s | %s | %s | %s |\n', ...
            data.label(i),data.n_conditions(i), ...
            format_percent(data.stable_fraction(i)), ...
            format_percent(data.eligible_fnr(i)), ...
            format_percent(data.eligible_fpr(i)), ...
            format_number(data.mean_rts_failure_detection_delay_us(i)), ...
            format_number(data.mean_data_failure_transaction_delay_us(i)), ...
            format_number(data.relative_goodput(i)), ...
            format_number(data.relative_delay(i)));
    end
    line('\n鐩稿鍚炲悙浠ュ悓涓€ `(鍗忚,璐熻浇鍙ｅ緞,lambda,M)` 鍐呰〃鐜版渶濂界殑鍙樹綋褰掍竴鍖栵紱鐩稿鏃跺欢浠ュ悓涓€鏉′欢鍐呮渶浣庣殑绋冲畾鏃跺欢褰掍竴鍖栵紝鍙湪绋冲畾鍙樹綋闂存瘮杈冦€傝繖鏍蜂笉浼氭妸涓嶅悓 M 鎴栦笉鍚岃礋杞界殑缁濆鏃跺欢鐩存帴骞冲潎銆俙directional`銆乣perfect/oracle`銆乣disabled` 鍙婁笉鍚?`rx_sens_dbm` 鍧囦繚鐣欎负鐙珛鍙樹綋锛涘師濮嬫紡鍚珮骞朵笉鑷姩鎰忓懗鐫€鏈夋晥鏈夊 FN 楂樸€俓n\n');
end

function write_conn_comparison_section(line, summary, cfg)
    line('## 6.1 Conn-Aloha 涓?Conn-CSMA 鐩存帴瀵圭収\n\n');
    needed = {'protocol','load_mode','lambda_base','M','stable_fraction', ...
        'mean_delay_us','normalized_goodput_units_s'};
    if isempty(summary) || ~has_variables(summary,needed)
        line('褰撳墠姹囨€诲瓧娈典笉瓒筹紝鏃犳硶鐢熸垚 SF-CB/SB-CB 鐩存帴瀵圭収銆俓n\n');
        return;
    end
    protocol = string(summary.protocol);
    modes = string(summary.load_mode);
    lambdas = double(summary.lambda_base);
    available = unique(lambdas(isfinite(lambdas)));
    if isempty(available)
        line('褰撳墠姹囨€绘病鏈夋湁闄愬埌杈剧巼銆俓n\n');
        return;
    end
    target_lambda = 30;
    if ~any(abs(available-target_lambda)<1e-12)
        target_lambda = max(available);
    end
    target_modes = unique(modes(abs(lambdas-target_lambda)<1e-12 & ...
        (protocol=="sf_cb" | protocol=="sb_cb")),'stable');
    for mi=1:numel(target_modes)
        mode=target_modes(mi);
        line('**%s锛宭ambda_base=%g pkt/STA/s**\n\n', ...
            display_load_mode(mode),target_lambda);
        line('| M | SF-CB绋冲畾 | SF-CB鏃跺欢 us | SF-CB鍚炲悙 units/s | SB-CB绋冲畾 | SB-CB鏃跺欢 us | SB-CB鍚炲悙 units/s | 绋虫€佹椂寤惰緝浼?|\n');
        line('|---:|---:|---:|---:|---:|---:|---:|---|\n');
        in_mode = modes==mode & abs(lambdas-target_lambda)<1e-12;
        m_values=unique(double(summary.M(in_mode & ...
            (protocol=="sf_cb" | protocol=="sb_cb"))));
        for M=m_values(:).'
            ia=find(in_mode & protocol=="sf_cb" & summary.M==M,1);
            ic=find(in_mode & protocol=="sb_cb" & summary.M==M,1);
            if isempty(ia) || isempty(ic), continue; end
            a_stable=summary.stable_fraction(ia)>=1-1e-12;
            c_stable=summary.stable_fraction(ic)>=1-1e-12;
            a_delay=summary.mean_delay_us(ia);
            c_delay=summary.mean_delay_us(ic);
            winner=conn_delay_winner(a_stable,a_delay,c_stable,c_delay);
            line('| %g | %s | %s | %s | %s | %s | %s | %s |\n',M, ...
                yes_no(a_stable),format_number(a_delay), ...
                format_number(summary.normalized_goodput_units_s(ia)), ...
                yes_no(c_stable),format_number(c_delay), ...
                format_number(summary.normalized_goodput_units_s(ic)),winner);
        end
        line('\n');
    end
    line(['浣?M 鏃讹紝SB-CB 鍗充娇鍘熷婕忓惉寰堥珮锛屼粛鍙兘鍑€?%.0f us 鍐崇瓥鏈轰細銆?, ...
        '鍞竴RTS棰勭害鍜屾垚鍔?NAV 淇濇姢锛岄伩寮€ SF-CB 鐨?%.0f us 杈圭晫绛夊緟鍙?, ...
        '绌洪绾?纰版挒棰勭害锛屽洜姝ゅ畬鎴愬寘鏃跺欢鏇翠綆銆傚師濮嬫紡鍚巼涓嶆槸澶辫触姒傜巼锛?, ...
        '鍙湁鏈夊 FN銆佹櫄鍚姩鍙婂叾閫犳垚鐨?RTS/鏁版嵁澶辫触鎵嶈繘鍏ユ満鍒朵唬浠枫€侻 ', ...
        '澧炲ぇ鍚庯紝CTS 鎵弿銆佹櫄鍚姩骞叉壈鍜屽け璐ヤ簨鍔¤秴鏃朵細琚洿闀挎暟鎹樁娈垫斁澶э紝', ...
        'SB-CB 鍙兘鍏堝け绋虫垨鍙嶈秴锛涘彟涓€鏂归潰 fixed-packet 涓?SF-CB 鍦?, ...
        '`lambda=30` 鐨勫浐瀹氱Н鍘嬪閲忕悊璁哄彧鏀寔 M=1锛岀煭绐楀彛涓?M>=2 鐨?, ...
        '鈥滅ǔ瀹氣€濅笉鑳芥帹缈昏楗卞拰杈圭晫銆俓n\n'], ...
        analysis_mmw_slot_us(cfg),analysis_conn_slot_us(cfg));
    line(['鎶?SF-CB 鏀规垚 unslotted 鍙兘鍘绘帀杈圭晫鐩镐綅绛夊緟锛屼笉鑳戒繚璇佹€绘椂寤?, ...
        '涓嬮檷锛氱粡鍏哥函 Aloha 鐨勬槗纰版挒鏃堕棿绐楃敱涓€甯ф墿澶у埌绾︿袱甯э紝鍚炲悙涓婇檺', ...
        '涔熶綆浜?slotted Aloha銆傚湪鏈満鏅腑瀹冭繕浼氶噸鏂板紩鍏?RTS 涓?CTS 鎵弿', ...
        '鐩镐簰閲嶅彔鐨勯棶棰橈紱闄ら潪澧炲姞淇濇姢/蹇欓煶绛夋満鍒讹紝鍚﹀垯涓嶆槸褰撳墠缁撴灉鐨勭洿鎺?, ...
        '淇銆俓n\n']);
end

function winner=conn_delay_winner(a_stable,a_delay,c_stable,c_delay)
    if a_stable && c_stable && isfinite(a_delay) && isfinite(c_delay)
        if a_delay<=c_delay
            winner='SF-CB';
        else
            winner='SB-CB';
        end
    elseif a_stable && isfinite(a_delay)
        winner='SF-CB锛圫B-CB涓嶇ǔ瀹氾級';
    elseif c_stable && isfinite(c_delay)
        winner='SB-CB锛圫F-CB涓嶇ǔ瀹氾級';
    else
        winner='鏃犲彲鎶ュ憡绋虫€佹椂寤?;
    end
end

function write_topology_section(line, topology)
    line('## 7. 鐙珛鎷撴墤椴佹鎬n\n');
    if isempty(topology)
        line('鏈彂鐜板彲鐢ㄧ殑 `checkpoints_topology` 鎴?`topology_robustness.csv` 鏉′欢銆俓n\n');
        return;
    end
    line('| 鍗忚/鏉′欢 | 鎷撴墤鏁?| 绋冲畾鎷撴墤姣斾緥 | 绋虫€佸潎鍊兼椂寤?us锛?5%% CI鍗婂锛?| 褰掍竴鍖栧悶鍚?units/s锛?5%% CI鍗婂锛?|\n');
    line('|---|---:|---:|---:|---:|\n');
    max_rows = min(height(topology),24);
    for i = 1:max_rows
        label = sprintf('%s/%s/lambda=%g/M=%g', ...
            display_protocol(topology.protocol(i)), ...
            display_load_mode(topology.load_mode(i)), ...
            topology.lambda_base(i),topology.M(i));
        line('| %s | %d | %s | %s | %s |\n',label, ...
            topology.n_topology_clusters(i), ...
            format_percent(topology.stable_topology_fraction(i)), ...
            format_estimate_ci(topology.mean_delay_us_mean(i), ...
                               topology.mean_delay_us_ci95(i)), ...
            format_estimate_ci(topology.normalized_goodput_units_s_mean(i), ...
                               topology.normalized_goodput_units_s_ci95(i)));
    end
    if height(topology) > max_rows
        line('| 鈥?| 鈥?| 鈥?| 鈥?| 鈥?|\n');
    end
    line('\n姣忎釜 topology seed 鍏堝舰鎴愪竴涓潯浠剁骇瑙傛祴锛屽啀璺?seed 璁＄畻 Student-t 95%% CI锛涘悓涓€鎷撴墤鍐呯殑澶氫釜 run 鍜屾捣閲忓寘涓嶄細澧炲姞杩欓噷鐨勭嫭绔嬫牱鏈暟銆傝嫢浠讳竴鎷撴墤鏈揪鍒扮ǔ瀹氬垽鎹紝姹囨€荤ǔ鎬佹椂寤剁疆涓?NaN锛岃€屽悶鍚愩€佺Н鍘嬫枩鐜囧拰绋冲畾姣斾緥浠嶄繚鐣欑敤浜庡垽鏂け绋炽€傚崟涓嫇鎵戞椂鍙姤鍛婂潎鍊硷紝浣嗘棤娉曚及璁?t 鍖洪棿銆俓n\n');
end

function info = condition_info(condition, cfg)
    row = struct();
    if isfield(condition,'row') && isstruct(condition.row), row = condition.row; end
    info.protocol = lower(text_value(row, 'protocol', 'unknown'));
    info.load_mode = lower(text_value(row, 'load_mode', 'unknown'));
    info.lambda_base = numeric_value(row, 'lambda_base', NaN);
    info.lambda_effective = numeric_value(row, 'lambda_effective', NaN);
    info.M = numeric_value(row, 'M', NaN);
    info.Tp_us = analysis_conn_slot_us(cfg)*info.M;  % always use config conn_slot
    info.best_q = numeric_value(row, 'best_q', NaN);
end

function runs = evaluation_runs(condition)
    runs = cell(0,1);
    if ~isfield(condition,'evaluation') || isempty(condition.evaluation), return; end
    value = condition.evaluation;
    if iscell(value)
        runs = value(:);
    elseif isstruct(value)
        runs = squeeze(num2cell(value));
        runs = runs(:);
    end
    runs = runs(~cellfun(@isempty,runs));
end

function vector = numeric_vector(s, field)
    vector = zeros(0,1);
    if isstruct(s) && isfield(s,field) && isnumeric(s.(field))
        vector = double(s.(field)(:));
    end
end

function value = scalar_field(s, aliases)
    value = NaN;
    for i = 1:numel(aliases)
        if isfield(s,aliases{i})
            candidate = s.(aliases{i});
            if isnumeric(candidate) && isscalar(candidate)
                value = double(candidate);
                return;
            end
        end
    end
end

function total = sum_metric(runs, aliases)
    total = 0;
    found = false;
    for ri = 1:numel(runs)
        d = runs{ri}.diagnostics;
        value = scalar_field(d, aliases);
        if isfinite(value)
            total = total + value;
            found = true;
        end
    end
    if ~found, total = NaN; end
end

function total = sum_available_metrics(runs, alias_groups)
    values = nan(1,numel(alias_groups));
    for i = 1:numel(alias_groups)
        values(i) = sum_metric(runs, alias_groups{i});
    end
    if all(~isfinite(values))
        total = NaN;
    else
        total = sum(values,'omitnan');
    end
end

function value = first_scalar_field(runs, aliases, fallback)
    value = fallback;
    for ri = 1:numel(runs)
        candidate = scalar_field(runs{ri}.diagnostics, aliases);
        if isfinite(candidate), value = candidate; return; end
    end
end

function value = first_text_field(runs, field, fallback)
    value = fallback;
    for ri = 1:numel(runs)
        d = runs{ri}.diagnostics;
        if isfield(d,field) && (ischar(d.(field)) || isstring(d.(field)))
            value = char(string(d.(field)));
            return;
        end
    end
end

function out = text_value(s, field, fallback)
    out = fallback;
    if isstruct(s) && isfield(s,field) && ~isempty(s.(field))
        out = char(string(s.(field)));
    end
end

function out = numeric_value(s, field, fallback)
    out = fallback;
    if isstruct(s) && isfield(s,field) && isnumeric(s.(field)) && ...
            isscalar(s.(field))
        out = double(s.(field));
    end
end

function out = numeric_alias(s, fields, fallback)
    out = fallback;
    if ~isstruct(s), return; end
    for i = 1:numel(fields)
        field = fields{i};
        if isfield(s,field)
            value = s.(field);
            if (isnumeric(value) || islogical(value)) && isscalar(value)
                out = double(value);
                return;
            end
        end
    end
end

function out = text_alias(s, fields, fallback)
    out = fallback;
    if ~isstruct(s), return; end
    for i = 1:numel(fields)
        field = fields{i};
        if isfield(s,field) && ~isempty(s.(field)) && ...
                (ischar(s.(field)) || isstring(s.(field)) || iscellstr(s.(field)))
            out = char(string(s.(field)));
            return;
        end
    end
end

function value = analysis_mmw_slot_us(cfg)
% Preserve the timing of historical result directories that predate the
% explicit mmWave timing fields; new result directories use the slot config.
    if isstruct(cfg) && isfield(cfg,'mmw_slot_us')
        value = mmw_timing_config(cfg).SLOT_US;
    elseif isstruct(cfg) && isfield(cfg,'arrival_tick_us') && ...
            isequal(double(cfg.arrival_tick_us),5)
        value = 5;
    else
        value = mmw_timing_config().SLOT_US;
    end
end

function value = analysis_conn_slot_us(cfg)
    if isstruct(cfg) && isfield(cfg,'mmw_real_conn_slot_us') && ...
            ~isempty(cfg.mmw_real_conn_slot_us) && isfinite(cfg.mmw_real_conn_slot_us)
        value = double(cfg.mmw_real_conn_slot_us);   % 162.5 us real conn-slot
    elseif isstruct(cfg) && isfield(cfg,'mmw_slot_us')
        value = mmw_timing_config(cfg).CONN_SLOT_US;
    elseif isstruct(cfg) && isfield(cfg,'arrival_tick_us') && ...
            isequal(double(cfg.arrival_tick_us),5)
        value = 190;
    else
        value = mmw_timing_config().CONN_SLOT_US;
    end
end
function value = config_scalar(cfg, field, fallback)
    value = fallback;
    if isstruct(cfg) && isfield(cfg,field) && isnumeric(cfg.(field)) && ...
            isscalar(cfg.(field))
        value = double(cfg.(field));
    end
end

function value = config_text(cfg, field, fallback)
    value = fallback;
    if isstruct(cfg) && isfield(cfg,field) && ...
            (ischar(cfg.(field)) || isstring(cfg.(field)))
        value = char(string(cfg.(field)));
    end
end

function tf = has_variables(t, names)
    tf = all(ismember(names, t.Properties.VariableNames));
end

function paths = append_path(paths, path)
    if ~isempty(path), paths(end+1,1) = string(path); end
end

function label = display_protocol(protocol)
    switch lower(char(protocol))
        case 'sf_cf', label = 'SF-CF';
        case 'sf_cb', label = 'SF-CB';
        case 'sb_cf', label = 'SB-CF';
        case 'sb_cb', label = 'SB-CB';
        case 's7_clean', label = 'S7-AN (n_S=0)';
        case 's7_busy', label = 'S7-AN (n_S=10)';
        otherwise, label = char(protocol);
    end
end

function label = display_load_mode(mode)
    switch lower(char(mode))
        case 'fixed_packet', label = 'fixed pkt/STA/s';
        case 'fixed_payload', label = 'fixed normalized payload';
        otherwise, label = char(mode);
    end
end

function value = safe_mean(x)
    x = x(isfinite(x));
    if isempty(x), value = NaN; else, value = mean(x); end
end

function value = safe_ratio(numerator, denominator)
    if isfinite(numerator) && isfinite(denominator) && denominator > 0
        value = numerator/denominator;
    else
        value = NaN;
    end
end

function value = sum_finite(x)
    x = double(x(:));
    x = x(isfinite(x));
    if isempty(x), value = 0; else, value = sum(x); end
end

function value = nansum_local(x)
    value = sum(x,'omitnan');
end

function text = format_percent(value)
    if isfinite(value), text = sprintf('%.2f%%',100*value); else, text = 'N/A'; end
end

function text = format_number(value)
    if isfinite(value), text = sprintf('%.6g',value); else, text = 'N/A'; end
end

function text = format_estimate_ci(value, half_width)
    if ~isfinite(value)
        text = 'N/A';
    elseif isfinite(half_width)
        text = sprintf('%.6g 卤 %.3g',value,half_width);
    else
        text = sprintf('%.6g锛圕I涓嶅彲浼帮級',value);
    end
end

function text = yes_no(value)
    if value, text = '鏄?; else, text = '鍚?; end
end

function text = number_list(values)
    values = values(isfinite(values));
    if isempty(values)
        text = '鏃?;
    else
        text = strjoin(arrayfun(@(x) sprintf('%g',x),values(:).', ...
            'UniformOutput',false),', ');
    end
end
