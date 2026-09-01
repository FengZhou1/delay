function resume_0819_R9()
%RESUME_0819_R9 从上次中断处续跑

    root = fullfile(pwd, '0819_R9_results');
    if ~isfolder(root), mkdir(root); end

    %% Logic1 lambda-sweep - 续跑
    cfg = default_experiment_config('analysis');
    cfg.txop_mode = 'ready_queue';
    cfg.protocols = {'sf_cb','sb_cb','unslotted','s7_clean','s7_busy'};
    cfg.M_values = [1, 5];
    cfg.lambda_values = [8, 15, 25, 30, 45];
    cfg.load_modes = {'fixed_packet'};
    cfg.resume = true;
    cfg.run_preflight_tests = false;
    cfg.n_eval_runs = 3;
    cfg.condition_timeout_s = 1800;
    cfg.n_workers = 2;
    cfg.q_multi_basin_tuning = true;
    qgrid = build_piecewise_q_grid(NaN);
    cfg.q_coarse = qgrid;
    cfg.protocol_q_grids_enabled = true;
    for p = 1:numel(cfg.protocols)
        cfg.protocol_q_grids.(cfg.protocols{p}) = qgrid;
    end
    cfg.stability_rate_tolerance = 0.05;
    cfg.stability_censor_tolerance = 0.01;
    cfg.stability_slope_fraction = 0.05;
    cfg.stability_require_slope = true;
    % 指向已有目录，续跑
    cfg.output_dir = fullfile('results_v2', '20260819_162657_0e9b2bf9c602');
    fprintf('续跑 Logic1 lambda-sweep...\n');
    exp1 = run_experiment(cfg);

    % CF baseline
    cfg_cf = cfg;
    cfg_cf.protocols = {'sf_cf','sb_cf'};
    cfg_cf.M_values = 1;
    cfg_cf.protocol_q_grids.sf_cf = qgrid;
    cfg_cf.protocol_q_grids.sb_cf = qgrid;
    cfg_cf.output_dir = fullfile('results_v2', '20260819_202504_079a12a5cc1b'); % CF 已完成，续跑跳过
    fprintf('合并 Logic1 CF baseline...\n');
    exp1cf = run_experiment(cfg_cf);

    % 合并保存
    out1 = fullfile(root, 'logic1', 'lambda_sweep');
    if ~isfolder(out1), mkdir(out1); end
    s1 = readtable(fullfile(exp1.output_dir,'summary.csv'),'VariableNamingRule','preserve');
    s1.fixed_M_baseline = false(height(s1),1);
    s1cf = readtable(fullfile(exp1cf.output_dir,'summary.csv'),'VariableNamingRule','preserve');
    s1cf.fixed_M_baseline = true(height(s1cf),1);
    merged1 = [s1; s1cf];
    writetable(merged1, fullfile(out1, 'merged_summary.csv'));

    for mi = [1, 5]
        subdir = fullfile(out1, sprintf('M%d', mi));
        if ~isfolder(subdir), mkdir(subdir); end
        sub = merged1(merged1.M == mi, :);
        writetable(sub, fullfile(subdir, 'summary.csv'));
        sub_fig = fullfile(subdir, 'figures');
        if ~isfolder(sub_fig), mkdir(sub_fig); end
        try
            plot_delay_vs_lambda(sub, sub_fig, sprintf('Logic1 M=%d', mi));
        catch
            warning('绘图失败，跳过');
        end
        theory_validation(fullfile(subdir, 'summary.csv'), subdir);
    end

    %% Logic1 M-sweep
    fprintf('\n跑 Logic1 M-sweep...\n');
    override = struct('lambda_values', [15, 30], 'q_multi_basin_tuning', true, ...
        'resume', true, ...
        'output_dir', fullfile('results_v2','20260819_211902_f4ddfa116f71'), ...
        'cf_output_dir', fullfile('results_v2','20260820_011732_366197bb0fb1'));
    out1_msweep = run_delay_m_analysis('ready_queue', ...
        fullfile(root, 'logic1', 'M_sweep'), true, override);
    msweep1_dir = fileparts(out1_msweep);

    ms1 = readtable(out1_msweep,'VariableNamingRule','preserve');
    for li = [15, 30]
        subdir = fullfile(msweep1_dir, sprintf('lam%d', li));
        if ~isfolder(subdir), mkdir(subdir); end
        sub = ms1(ms1.lambda_base == li, :);
        writetable(sub, fullfile(subdir, 'summary.csv'));
        sub_fig = fullfile(subdir, 'figures');
        if ~isfolder(sub_fig), mkdir(sub_fig); end
        try
            plot_delay_vs_M(sub, sub_fig, sprintf('Logic1 lambda=%d', li));
        catch
            warning('绘图失败，跳过');
        end
        theory_validation(fullfile(subdir, 'summary.csv'), subdir);
    end

    %% Logic2 lambda-sweep
    fprintf('\n跑 Logic2 lambda-sweep...\n');
    cfg2 = cfg;
    cfg2.txop_mode = 'batch_M';
    cfg2.protocols = {'sf_cb','sb_cb','unslotted','s7_clean','s7_busy'};
    cfg2.n_workers = 2;
    cfg2.output_dir = [];
    exp2 = run_experiment(cfg2);

    out2 = fullfile(root, 'logic2', 'lambda_sweep');
    if ~isfolder(out2), mkdir(out2); end
    s2 = readtable(fullfile(exp2.output_dir,'summary.csv'),'VariableNamingRule','preserve');
    writetable(s2, fullfile(out2, 'merged_summary.csv'));

    for mi = [1, 5]
        subdir = fullfile(out2, sprintf('M%d', mi));
        if ~isfolder(subdir), mkdir(subdir); end
        sub = s2(s2.M == mi, :);
        writetable(sub, fullfile(subdir, 'summary.csv'));
        sub_fig = fullfile(subdir, 'figures');
        if ~isfolder(sub_fig), mkdir(sub_fig); end
        try
            plot_delay_vs_lambda(sub, sub_fig, sprintf('Logic2 M=%d', mi));
        catch
            warning('绘图失败，跳过');
        end
        theory_validation(fullfile(subdir, 'summary.csv'), subdir);
    end

    %% Logic2 M-sweep
    fprintf('\n跑 Logic2 M-sweep...\n');
    override2 = struct('lambda_values', [15, 30], 'q_multi_basin_tuning', true);
    out2_msweep = run_delay_m_analysis('batch_M', ...
        fullfile(root, 'logic2', 'M_sweep'), false, override2);
    msweep2_dir = fileparts(out2_msweep);

    ms2 = readtable(out2_msweep,'VariableNamingRule','preserve');
    for li = [15, 30]
        subdir = fullfile(msweep2_dir, sprintf('lam%d', li));
        if ~isfolder(subdir), mkdir(subdir); end
        sub = ms2(ms2.lambda_base == li, :);
        writetable(sub, fullfile(subdir, 'summary.csv'));
        sub_fig = fullfile(subdir, 'figures');
        if ~isfolder(sub_fig), mkdir(sub_fig); end
        try
            plot_delay_vs_M(sub, sub_fig, sprintf('Logic2 lambda=%d', li));
        catch
            warning('绘图失败，跳过');
        end
        theory_validation(fullfile(subdir, 'summary.csv'), subdir);
    end

    %% 饱和吞吐
    fprintf('\n跑饱和吞吐...\n');
    sat_cfg = default_saturation_config('analysis');
    sat_cfg.M_values = 1:6;
    sat_cfg.resume = false;
    sat_cfg.run_preflight_tests = false;
    sat_cfg.n_workers = 2;
    sat_cfg.protocols = {'sf_cb','sb_cb','s7_clean','s7_busy','unslotted'};
    sat_exp = run_saturation_experiment(sat_cfg);

    sat_cfg_cf = sat_cfg;
    sat_cfg_cf.protocols = {'sf_cf','sb_cf'};
    sat_cfg_cf.M_values = 1;
    sat_cfg_cf.protocol_q_grids.sf_cf = 1/40;
    sat_cfg_cf.protocol_q_grids.sb_cf = 1/40;
    sat_exp_cf = run_saturation_experiment(sat_cfg_cf);

    out_sat = fullfile(root, 'saturation');
    if ~isfolder(out_sat), mkdir(out_sat); end
    sat_sum = readtable(fullfile(sat_exp.output_dir,'saturation_summary.csv'),'VariableNamingRule','preserve');
    sat_cf_sum = readtable(fullfile(sat_exp_cf.output_dir,'saturation_summary.csv'),'VariableNamingRule','preserve');
    sat_merged = [sat_sum; sat_cf_sum];
    writetable(sat_merged, fullfile(out_sat, 'saturation_summary.csv'));
    copyfile(fullfile(sat_exp.output_dir,'figures'), fullfile(out_sat,'figures'),'f');
    copyfile(fullfile(sat_exp_cf.output_dir,'figures'), fullfile(out_sat,'figures'),'f');

    fprintf('\n===== ALL DONE =====\n');
    fprintf('结果目录: %s\n', root);
end

function plot_delay_vs_lambda(data, fig_dir, title_prefix)
    if ~isfolder(fig_dir), mkdir(fig_dir); end
    protocols = unique(data.protocol, 'stable');
    colors = lines(numel(protocols));
    markers = {'o','s','^','d','v','p','h'};
    figure('Position', [100, 100, 900, 550], 'Visible', 'off');
    hold on;
    for pi = 1:numel(protocols)
        proto = char(protocols(pi));
        rows = data(string(data.protocol)==proto, :);
        lam = double(rows.lambda_base);
        delay = double(rows.mean_delay_us);
        [lam, idx] = sort(lam);
        delay = delay(idx);
        plot(lam, delay, '-o', 'Color', colors(pi,:), ...
            'Marker', markers{pi}, 'MarkerFaceColor', colors(pi,:), ...
            'LineWidth', 1.5, 'DisplayName', proto);
    end
    hold off;
    xlabel('\lambda (pkts/STA/s)');
    ylabel('Mean end-to-end delay (\mus)');
    title(sprintf('%s: Delay vs Arrival Rate', title_prefix));
    legend('Location', 'northwest');
    grid on; set(gca, 'YScale', 'log');
    saveas(gcf, fullfile(fig_dir, 'delay_vs_lambda.png'));
    close(gcf);
    figure('Position', [100, 100, 900, 550], 'Visible', 'off');
    hold on;
    for pi = 1:numel(protocols)
        proto = char(protocols(pi));
        rows = data(string(data.protocol)==proto, :);
        lam = double(rows.lambda_base);
        acc = double(rows.mean_access_delay_us);
        [lam, idx] = sort(lam);
        acc = acc(idx);
        plot(lam, acc, '-s', 'Color', colors(pi,:), ...
            'Marker', markers{pi}, 'MarkerFaceColor', colors(pi,:), ...
            'LineWidth', 1.5, 'DisplayName', proto);
    end
    hold off;
    xlabel('\lambda (pkts/STA/s)');
    ylabel('Mean access delay (\mus)');
    title(sprintf('%s: Access Delay vs Arrival Rate', title_prefix));
    legend('Location', 'northwest');
    grid on; set(gca, 'YScale', 'log');
    saveas(gcf, fullfile(fig_dir, 'access_delay_vs_lambda.png'));
    close(gcf);
end

function plot_delay_vs_M(data, fig_dir, title_prefix)
    if ~isfolder(fig_dir), mkdir(fig_dir); end
    protocols = unique(data.protocol, 'stable');
    colors = lines(numel(protocols));
    markers = {'o','s','^','d','v','p','h'};
    figure('Position', [100, 100, 900, 550], 'Visible', 'off');
    hold on;
    for pi = 1:numel(protocols)
        proto = char(protocols(pi));
        rows = data(string(data.protocol)==proto, :);
        mv = double(rows.M);
        delay = double(rows.mean_delay_us);
        [mv, idx] = sort(mv);
        delay = delay(idx);
        plot(mv, delay, '-o', 'Color', colors(pi,:), ...
            'Marker', markers{pi}, 'MarkerFaceColor', colors(pi,:), ...
            'LineWidth', 1.5, 'DisplayName', proto);
    end
    hold off;
    xlabel('M (TXOP packets)');
    ylabel('Mean end-to-end delay (\mus)');
    title(sprintf('%s: Delay vs M', title_prefix));
    legend('Location', 'northwest');
    grid on; set(gca, 'YScale', 'log');
    saveas(gcf, fullfile(fig_dir, 'delay_vs_M.png'));
    close(gcf);
    figure('Position', [100, 100, 900, 550], 'Visible', 'off');
    hold on;
    for pi = 1:numel(protocols)
        proto = char(protocols(pi));
        rows = data(string(data.protocol)==proto, :);
        mv = double(rows.M);
        acc = double(rows.mean_access_delay_us);
        [mv, idx] = sort(mv);
        acc = acc(idx);
        plot(mv, acc, '-s', 'Color', colors(pi,:), ...
            'Marker', markers{pi}, 'MarkerFaceColor', colors(pi,:), ...
            'LineWidth', 1.5, 'DisplayName', proto);
    end
    hold off;
    xlabel('M (TXOP packets)');
    ylabel('Mean access delay (\mus)');
    title(sprintf('%s: Access Delay vs M', title_prefix));
    legend('Location', 'northwest');
    grid on; set(gca, 'YScale', 'log');
    saveas(gcf, fullfile(fig_dir, 'access_delay_vs_M.png'));
    close(gcf);
end
