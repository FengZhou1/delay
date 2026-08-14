function info = run_boundary_q_supplement(r9_dir, out_dir, targets, full_grid, eval_seeds)
%RUN_BOUNDARY_Q_SUPPLEMENT Re-tune R9 conditions whose best_q hit the scan boundary.
%
%   Auto mode (targets empty): every R9 condition whose best_q equals the
%   upper or lower edge of its protocol q grid is re-tuned:
%     * upper hit -> scan [0.25:0.05:0.5], lower hit -> [1e-5:1e-5:9e-5]
%   Point-fix mode (targets given as Nx3 cell {protocol, lambda_base, M} or a
%   table with those variables): only the listed conditions are re-tuned.
%   When FULL_GRID is true, the original protocol grid AND the extension are
%   both scanned with 3 seeds (used for single-point fixes where the R9
%   1-seed tuning was corrupted by noise).
%
%   Rules (both modes):
%     * 3 seeds per q (3 tune runs); a q is stable only when ALL 3 seeds are
%       stable
%     * the stable q with the lowest mean delay is evaluated first
%     * eval acceptance: completion_ratio >= 0.95 AND summary.stable
%     * if the eval is not accepted, fall back to the next stable q to the
%       LEFT and re-eval; if nothing is accepted the original R9 row is kept
%
%   Same physical settings as R9 (config, scenario, arrival seeds, measure
%   windows). Tuning uses 3 seeds. Eval uses EVAL_SEEDS seeds (default 3 in
%   full-grid point-fix mode, otherwise 1); seed 1 is the same eval seed as
%   R9. In point-fix mode the R9 row is ALWAYS replaced with the new eval
%   (same q or not) so the refreshed metrics survive the merge.

    if nargin < 1 || isempty(r9_dir)
        r9_dir = fullfile('results_v2','20260813_003419_e174efb1074f');
    end
    if nargin < 2 || isempty(out_dir)
        out_dir = fullfile('results_v2','R9_merged','supplement_work');
    end
    if nargin < 3, targets = {}; end
    if nargin < 4 || isempty(full_grid), full_grid = false; end
    if nargin < 5 || isempty(eval_seeds)
        if full_grid, eval_seeds = 3; else, eval_seeds = 1; end
    end
    if ~isfolder(out_dir), mkdir(out_dir); end

    saved = load(fullfile(r9_dir,'config.mat'),'cfg');
    cfg = saved.cfg;
    summary = readtable(fullfile(r9_dir,'summary.csv'),'VariableNamingRule','preserve');
    scenario = prepare_scenario_v2(cfg,cfg.topology_seed);

    if cfg.parallel && license('test','Distrib_Computing_Toolbox')
        pool = gcp('nocreate');
        if isempty(pool)
            parpool('Processes',cfg.n_workers,'IdleTimeout',Inf);
        end
    end

    upper_ext = 0.25:0.05:0.5;
    lower_ext = 1e-5:1e-5:9e-5;
    n_seeds = 3;
    started = tic;

    % ---- determine target rows ----
    hit_idx = [];
    if ~isempty(targets)
        if istable(targets)
            t_proto = cellstr(targets.protocol);
            t_lam = double(targets.lambda_base);
            t_M = double(targets.M);
        else
            t_proto = cellstr(targets(:,1));
            t_lam = cell2mat(targets(:,2));
            t_M = cell2mat(targets(:,3));
        end
        for ti = 1:numel(t_proto)
            mask = strcmp(summary.protocol,t_proto{ti}) & ...
                   double(summary.lambda_base)==t_lam(ti) & ...
                   double(summary.M)==t_M(ti);
            idx = find(mask);
            if ~isempty(idx)
                hit_idx(end+1) = idx(1); %#ok<AGROW>
            else
                warning('run_boundary_q_supplement:TargetNotFound', ...
                    'Target %s lam%g M%d not found in R9 summary.', ...
                    t_proto{ti},t_lam(ti),t_M(ti));
            end
        end
    else
        for ri = 1:height(summary)
            proto = char(summary.protocol(ri));
            if ~isfield(cfg.protocol_q_grids,proto), continue; end
            grid = double(cfg.protocol_q_grids.(proto));
            bq = double(summary.best_q(ri));
            if ~isfinite(bq), continue; end
            if abs(bq-max(grid)) <= 1e-9 || abs(bq-min(grid)) <= 1e-9
                hit_idx(end+1) = ri; %#ok<AGROW>
            end
        end
    end
    fprintf('Target conditions: %d\n', numel(hit_idx));

    changed_rows = table();
    report_rows = {};
    hit_logs = struct();

    for hi = 1:numel(hit_idx)
        ri = hit_idx(hi);
        proto = char(summary.protocol(ri));
        load_mode = char(summary.load_mode(ri));
        lambda_base = double(summary.lambda_base(ri));
        lambda_eff = double(summary.lambda_effective(ri));
        M = double(summary.M(ri));
        old_best_q = double(summary.best_q(ri));
        old_delay = double(summary.mean_delay_us(ri));
        fprintf('[supplement %d/%d] %s lam%g M%d old_q=%.4g full_grid=%d\n', ...
            hi,numel(hit_idx),proto,lambda_base,M,old_best_q,full_grid);

        t_cond = tic;
        load_idx = find(strcmp(cfg.load_modes,load_mode),1);
        lambda_idx = find(cfg.lambda_values==lambda_base,1);
        proto_idx = find(strcmp(cfg.protocols,proto),1);

        % ---- tune cfg, mirroring run_experiment.tune_condition ----
        tc = cfg;
        tc.warmup_us = cfg.tune_warmup_us;
        tc.measure_us = cfg.tune_measure_us;
        if isfield(cfg,'tune_min_expected_arrivals') && ...
                cfg.tune_min_expected_arrivals>0 && lambda_eff>0
            req = cfg.tune_min_expected_arrivals/(cfg.n_nodes*lambda_eff)*1e6;
            if isfield(cfg,'tune_measure_max_us') && isfinite(cfg.tune_measure_max_us)
                req = min(req,cfg.tune_measure_max_us);
            end
            req = ceil(req/cfg.arrival_tick_us)*cfg.arrival_tick_us;
            tc.measure_us = max(tc.measure_us,req);
        end
        tc.drain_max_us = cfg.tune_drain_max_us;
        tc.arrival_end_us = tc.warmup_us + tc.measure_us;
        tc.sim_hard_end_us = tc.arrival_end_us + tc.drain_max_us;
        tc.collect_diagnostics = false;

        % ---- 3 tuning seeds (common traces across q, as in R9) ----
        traces = cell(n_seeds,1);
        pseeds = zeros(n_seeds,1);
        for s = 1:n_seeds
            aseed = experiment_arrival_seed(cfg,lambda_eff,s,0,load_idx,lambda_idx);
            traces{s} = generate_arrival_trace(lambda_eff,tc,aseed);
            pseeds(s) = bounded_seed(cfg.protocol_seed_base + ...
                proto_idx*1000000 + M*10000 + s);
        end

        grid = double(cfg.protocol_q_grids.(proto));
        if full_grid
            ext_q = upper_ext;
            hit_side = 'full_grid';
            scan_q = unique([grid, ext_q]);
        elseif abs(old_best_q-max(grid)) <= 1e-9
            ext_q = upper_ext;
            hit_side = 'upper';
            scan_q = ext_q;
        else
            ext_q = lower_ext;
            hit_side = 'lower';
            scan_q = ext_q;
        end

        % ---- scan: each q x 3 seeds ----
        n_q = numel(scan_q);
        cell_out = cell(n_q,1);
        parfor qi = 1:n_q
            local = cell(n_seeds,1);
            for s = 1:n_seeds
                res = run_protocol_v2(proto,traces{s},scenario,tc,M,scan_q(qi),pseeds(s));
                local{s} = res.summary;
            end
            cell_out{qi} = local;
        end
        stable_ok = false(n_q,1);
        mean_del = nan(n_q,1);
        for qi = 1:n_q
            ss = cell_out{qi};
            st = [ss{1}.stable, ss{2}.stable, ss{3}.stable];
            dl = [ss{1}.mean_delay_us, ss{2}.mean_delay_us, ss{3}.mean_delay_us];
            stable_ok(qi) = all(st) && all(isfinite(dl));
            if stable_ok(qi)
                mean_del(qi) = mean(dl);
            end
        end
        scan_stable_q = scan_q(stable_ok);
        [~,order] = sort(mean_del(stable_ok));
        cand_q = scan_stable_q(order);
        tried_q = [];

        % ---- original-grid stable info for the left fallback ----
        orig_stable_q = old_best_q;
        ck_path = fullfile(r9_dir,'checkpoints', ...
            sprintf('%s_%s_lam%g_M%d.mat',proto,load_mode,lambda_base,M));
        if isfile(ck_path)
            ck = load(ck_path,'condition');
            g = ck.condition.tuning.grid;
            qq = double([g.q]); sf = double([g.stable_fraction]);
            dl = double([g.mean_delay_us]);
            orig_stable_q = qq(sf >= 1-1e-12 & isfinite(dl));
        end

        % ---- eval inputs: seed 1 = same eval seed as R9 (offset 30000) ----
        eval_traces = cell(eval_seeds,1);
        eval_pseeds = zeros(eval_seeds,1);
        for s = 1:eval_seeds
            aseed_e = experiment_arrival_seed(cfg,lambda_eff,1,30000+s-1, ...
                load_idx,lambda_idx);
            eval_traces{s} = generate_arrival_trace(lambda_eff,cfg,aseed_e);
            eval_pseeds(s) = bounded_seed(cfg.protocol_seed_base + 30000 + s - 1 + ...
                proto_idx*1000000 + M*10000 + 1);
        end

        chosen_q = NaN;
        chosen_sum = [];
        fallback_log = {};
        source = 'none';

        % phase 1: scanned stable candidates (min delay first), strict
        % multi-seed eval (all seeds must be accepted)
        for c = 1:numel(cand_q)
            q = cand_q(c);
            [n_ok,avg_sum,~] = eval_multi(proto,eval_traces, ...
                scenario,cfg,M,q,eval_pseeds);
            tried_q(end+1) = q; %#ok<AGROW>
            if n_ok >= eval_seeds && ~isempty(avg_sum)
                fallback_log{end+1} = sprintf('scan q=%.5g comp=%.3f stable=%d', ...
                    q,avg_sum.completion_ratio,avg_sum.stable); %#ok<AGROW>
                chosen_q = q; chosen_sum = avg_sum; source = 'scan_min_delay'; break;
            else
                fallback_log{end+1} = sprintf('scan q=%.5g rejected (%d/%d seeds ok)', ...
                    q,n_ok,eval_seeds); %#ok<AGROW>
            end
        end
        % phase 2: fall back left over the combined stable set (descending)
        if ~isfinite(chosen_q)
            left_qs = sort(unique([orig_stable_q, scan_stable_q]),'descend');
            for c = 1:numel(left_qs)
                q = left_qs(c);
                if any(abs(tried_q-q) <= 1e-12), continue; end
                [n_ok,avg_sum,~] = eval_multi(proto,eval_traces, ...
                    scenario,cfg,M,q,eval_pseeds);
                if n_ok >= eval_seeds && ~isempty(avg_sum)
                    fallback_log{end+1} = sprintf('left q=%.5g comp=%.3f stable=%d', ...
                        q,avg_sum.completion_ratio,avg_sum.stable); %#ok<AGROW>
                    chosen_q = q; chosen_sum = avg_sum; source = 'left_fallback'; break;
                else
                    fallback_log{end+1} = sprintf('left q=%.5g rejected (%d/%d seeds ok)', ...
                        q,n_ok,eval_seeds); %#ok<AGROW>
                end
            end
        end
        % phase 3: relaxed majority eval over the top candidates (used when
        % the strict all-seeds pass rejects everything, e.g. bi-stable
        % points near saturation)
        if ~isfinite(chosen_q) && eval_seeds >= 2
            n_cand = min(5,numel(cand_q));
            best_q = NaN; best_delay = inf; best_sum = []; best_n_ok = 0;
            for c = 1:n_cand
                q = cand_q(c);
                [n_ok,avg_sum,~] = eval_multi(proto,eval_traces, ...
                    scenario,cfg,M,q,eval_pseeds);
                need = max(2,ceil(eval_seeds/2));
                if n_ok >= need && ~isempty(avg_sum) && ...
                        double(avg_sum.mean_delay_us) < best_delay
                    best_q = q; best_delay = double(avg_sum.mean_delay_us);
                    best_sum = avg_sum; best_n_ok = n_ok;
                end
            end
            if isfinite(best_q)
                chosen_q = best_q; chosen_sum = best_sum;
                source = 'relaxed_majority';
                fallback_log{end+1} = sprintf('relaxed pick q=%.5g (%d/%d seeds ok)', ...
                    best_q,best_n_ok,eval_seeds); %#ok<AGROW>
            end
        end

        elapsed = toc(t_cond);
        replace_row = isfinite(chosen_q) && ~isempty(chosen_sum);
        if replace_row && (full_grid || abs(chosen_q-old_best_q) > 1e-9)
            label = 'boundary_supplement_3seed';
            if full_grid, label = 'pointfix_full_rescan_3seed'; end
            new_row = summary(ri,:);
            new_row = fill_row(new_row,chosen_q,chosen_sum,elapsed, ...
                unique([scan_stable_q, orig_stable_q]),label);
            if isempty(changed_rows)
                changed_rows = new_row;
            else
                changed_rows = [changed_rows; new_row]; %#ok<AGROW>
            end
            fprintf('  NEW q=%.5g (was %.4g) delay %.0f -> %.0f us [%s]\n', ...
                chosen_q,old_best_q,old_delay,double(chosen_sum.mean_delay_us),source);
        else
            fprintf('  kept original q=%.4g (source=%s)\n',old_best_q,source);
        end

        report_rows{end+1} = struct('protocol',proto,'load_mode',load_mode, ...
            'lambda_base',lambda_base,'M',M,'hit_side',hit_side, ...
            'old_best_q',old_best_q,'old_mean_delay_us',old_delay, ...
            'new_best_q',chosen_q, ...
            'new_mean_delay_us',pick_delay(chosen_sum,old_delay), ...
            'ext_stable_count',nnz(stable_ok), ...
            'selection_source',source, ...
            'fallback_log',strjoin(fallback_log,' | ')); %#ok<AGROW>
        hit_logs.(sprintf('%s_lam%g_M%d',proto,lambda_base,M)) = struct( ...
            'scan_q',scan_q,'stable_ok',stable_ok,'mean_del',mean_del, ...
            'orig_stable_q',orig_stable_q,'chosen_q',chosen_q, ...
            'source',source,'fallback_log',{fallback_log},'elapsed_s',elapsed);
    end

    report = struct2table([report_rows{:}]);
    info = struct();
    info.r9_dir = r9_dir;
    info.out_dir = out_dir;
    info.new_rows = changed_rows;
    info.report = report;
    info.hit_logs = hit_logs;
    info.n_targets = numel(hit_idx);
    info.n_changed = height(changed_rows);
    info.full_grid = full_grid;
    info.elapsed_s = toc(started);
    save(fullfile(out_dir,'supplement_results.mat'),'info','-v7.3');
    if ~isempty(report)
        writetable(report, fullfile(out_dir,'supplement_summary.csv'));
    end
    fprintf('=== supplement done: %d targets, %d changed, %.0f s ===\n', ...
        info.n_targets, info.n_changed, info.elapsed_s);
end

function [n_ok,avg_sum,seed_delays] = eval_multi(proto,eval_traces, ...
    scenario,cfg,M,q,pseeds)
%EVAL_MULTI Multi-seed eval. A seed is accepted when completion>=0.95 AND
%   stable. Returns the number of accepted seeds, the mean over accepted
%   seed summaries, and the per-seed mean delays.
    n = numel(eval_traces);
    sums = cell(n,1);
    seed_delays = nan(n,1);
    n_ok = 0;
    for s = 1:n
        res = run_protocol_v2(proto,eval_traces{s},scenario,cfg,M,q,pseeds(s));
        sums{s} = res.summary;
        if isfield(res.summary,'mean_delay_us') && isfinite(res.summary.mean_delay_us)
            seed_delays(s) = double(res.summary.mean_delay_us);
        end
        if isfinite(res.summary.completion_ratio) && ...
                res.summary.completion_ratio >= 0.95 && logical(res.summary.stable)
            n_ok = n_ok + 1;
        end
    end
    ok_idx = find(isfinite(seed_delays));
    if isempty(ok_idx)
        avg_sum = [];
    else
        avg_sum = average_summaries(sums(ok_idx));
    end
end

function s = average_summaries(sums)
%AVERAGE_SUMMARIES Seed-averaged summary: mean of numeric scalar fields,
%   logical AND of logical fields, first value for the rest.
    s = sums{1};
    fn = fieldnames(s);
    for i = 1:numel(fn)
        f = fn{i};
        vals = cell(numel(sums),1);
        for k = 1:numel(sums)
            vals{k} = sums{k}.(f);
        end
        all_num = true; all_log = true;
        for k = 1:numel(vals)
            v = vals{k};
            if ~(isnumeric(v) && isscalar(v)), all_num = false; end
            if ~(islogical(v) && isscalar(v)), all_log = false; end
        end
        if all_num
            s.(f) = mean(cellfun(@double, vals));
        elseif all_log
            s.(f) = all(cellfun(@logical, vals));
        end
    end
end

function value = pick_delay(s,fallback)
    if isstruct(s) && isfield(s,'mean_delay_us')
        value = double(s.mean_delay_us);
    else
        value = fallback;
    end
end

function row = fill_row(row,chosen_q,s,elapsed_s,combined_stable_q,label)
%FILL_ROW Overwrite the tuning metadata and metric columns of a summary row
%   with the supplement eval values.
    row.best_q = chosen_q;
    row.q_tuning_best_q = chosen_q;
    row.q_selection_mode = {label};
    combined = sort(double(combined_stable_q));
    lefts = combined(combined < chosen_q);
    rights = combined(combined > chosen_q);
    if isempty(lefts), row.q_stable_basin_left = NaN;
    else, row.q_stable_basin_left = lefts(end); end
    if isempty(rights), row.q_stable_basin_right = NaN;
    else, row.q_stable_basin_right = rights(1); end
    row.q_search_boundary_hit = true;
    row.q_refinement_passes = 0;
    row.q_preferred_neighbor_radius = NaN;
    row.q_neighbor_radius_used = 0;
    row.q_validation_runs = 0;
    row.q_validation_candidates_tested = 0;
    row.q_validation_passed = true;
    row.q_validation_selected_rank = NaN;
    row.stable_fraction = double(s.stable);
    metrics = boundary_metric_names();
    for i = 1:numel(metrics)
        m = metrics{i};
        if isfield(s,m)
            row.(m) = s.(m);
        end
        ci = [m '_ci95'];
        if ismember(ci,row.Properties.VariableNames)
            row.(ci) = NaN;
        end
    end
    row.condition_elapsed_s = elapsed_s;
    row.timeout_exceeded = false;
end

function metrics = boundary_metric_names()
    metrics = {'n_arrived','n_completed','n_eligible','n_completed_eligible', ...
        'n_structural_censored','n_censored','raw_completion_ratio', ...
        'final_backlog', ...
        'mean_delay_us','mean_queue_delay_us','mean_access_delay_us', ...
        'conditional_mean_delay_us','p50_delay_us','p95_delay_us', ...
        'p99_delay_us','conditional_p50_delay_us','conditional_p95_delay_us', ...
        'conditional_p99_delay_us','mean_boundary_wait_us','mean_difs_wait_us', ...
        'mean_probability_wait_us','mean_busy_nav_wait_us', ...
        'mean_collision_delay_us','mean_control_delay_us','mean_data_delay_us', ...
        'mean_other_access_delay_us','arrival_rate_pkt_s','goodput_pkt_s', ...
        'normalized_offered_units_s','normalized_goodput_units_s', ...
        'goodput_bit_s','payload_airtime','mean_system_packets', ...
        'mean_waiting_packets','mean_service_packets','backlog_slope_pkt_s', ...
        'completion_ratio','little_relative_error','jain_fairness', ...
        'attempts_total','retransmissions_completed_cohort', ...
        'mean_attempts_completed','collision_waste_us_total', ...
        'collision_channel_time_us_total','collision_tx_airtime_us_total', ...
        'collision_channel_time_us_measure','collision_tx_airtime_us_measure', ...
        'stability_rate_ok','stability_censor_ok','stability_slope_ok', ...
        'stability_rate_relative_error','stability_allowed_censored', ...
        'stability_slope_limit_pkt_s'};
end

function seed = bounded_seed(value)
    seed = mod(double(value), 2^31-2) + 1;
end
