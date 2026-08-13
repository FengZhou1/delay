function merge_unslotted_orig_rows(new_run_dir)
%MERGE_UNSLOTTED_ORIG_ROWS Package fresh original-flow unslotted rows as a
%   supplement source and splice them into results_v2/R9_merged.
    r9_dir = fullfile('results_v2','20260813_003419_e174efb1074f');
    out_dir = fullfile('results_v2','R9_merged','supplement_work_unsl_orig');
    if ~isfolder(out_dir), mkdir(out_dir); end
    r9_summary = readtable(fullfile(r9_dir,'summary.csv'),'VariableNamingRule','preserve');
    new_summary = readtable(fullfile(new_run_dir,'summary.csv'),'VariableNamingRule','preserve');
    mask = string(new_summary.protocol) == 'unslotted';
    rows = new_summary(mask,:);
    % Keep the 3-seed point-fix value for unslotted lam30 M3 (1-seed eval at
    % this near-saturation point is too noisy); splice the other 11 rows.
    skip_mask = double(rows.lambda_base) == 30 & double(rows.M) == 3;
    if any(skip_mask)
        fprintf('merge_unslotted_orig_rows: keeping 3-seed value for unslotted lam30 M3\n');
        rows(skip_mask,:) = [];
    end
    if height(rows) ~= 11
        warning('merge_unslotted_orig_rows:RowCount', ...
            'expected 11 unslotted rows after M3 skip, got %d', height(rows));
    end
    report_rows = {};
    for i = 1:height(rows)
        r = rows(i,:);
        old_mask = string(r9_summary.protocol) == 'unslotted' & ...
                   double(r9_summary.lambda_base) == double(r.lambda_base) & ...
                   double(r9_summary.M) == double(r.M);
        old = r9_summary(old_mask,:);
        if isempty(old)
            old_q = NaN; old_delay = NaN;
        else
            old_q = double(old.best_q(1)); old_delay = double(old.mean_delay_us(1));
        end
        report_rows{end+1} = struct('protocol','unslotted', ...
            'load_mode',char(r.load_mode(1)), ...
            'lambda_base',double(r.lambda_base(1)),'M',double(r.M(1)), ...
            'hit_side','original_flow', ...
            'old_best_q',old_q,'old_mean_delay_us',old_delay, ...
            'new_best_q',double(r.best_q(1)), ...
            'new_mean_delay_us',double(r.mean_delay_us(1)), ...
            'ext_stable_count',NaN,'selection_source',char(r.q_selection_mode(1)), ...
            'fallback_log',''); %#ok<AGROW>
    end
    info = struct();
    info.r9_dir = r9_dir;
    info.out_dir = out_dir;
    info.new_rows = rows;
    info.report = struct2table([report_rows{:}]);
    info.hit_logs = struct();
    info.n_targets = height(rows);
    info.n_changed = height(rows);
    info.full_grid = false;
    info.elapsed_s = NaN;
    save(fullfile(out_dir,'supplement_results.mat'),'info','-v7.3');
    writetable(info.report, fullfile(out_dir,'supplement_summary.csv'));
    merge_r9_boundary(r9_dir, fullfile('results_v2','R9_merged'));
end
