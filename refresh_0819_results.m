function refresh_0819_results()
%REFRESH_0819_RESULTS 用源目录最新 summary 刷新 0819_R9_results 并重新画图
%
%   三个源目录:
%     20260819_162657_0e9b2bf9c602  -> Logic1 lambda-sweep (50 rows)
%     20260819_202504_079a12a5cc1b  -> Logic1 CF baseline (10 rows)
%     20260819_211902_f4ddfa116f71  -> Logic1 M-sweep (60 rows)
%
%   注意: 这个脚本只刷新 Logic1 的结果（用户正在跑的 Logic2 还没完成，
%         不在此脚本范围内）。

    root = fullfile(pwd, '0819_R9_results');

    %% ===== 1. Logic1 lambda-sweep =====
    fprintf('\n===== 刷新 Logic1 lambda-sweep =====\n');
    src1 = fullfile('results_v2','20260819_162657_0e9b2bf9c602','summary.csv');
    src1cf = fullfile('results_v2','20260819_202504_079a12a5cc1b','summary.csv');

    s1 = readtable(src1,'VariableNamingRule','preserve');
    s1.fixed_M_baseline = false(height(s1),1);
    s1cf = readtable(src1cf,'VariableNamingRule','preserve');
    s1cf.fixed_M_baseline = true(height(s1cf),1);
    merged1 = [s1; s1cf];

    out1 = fullfile(root,'logic1','lambda_sweep');
    if ~isfolder(out1), mkdir(out1); end
    writetable(merged1, fullfile(out1,'merged_summary.csv'));

    for mi = [1, 5]
        subdir = fullfile(out1, sprintf('M%d', mi));
        if ~isfolder(subdir), mkdir(subdir); end
        sub = merged1(merged1.M == mi, :);
        writetable(sub, fullfile(subdir,'summary.csv'));
        sub_fig = fullfile(subdir,'figures');
        if ~isfolder(sub_fig), mkdir(sub_fig); end
        try
            plot_delay_vs_lambda(sub, sub_fig, sprintf('Logic1 M=%d', mi));
            fprintf('  绘图 M=%d 完成\n', mi);
        catch ME
            fprintf('  M=%d 绘图失败: %s\n', mi, ME.message);
        end
        try
            theory_validation(fullfile(subdir,'summary.csv'), subdir);
        catch ME
            fprintf('  M=%d 理论验证失败: %s\n', mi, ME.message);
        end
    end

    %% ===== 2. Logic1 M-sweep =====
    fprintf('\n===== 刷新 Logic1 M-sweep =====\n');
    src_ms = fullfile('results_v2','20260819_211902_f4ddfa116f71','summary.csv');
    ms1 = readtable(src_ms,'VariableNamingRule','preserve');

    out1m = fullfile(root,'logic1','M_sweep');
    if ~isfolder(out1m), mkdir(out1m); end
    writetable(ms1, fullfile(out1m,'summary.csv'));

    % CF baseline for M-sweep (fixed M=1) 来自 CF 目录, 单独画出
    for li = [15, 30]
        subdir = fullfile(out1m, sprintf('lam%d', li));
        if ~isfolder(subdir), mkdir(subdir); end
        sub = ms1(ms1.lambda_base == li, :);
        % 附加 CF 固定基线
        cf_rows = s1cf(s1cf.lambda_base == li, :);
        cf_rows.fixed_M_baseline = true(height(cf_rows),1);
        if ismember('fixed_M_baseline', sub.Properties.VariableNames)
            sub_cf = [sub; cf_rows];
        else
            sub.fixed_M_baseline = false(height(sub),1);
            sub_cf = [sub; cf_rows];
        end
        writetable(sub_cf, fullfile(subdir,'summary.csv'));
        sub_fig = fullfile(subdir,'figures');
        if ~isfolder(sub_fig), mkdir(sub_fig); end
        try
            plot_delay_vs_M(sub_cf, sub_fig, sprintf('Logic1 lambda=%d', li));
            fprintf('  绘图 lam%d 完成\n', li);
        catch ME
            fprintf('  lam%d 绘图失败: %s\n', li, ME.message);
        end
        try
            theory_validation(fullfile(subdir,'summary.csv'), subdir);
        catch ME
            fprintf('  lam%d 理论验证失败: %s\n', li, ME.message);
        end
    end

    % 也生成 plot_delay_m_comparison 风格的图
    try
        if ~isfolder(out1m), mkdir(out1m); end
        figs = plot_delay_m_comparison(ms1, out1m);
        fprintf('  plot_delay_m_comparison 生成 %d 张图\n', numel(figs));
    catch ME
        fprintf('  plot_delay_m_comparison 失败: %s\n', ME.message);
    end

    fprintf('\n===== 刷新完成 =====\n');
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
