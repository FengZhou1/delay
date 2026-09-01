function resume_sbcf_M5()
% 临时：续跑 M5 sb_cf 补扫的 λ=26/28，然后合并结果并更新边界表
    root = fullfile(pwd,'0819_R9_results');

    cfg = default_experiment_config('analysis');
    cfg.txop_mode = 'ready_queue';
    cfg.protocols = {'sb_cf'};
    cfg.M_values = 5;
    cfg.lambda_values = [20, 22, 24, 26, 28];
    cfg.load_modes = {'fixed_packet'};
    cfg.resume = true;
    cfg.run_preflight_tests = false;
    cfg.n_eval_runs = 3;
    cfg.condition_timeout_s = 3600;
    cfg.parallel = false;
    cfg.n_workers = 1;
    cfg.q_multi_basin_tuning = true;
    qgrid = build_piecewise_q_grid(NaN);
    cfg.q_coarse = qgrid;
    cfg.protocol_q_grids_enabled = true;
    cfg.protocol_q_grids.sb_cf = qgrid;
    cfg.stability_rate_tolerance = 0.05;
    cfg.stability_censor_tolerance = 0.01;
    cfg.stability_slope_fraction = 0.05;
    cfg.stability_require_slope = true;
    cfg.output_dir = fullfile('results_v2','R9_sbcf_boundary_fill_M5');
    exp = run_experiment(cfg);
    fprintf('M5 续跑完成: %s\n', exp.output_dir);

    new = readtable(fullfile(exp.output_dir,'summary.csv'),'VariableNamingRule','preserve');
    sb_dir = fullfile(root,'stability_boundary','M5');
    sum_path = fullfile(sb_dir,'summary.csv');
    old = readtable(sum_path,'VariableNamingRule','preserve');
    copyfile(sum_path, [sum_path '.bak_sbcf_' datestr(now,'yyyymmdd_HHMMSS')]);
    keep = string(old.protocol) ~= "sb_cf";
    merged = [old(keep,:); new];
    merged = unique(merged,'rows','stable');
    writetable(merged, sum_path);
    fprintf('M5 summary 已合并，总行数 %d\n', height(merged));

    % 重算两个边界表
    for Mi = 1:2
        if Mi==1, bdir = fullfile(root,'stability_boundary','M1'); else, bdir = fullfile(root,'stability_boundary','M5'); end
        s = readtable(fullfile(bdir,'summary.csv'),'VariableNamingRule','preserve');
        b = compute_stability_boundary(s);
        writetable(b, fullfile(bdir,'stability_boundary.csv'));
        fprintf('边界表已更新: %s\n', fullfile(bdir,'stability_boundary.csv'));
        disp(b);
    end
end

function boundary = compute_stability_boundary(summary)
    protocols = unique(string(summary.protocol),'stable');
    rows = table();
    for i = 1:numel(protocols)
        p = protocols(i);
        sub = summary(string(summary.protocol)==p,:);
        lam = double(sub.lambda_base);
        stable = double(sub.stable_fraction) >= 1-1e-12 & ...
                 double(sub.completion_ratio) >= 0.99;
        [lam,ord] = sort(lam); stable = stable(ord);
        if any(stable)
            max_lam = lam(find(stable,1,'last'));
        else
            max_lam = NaN;
        end
        idx = find(lam==max_lam & stable,1);
        if ~isempty(idx)
            bdelay = double(sub.mean_delay_us(idx));
            bq = double(sub.best_q(idx));
        else
            bdelay = NaN; bq = NaN;
        end
        rows = [rows; table(string(p),max_lam,bdelay,bq, ...
            'VariableNames',{'protocol','max_stable_lambda','boundary_delay_us','boundary_best_q'})];
    end
    boundary = rows;
end
