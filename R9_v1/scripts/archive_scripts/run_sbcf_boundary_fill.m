function run_sbcf_boundary_fill()
% 临时：补扫 sb_cf 的稳定边界（M=1 和 M=5），λ 覆盖 20~28
    root = fullfile(pwd,'0819_R9_results');
    lambdas = [20, 22, 24, 26, 28];

    for Mi = 1:2
        Ms = [1, 5]; M = Ms(Mi);
        fprintf('\n===== 补扫 sb_cf M=%d =====\n', M);
        cfg = default_experiment_config('analysis');
        cfg.txop_mode = 'ready_queue';
        cfg.protocols = {'sb_cf'};
        cfg.M_values = M;
        cfg.lambda_values = lambdas;
        cfg.load_modes = {'fixed_packet'};
        cfg.resume = false;
        cfg.run_preflight_tests = false;
        cfg.n_eval_runs = 3;
        cfg.condition_timeout_s = 1800;
        cfg.n_workers = 2;
        cfg.q_multi_basin_tuning = true;
        qgrid = build_piecewise_q_grid(NaN);
        cfg.q_coarse = qgrid;
        cfg.protocol_q_grids_enabled = true;
        cfg.protocol_q_grids.sb_cf = qgrid;
        cfg.stability_rate_tolerance = 0.05;
        cfg.stability_censor_tolerance = 0.01;
        cfg.stability_slope_fraction = 0.05;
        cfg.stability_require_slope = true;
        cfg.output_dir = fullfile('results_v2', sprintf('R9_sbcf_boundary_fill_M%d', M));
        exp = run_experiment(cfg);
        fprintf('M=%d 补扫完成: %s\n', M, exp.output_dir);

        new = readtable(fullfile(exp.output_dir,'summary.csv'),'VariableNamingRule','preserve');

        % 合并进 0819_R9_results 边界 summary
        if M == 1
            sb_dir = fullfile(root,'stability_boundary','M1');
        else
            sb_dir = fullfile(root,'stability_boundary','M5');
        end
        sum_path = fullfile(sb_dir,'summary.csv');
        old = readtable(sum_path,'VariableNamingRule','preserve');
        copyfile(sum_path, [sum_path '.bak_sbcf_' datestr(now,'yyyymmdd_HHMMSS')]);

        % 删除旧 sb_cf 行（从30开始），追加新 sb_cf 行
        keep = string(old.protocol) ~= "sb_cf";
        merged = [old(keep,:); new];
        merged = unique(merged,'rows','stable');
        writetable(merged, sum_path);
        fprintf('已合并 %d 行到 %s\n', height(new), sum_path);
    end
    fprintf('\n===== 全部完成 =====\n');
end
