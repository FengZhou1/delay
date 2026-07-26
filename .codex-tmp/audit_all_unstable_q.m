project_dir = fileparts(fileparts(mfilename('fullpath')));
root_dir = fullfile(project_dir,'results_v2','20260726_191557_a6ccf7195cee','combined_view');
summary = readtable(fullfile(root_dir,'summary.csv'),'VariableNamingRule','preserve');
unstable = summary(double(summary.stable_fraction) < 1-1e-12,:);

audit_rows = table();
tuning_rows = table();
for i = 1:height(unstable)
    protocol = string(unstable.protocol(i));
    load_mode = string(unstable.load_mode(i));
    lambda_base = double(unstable.lambda_base(i));
    M = double(unstable.M(i));
    tag = sprintf('%s_%s_lam%g_M%d',protocol,load_mode,lambda_base,M);
    checkpoint_path = fullfile(root_dir,'checkpoints',[tag '.mat']);

    selected_q = double(unstable.best_q(i));
    selected_stable_fraction = double(unstable.stable_fraction(i));
    q_min = NaN;
    q_max = NaN;
    q_count = 0;
    max_tune_stable_fraction = NaN;
    q_at_max_stable_fraction = NaN;
    max_mean_goodput = NaN;
    q_at_max_mean_goodput = NaN;
    offered_mean_at_best_goodput = NaN;
    any_all_tune_stable = false;
    n_eval = 0;
    checkpoint_found = isfile(checkpoint_path);

    if checkpoint_found
        data = load(checkpoint_path);
        condition = data.condition;
        if isfield(condition,'tuning') && isfield(condition.tuning,'grid') ...
                && ~isempty(condition.tuning.grid)
            grid = condition.tuning.grid;
            qs = arrayfun(@(x) double(x.q),grid);
            q_min = min(qs);
            q_max = max(qs);
            q_count = numel(qs);
            stable_fracs = arrayfun(@(x) double(x.stable_fraction),grid);
            [max_tune_stable_fraction,idx_stable] = max(stable_fracs);
            q_at_max_stable_fraction = qs(idx_stable);
            any_all_tune_stable = any(stable_fracs >= 1-1e-12);

            for gidx = 1:numel(grid)
                rs = grid(gidx).run_summaries;
                mean_goodput = mean(arrayfun(@(x) double(x.goodput_pkt_s),rs), ...
                    'omitnan');
                mean_arrival = mean(arrayfun(@(x) double(x.arrival_rate_pkt_s),rs), ...
                    'omitnan');
                mean_ratio = mean(arrayfun(@(x) double(x.completion_ratio),rs), ...
                    'omitnan');
                mean_backlog = mean(arrayfun(@(x) double(x.final_backlog),rs), ...
                    'omitnan');
                mean_slope = mean(arrayfun(@(x) double(x.backlog_slope_pkt_s),rs), ...
                    'omitnan');
                mean_delay = mean(arrayfun(@(x) double(x.conditional_mean_delay_us),rs), ...
                    'omitnan');
                row = table(protocol,load_mode,lambda_base,M,double(grid(gidx).q), ...
                    double(grid(gidx).stable_fraction),mean_arrival,mean_goodput, ...
                    mean_ratio,mean_backlog,mean_slope,mean_delay, ...
                    'VariableNames',{'protocol','load_mode','lambda_base','M','q', ...
                    'tune_stable_fraction','mean_arrival_rate','mean_goodput_rate', ...
                    'mean_completion_ratio','mean_final_backlog','mean_backlog_slope', ...
                    'mean_conditional_delay_us'});
                tuning_rows = [tuning_rows; row]; %#ok<AGROW>
            end
            point_mask = tuning_rows.protocol == protocol ...
                & tuning_rows.load_mode == load_mode ...
                & tuning_rows.lambda_base == lambda_base ...
                & tuning_rows.M == M;
            point_rows = tuning_rows(point_mask,:);
            [max_mean_goodput,idx_goodput] = max(point_rows.mean_goodput_rate);
            q_at_max_mean_goodput = point_rows.q(idx_goodput);
            offered_mean_at_best_goodput = point_rows.mean_arrival_rate(idx_goodput);
        end
        if isfield(condition,'evaluation') && ~isempty(condition.evaluation)
            n_eval = numel(condition.evaluation);
        end
    end

    audit = table(protocol,load_mode,lambda_base,M,selected_q, ...
        selected_stable_fraction,checkpoint_found,q_min,q_max,q_count, ...
        max_tune_stable_fraction,q_at_max_stable_fraction,any_all_tune_stable, ...
        max_mean_goodput,q_at_max_mean_goodput,offered_mean_at_best_goodput,n_eval, ...
        'VariableNames',{'protocol','load_mode','lambda_base','M','selected_q', ...
        'selected_stable_fraction','checkpoint_found','q_min','q_max','q_count', ...
        'max_tune_stable_fraction','q_at_max_stable_fraction','any_all_tune_stable', ...
        'max_mean_goodput','q_at_max_mean_goodput','offered_mean_at_best_goodput', ...
        'n_eval'});
    audit_rows = [audit_rows; audit]; %#ok<AGROW>
end

out_dir = fullfile(project_dir,'.codex-tmp');
writetable(audit_rows,fullfile(out_dir,'unstable_q_audit.csv'));
writetable(tuning_rows,fullfile(out_dir,'unstable_q_tuning_grid.csv'));
disp(audit_rows);
