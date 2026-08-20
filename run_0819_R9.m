function run_0819_R9()
%RUN_0819_R9 V1 主控脚本：方案一 + 方案二时延与饱和吞吐结果
%   结果全部输出到 0819_R9_results/ 文件夹
%
% 实验内容：
%   Logic1-λ-sweep: M=[1,5], λ=[8,15,25,30,45], ready_queue
%   Logic1-M-sweep: λ=[15,30], M=[1:6], ready_queue
%   Logic2-λ-sweep: M=[1,5], λ=[8,15,25,30,45], batch_M
%   Logic2-M-sweep: λ=[15,30], M=[1:6], batch_M
%   Saturation: M=[1:6], 全部协议

    root = fullfile(pwd, '0819_R9_results');
    if ~isfolder(root), mkdir(root); end

    %% ========== 1. Logic1 (ready_queue) λ-sweep ==========
    fprintf('\n===== Logic1 λ-sweep (M=[1,5], λ=[8,15,25,30,45]) =====\n');
    cfg1 = default_experiment_config('analysis');
    cfg1.txop_mode = 'ready_queue';
    cfg1.protocols = {'sf_cb','sb_cb','unslotted','s7_clean','s7_busy'};
    cfg1.M_values = [1, 5];
    cfg1.lambda_values = [8, 15, 25, 30, 45];
    cfg1.load_modes = {'fixed_packet'};
    cfg1.resume = true;
    cfg1.run_preflight_tests = false;
    cfg1.n_eval_runs = 3;
    cfg1.condition_timeout_s = 1800;
    cfg1.n_workers = 2;
    cfg1.q_multi_basin_tuning = true;
    qgrid = build_piecewise_q_grid(NaN);
    cfg1.q_coarse = qgrid;
    cfg1.protocol_q_grids_enabled = true;
    for p = 1:numel(cfg1.protocols)
        cfg1.protocol_q_grids.(cfg1.protocols{p}) = qgrid;
    end
    cfg1.stability_rate_tolerance = 0.05;
    cfg1.stability_censor_tolerance = 0.01;
    cfg1.stability_slope_fraction = 0.05;
    cfg1.stability_require_slope = true;
    exp1 = run_experiment(cfg1);

    % CF baseline (M=1 only)
    cfg1cf = cfg1;
    cfg1cf.protocols = {'sf_cf','sb_cf'};
    cfg1cf.M_values = 1;
    cfg1cf.protocol_q_grids.sf_cf = qgrid;
    cfg1cf.protocol_q_grids.sb_cf = qgrid;
    exp1cf = run_experiment(cfg1cf);

    % 合并并保存到 logic1/lambda_sweep/
    out1_lambda = fullfile(root, 'logic1', 'lambda_sweep');
    if ~isfolder(out1_lambda), mkdir(out1_lambda); end

    s1 = readtable(fullfile(exp1.output_dir,'summary.csv'),'VariableNamingRule','preserve');
    s1.fixed_M_baseline = false(height(s1),1);
    s1cf = readtable(fullfile(exp1cf.output_dir,'summary.csv'),'VariableNamingRule','preserve');
    s1cf.fixed_M_baseline = true(height(s1cf),1);
    merged1 = [s1; s1cf];
    writetable(merged1, fullfile(out1_lambda, 'merged_summary.csv'));

    % 按 M 分拆保存
    for mi = [1, 5]
        subdir = fullfile(out1_lambda, sprintf('M%d', mi));
        if ~isfolder(subdir), mkdir(subdir); end
        sub = merged1(merged1.M == mi, :);
        writetable(sub, fullfile(subdir, 'summary.csv'));
        sub_fig = fullfile(subdir, 'figures');
        if ~isfolder(sub_fig), mkdir(sub_fig); end
        plot_delay_vs_lambda(sub, sub_fig, sprintf('Logic1 M=%d', mi));
        % 理论验证
        theory_validation(fullfile(subdir, 'summary.csv'), subdir);
    end

    %% ========== 2. Logic1 (ready_queue) M-sweep ==========
    fprintf('\n===== Logic1 M-sweep (λ=[15,30], M=[1:6]) =====\n');
    override = struct('lambda_values', [15, 30], 'q_multi_basin_tuning', true);
    out1_msweep = run_delay_m_analysis('ready_queue', ...
        fullfile(root, 'logic1', 'M_sweep'), true, override);

    % 按 λ 分拆保存并做理论验证
    ms1 = readtable(fullfile(out1_msweep, 'summary.csv'),'VariableNamingRule','preserve');
    for li = [15, 30]
        subdir = fullfile(out1_msweep, sprintf('lam%d', li));
        if ~isfolder(subdir), mkdir(subdir); end
        sub = ms1(ms1.lambda_base == li, :);
        writetable(sub, fullfile(subdir, 'summary.csv'));
        sub_fig = fullfile(subdir, 'figures');
        if ~isfolder(sub_fig), mkdir(sub_fig); end
        plot_delay_vs_M(sub, sub_fig, sprintf('Logic1 λ=%d', li));
        theory_validation(fullfile(subdir, 'summary.csv'), subdir);
    end

    %% ========== 3. Logic2 (batch_M) λ-sweep ==========
    fprintf('\n===== Logic2 λ-sweep (M=[1,5], λ=[8,15,25,30,45]) =====\n');
    cfg2 = default_experiment_config('analysis');
    cfg2.txop_mode = 'batch_M';
    cfg2.protocols = {'sf_cb','sb_cb','unslotted','s7_clean','s7_busy'};
    cfg2.M_values = [1, 5];
    cfg2.lambda_values = [8, 15, 25, 30, 45];
    cfg2.load_modes = {'fixed_packet'};
    cfg2.resume = true;
    cfg2.run_preflight_tests = false;
    cfg2.n_eval_runs = 3;
    cfg2.condition_timeout_s = 1800;
    cfg2.n_workers = 2;
    cfg2.q_multi_basin_tuning = true;
    cfg2.q_coarse = qgrid;
    cfg2.protocol_q_grids_enabled = true;
    for p = 1:numel(cfg2.protocols)
        cfg2.protocol_q_grids.(cfg2.protocols{p}) = qgrid;
    end
    cfg2.stability_rate_tolerance = 0.05;
    cfg2.stability_censor_tolerance = 0.01;
    cfg2.stability_slope_fraction = 0.05;
    cfg2.stability_require_slope = true;
    exp2 = run_experiment(cfg2);

    % M=1 时 batch_M 与 ready_queue 等价，补充 CF 协议 M=1 基线
    fprintf('Logic2 CF baseline (sf_cf/sb_cf, M=1)...\n');
    cfg2cf = cfg2;
    cfg2cf.protocols = {'sf_cf','sb_cf'};
    cfg2cf.M_values = 1;
    cfg2cf.txop_mode = 'batch_M';
    exp2cf = run_experiment(cfg2cf);

    out2_lambda = fullfile(root, 'logic2', 'lambda_sweep');
    if ~isfolder(out2_lambda), mkdir(out2_lambda); end
    s2 = readtable(fullfile(exp2.output_dir,'summary.csv'),'VariableNamingRule','preserve');
    s2.fixed_M_baseline = false(height(s2),1);
    s2cf = readtable(fullfile(exp2cf.output_dir,'summary.csv'),'VariableNamingRule','preserve');
    s2cf.fixed_M_baseline = true(height(s2cf),1);
    merged2 = [s2; s2cf];
    writetable(merged2, fullfile(out2_lambda, 'merged_summary.csv'));

    for mi = [1, 5]
        subdir = fullfile(out2_lambda, sprintf('M%d', mi));
        if ~isfolder(subdir), mkdir(subdir); end
        sub = merged2(merged2.M == mi, :);
        writetable(sub, fullfile(subdir, 'summary.csv'));
        sub_fig = fullfile(subdir, 'figures');
        if ~isfolder(sub_fig), mkdir(sub_fig); end
        plot_delay_vs_lambda(sub, sub_fig, sprintf('Logic2 M=%d', mi));
        theory_validation(fullfile(subdir, 'summary.csv'), subdir);
    end

    %% ========== 4. Logic2 (batch_M) M-sweep ==========
    fprintf('\n===== Logic2 M-sweep (λ=[15,30], M=[1:6]) =====\n');
    override2 = struct('lambda_values', [15, 30], 'q_multi_basin_tuning', true);
    out2_msweep = run_delay_m_analysis('batch_M', ...
        fullfile(root, 'logic2', 'M_sweep'), false, override2);

    ms2 = readtable(fullfile(out2_msweep, 'summary.csv'),'VariableNamingRule','preserve');
    for li = [15, 30]
        subdir = fullfile(out2_msweep, sprintf('lam%d', li));
        if ~isfolder(subdir), mkdir(subdir); end
        sub = ms2(ms2.lambda_base == li, :);
        writetable(sub, fullfile(subdir, 'summary.csv'));
        sub_fig = fullfile(subdir, 'figures');
        if ~isfolder(sub_fig), mkdir(sub_fig); end
        plot_delay_vs_M(sub, sub_fig, sprintf('Logic2 λ=%d', li));
        theory_validation(fullfile(subdir, 'summary.csv'), subdir);
    end

    %% ========== 5. 饱和吞吐 ==========
    fprintf('\n===== Saturation M=[1:6] =====\n');
    sat_cfg = default_saturation_config('analysis');
    sat_cfg.M_values = 1:6;
    sat_cfg.resume = true;
    sat_cfg.run_preflight_tests = false;
    % CF 协议只跑 M=1
    sat_cfg.protocols = {'sf_cb','sb_cb','s7_clean','s7_busy','unslotted'};
    sat_exp = run_saturation_experiment(sat_cfg);
    % 单独跑 CF 协议 M=1
    sat_cfg_cf = sat_cfg;
    sat_cfg_cf.protocols = {'sf_cf','sb_cf'};
    sat_cfg_cf.M_values = 1;
    sat_cfg_cf.protocol_q_grids.sf_cf = 1/40;   % ALOHA 最优 q=1/N
    % sb_cf 是 CSMA 无 RTS，饱和下需要更小 q，保留 default 的 logspace 网格自动扫描
    sat_cfg_cf.protocol_q_grids.sb_cf = unique([ ...
        logspace(-5, log10(3e-2), 13), 1e-3, 3e-3, 1e-2, 3e-2]);
    sat_exp_cf = run_saturation_experiment(sat_cfg_cf);

    out_sat = fullfile(root, 'saturation');
    if ~isfolder(out_sat), mkdir(out_sat); end
    sat_sum = readtable(fullfile(sat_exp.output_dir,'saturation_summary.csv'),...
        'VariableNamingRule','preserve');
    sat_cf_sum = readtable(fullfile(sat_exp_cf.output_dir,'saturation_summary.csv'),...
        'VariableNamingRule','preserve');
    sat_merged = [sat_sum; sat_cf_sum];
    writetable(sat_merged, fullfile(out_sat, 'saturation_summary.csv'));
    % 用合并后的 summary 重新画图，避免同名图片被 CF 实验覆盖
    if ~isfolder(fullfile(out_sat,'figures')), mkdir(fullfile(out_sat,'figures')); end
    try
        plot_saturation_throughput_v2(out_sat);
        fprintf('饱和吞吐完整图已生成: %s\n', fullfile(out_sat,'figures','saturation_throughput_vs_Tp.png'));
    catch ME
        warning('饱和吞吐绘图失败: %s', ME.message);
    end

    %% ========== 6. 生成 README ==========
    write_readme(root);

    fprintf('\n===== ALL DONE =====\n');
    fprintf('结果目录: %s\n', root);
end

function plot_delay_vs_lambda(data, fig_dir, title_prefix)
%PLOT_DELAY_VS_LAMBDA 画时延 vs λ 图
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
    grid on;
    set(gca, 'YScale', 'log');
    saveas(gcf, fullfile(fig_dir, 'delay_vs_lambda.png'));
    close(gcf);

    % 接入时延图
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
    grid on;
    set(gca, 'YScale', 'log');
    saveas(gcf, fullfile(fig_dir, 'access_delay_vs_lambda.png'));
    close(gcf);
end

function plot_delay_vs_M(data, fig_dir, title_prefix)
%PLOT_DELAY_VS_M 画时延 vs M 图
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
    grid on;
    set(gca, 'YScale', 'log');
    saveas(gcf, fullfile(fig_dir, 'delay_vs_M.png'));
    close(gcf);

    % 接入时延图
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
    grid on;
    set(gca, 'YScale', 'log');
    saveas(gcf, fullfile(fig_dir, 'access_delay_vs_M.png'));
    close(gcf);
end

function write_readme(root)
    path = fullfile(root, 'README.md');
    fid = fopen(path, 'w');
    if fid < 0, return; end
    cleanup = onCleanup(@() fclose(fid));
    fprintf(fid, '# 0819_R9_results V1\n\n');
    fprintf(fid, '- 方案一(ready_queue) + 方案二(batch_M)\n');
    fprintf(fid, '- 固定M=[1,5], 扫描λ=[8,15,25,30,45] (系统负载0.05,0.1,0.16,0.2,0.3)\n');
    fprintf(fid, '- 固定λ=[15,30], 扫描M=[1:6]\n');
    fprintf(fid, '- 饱和吞吐 M=[1:6]\n');
    fprintf(fid, '- SF-CF/SB-CF 仅在方案一 M=1 时运行\n');
    fprintf(fid, '- 每个条件 3 个评估种子\n');
    fprintf(fid, '- q 调优: 分段粗扫 + 多盆地细扫 + 候选验证\n\n');
    fprintf(fid, '## 目录结构\n\n');
    fprintf(fid, '```\n');
    for d = {'logic1','logic2','saturation'}
        dd = d{1};
        fprintf(fid, '%s/\n', dd);
        if ismember(dd, {'logic1','logic2'})
            fprintf(fid, '  lambda_sweep/\n');
            fprintf(fid, '    M1/          - M=1, λ=[8,15,25,30,45]\n');
            fprintf(fid, '    M5/          - M=5, λ=[8,15,25,30,45]\n');
            fprintf(fid, '    merged_summary.csv\n');
            fprintf(fid, '  M_sweep/\n');
            fprintf(fid, '    lam15/       - λ=15, M=[1:6]\n');
            fprintf(fid, '    lam30/       - λ=30, M=[1:6]\n');
            fprintf(fid, '    summary.csv\n');
        end
        if strcmp(dd, 'saturation')
            fprintf(fid, '  saturation_summary.csv\n');
            fprintf(fid, '  figures/\n');
        end
    end
    fprintf(fid, '```\n\n');
    fprintf(fid, '每个子文件夹包含:\n');
    fprintf(fid, '- summary.csv: 实验原始数据\n');
    fprintf(fid, '- theory_validation.csv: 理论值与实验值对比\n');
    fprintf(fid, '- figures/: 时延图\n');
    fprintf(fid, '\n## 备注\n\n');
    fprintf(fid, '- V1版本, 2026-08-19\n');
    fprintf(fid, '- 理论计算使用 K_active 反推公式\n');
end
