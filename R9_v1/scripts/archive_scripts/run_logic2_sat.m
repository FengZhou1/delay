function run_logic2_sat()
%RUN_LOGIC2_SAT 临时脚本：用新逻辑跑 Logic2 时延 + 饱和吞吐
%   Logic2: batch_M, M=[1,5] λ=[8,15,25,30,45] + M=[1:6] λ=[15,30]
%   Saturation: M=[1:6]
%   结果写入 0819_R9_results/logic2 和 0819_R9_results/saturation
%   本脚本为临时脚本，跑完可删除；正式跑全部用 run_0819_R9

    root = fullfile(pwd, '0819_R9_results');
    if ~isfolder(root), mkdir(root); end

    %% ===== 1. Logic2 lambda-sweep =====
    fprintf('\n===== [1/3] Logic2 lambda-sweep (M=[1,5], λ=[8,15,25,30,45]) =====\n');
    cfg = default_experiment_config('analysis');
    cfg.txop_mode = 'batch_M';
    cfg.protocols = {'sf_cb','sb_cb','unslotted','s7_clean','s7_busy'};
    cfg.M_values = [1, 5];
    cfg.lambda_values = [8, 15, 25, 30, 45];
    cfg.load_modes = {'fixed_packet'};
    cfg.resume = false;          % 全新跑（新逻辑）
    cfg.run_preflight_tests = false;
    cfg.n_eval_runs = 3;
    cfg.condition_timeout_s = 1800;
    cfg.n_workers = 2;           % 2 worker，避免内存爆
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
    cfg.output_dir = [];   % 新建目录
    exp2 = run_experiment(cfg);
    fprintf('Logic2 lambda-sweep 完成: %s\n', exp2.output_dir);

    % M=1 时 batch_M 与 ready_queue 等价，补充 CF 协议 M=1 基线
    cfg2cf = cfg;
    cfg2cf.protocols = {'sf_cf','sb_cf'};
    cfg2cf.M_values = 1;
    cfg2cf.txop_mode = 'batch_M';
    exp2cf = run_experiment(cfg2cf);
    fprintf('Logic2 CF baseline 完成: %s\n', exp2cf.output_dir);

    out2 = fullfile(root, 'logic2', 'lambda_sweep');
    if ~isfolder(out2), mkdir(out2); end
    s2 = readtable(fullfile(exp2.output_dir,'summary.csv'),'VariableNamingRule','preserve');
    s2.fixed_M_baseline = false(height(s2),1);
    s2cf = readtable(fullfile(exp2cf.output_dir,'summary.csv'),'VariableNamingRule','preserve');
    s2cf.fixed_M_baseline = true(height(s2cf),1);
    merged2 = [s2; s2cf];
    writetable(merged2, fullfile(out2, 'merged_summary.csv'));
    for mi = [1, 5]
        subdir = fullfile(out2, sprintf('M%d', mi));
        if ~isfolder(subdir), mkdir(subdir); end
        sub = merged2(merged2.M == mi, :);
        writetable(sub, fullfile(subdir, 'summary.csv'));
        sub_fig = fullfile(subdir, 'figures');
        if ~isfolder(sub_fig), mkdir(sub_fig); end
        try
            plot_delay_vs_lambda(sub, sub_fig, sprintf('Logic2 M=%d', mi));
        catch ME
            fprintf('  M=%d 绘图失败: %s\n', mi, ME.message);
        end
        try
            theory_validation(fullfile(subdir,'summary.csv'), subdir);
        catch ME
            fprintf('  M=%d 理论验证失败: %s\n', mi, ME.message);
        end
    end

    %% ===== 2. Logic2 M-sweep =====
    fprintf('\n===== [2/3] Logic2 M-sweep (λ=[15,30], M=[1:6]) =====\n');
    override = struct( ...
        'lambda_values', [15, 30], ...
        'q_multi_basin_tuning', true, ...
        'resume', false, ...
        'n_workers', 2);
    out2_msweep = run_delay_m_analysis('batch_M', ...
        fullfile(root, 'logic2', 'M_sweep'), false, override);
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
            plot_delay_vs_M(sub, sub_fig, sprintf('Logic2 λ=%d', li));
        catch ME
            fprintf('  lam%d 绘图失败: %s\n', li, ME.message);
        end
        try
            theory_validation(fullfile(subdir,'summary.csv'), subdir);
        catch ME
            fprintf('  lam%d 理论验证失败: %s\n', li, ME.message);
        end
    end

    %% ===== 3. 饱和吞吐 =====
    fprintf('\n===== [3/3] 饱和吞吐 M=[1:6] =====\n');
    sat_cfg = default_saturation_config('analysis');
    sat_cfg.M_values = 1:6;
    sat_cfg.resume = false;
    sat_cfg.run_preflight_tests = false;
    sat_cfg.n_workers = 2;
    sat_cfg.protocols = {'sf_cb','sb_cb','s7_clean','s7_busy','unslotted'};
    sat_exp = run_saturation_experiment(sat_cfg);
    fprintf('饱和吞吐(主)完成: %s\n', sat_exp.output_dir);

    sat_cfg_cf = sat_cfg;
    sat_cfg_cf.protocols = {'sf_cf','sb_cf'};
    sat_cfg_cf.M_values = 1;
    sat_cfg_cf.protocol_q_grids.sf_cf = 1/40;
    sat_cfg_cf.protocol_q_grids.sb_cf = 1/40;
    sat_exp_cf = run_saturation_experiment(sat_cfg_cf);
    fprintf('饱和吞吐(CF)完成: %s\n', sat_exp_cf.output_dir);

    out_sat = fullfile(root, 'saturation');
    if ~isfolder(out_sat), mkdir(out_sat); end
    sat_sum = readtable(fullfile(sat_exp.output_dir,'saturation_summary.csv'),'VariableNamingRule','preserve');
    sat_cf_sum = readtable(fullfile(sat_exp_cf.output_dir,'saturation_summary.csv'),'VariableNamingRule','preserve');
    sat_merged = [sat_sum; sat_cf_sum];
    writetable(sat_merged, fullfile(out_sat, 'saturation_summary.csv'));
    % 用合并后的 summary 重新画图，避免同名图片被 CF 实验覆盖
    if ~isfolder(fullfile(out_sat,'figures')), mkdir(fullfile(out_sat,'figures')); end
    try
        plot_saturation_throughput_v2(out_sat);
        fprintf('饱和吞吐完整图已生成\n');
    catch ME
        warning('饱和吞吐绘图失败: %s', ME.message);
    end

    fprintf('\n===== 全部完成 =====\n');
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
