function run_logic1_m10_m15()
%RUN_LOGIC1_M10_M15 补跑 logic1 lambda_sweep 的 M=10/15
%   5 协议（不含 CF），λ=[8,15,25,30,45]
%   结果合并进 0819_R9_results/logic1/lambda_sweep

    root = fullfile(pwd,'0819_R9_results');
    out1_lambda = fullfile(root,'logic1','lambda_sweep');
    protocols = {'sf_cb','sb_cb','unslotted','s7_clean','s7_busy'};

    for mi = 1:2
        Ms = [10, 15]; M = Ms(mi);
        fprintf('\n===== 补跑 logic1 M=%d λ-sweep =====\n', M);

        cfg = default_experiment_config('analysis');
        cfg.txop_mode = 'ready_queue';
        cfg.protocols = protocols;
        cfg.M_values = M;
        cfg.lambda_values = [8, 15, 25, 30, 45];
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
        for p = 1:numel(protocols)
            cfg.protocol_q_grids.(protocols{p}) = qgrid;
        end
        cfg.stability_rate_tolerance = 0.05;
        cfg.stability_censor_tolerance = 0.01;
        cfg.stability_slope_fraction = 0.05;
        cfg.stability_require_slope = true;
        cfg.output_dir = fullfile('results_v2', sprintf('R9_logic1_lamM%d', M));
        exp = run_experiment(cfg);
        fprintf('M=%d 完成: %s\n', M, exp.output_dir);

        new = readtable(fullfile(exp.output_dir,'summary.csv'),'VariableNamingRule','preserve');
        fprintf('M=%d 行数: %d\n', M, height(new));

        % 写 M10/M15 子目录 + 图 + 理论验证
        subdir = fullfile(out1_lambda, sprintf('M%d', M));
        if ~isfolder(subdir), mkdir(subdir); end
        writetable(new, fullfile(subdir,'summary.csv'));
        sub_fig = fullfile(subdir,'figures');
        if ~isfolder(sub_fig), mkdir(sub_fig); end
        plot_delay_vs_lambda(new, sub_fig, sprintf('Logic1 M=%d', M));
        theory_validation(fullfile(subdir,'summary.csv'), subdir);
    end

    % 合并所有 M（保留 CF 行）进 merged_summary.csv
    merged_path = fullfile(out1_lambda,'merged_summary.csv');
    old = readtable(merged_path,'VariableNamingRule','preserve');
    copyfile(merged_path, [merged_path '.bak_m10m15_' datestr(now,'yyyymmdd_HHMMSS')]);

    new1 = readtable(fullfile(out1_lambda,'M1','summary.csv'),'VariableNamingRule','preserve');
    new5 = readtable(fullfile(out1_lambda,'M5','summary.csv'),'VariableNamingRule','preserve');
    new10 = readtable(fullfile(out1_lambda,'M10','summary.csv'),'VariableNamingRule','preserve');
    new15 = readtable(fullfile(out1_lambda,'M15','summary.csv'),'VariableNamingRule','preserve');
    merged = [new1; new5; new10; new15];
    % 补 CF 行（旧 merged 中 fixed_M_baseline=true 的 sf_cf/sb_cf）
    if ismember('fixed_M_baseline', old.Properties.VariableNames)
        cf = old(string(old.protocol)=="sf_cf" | string(old.protocol)=="sb_cf", :);
        merged.fixed_M_baseline = false(height(merged),1);
        merged = [merged; cf];
    end
    merged = unique(merged,'rows','stable');
    writetable(merged, merged_path);
    fprintf('merged_summary.csv 已更新，总行数 %d\n', height(merged));
    fprintf('\n===== 全部完成 =====\n');
end

function plot_delay_vs_lambda(data, fig_dir, title_prefix)
    if ~isfolder(fig_dir), mkdir(fig_dir); end
    protocols = unique(data.protocol,'stable');
    colors = lines(numel(protocols));
    markers = {'o','s','^','d','v','p','h'};
    figure('Position',[100 100 900 550],'Visible','off'); hold on;
    for pi=1:numel(protocols)
        proto=char(protocols(pi));
        rows=data(string(data.protocol)==proto,:);
        lam=double(rows.lambda_base); delay=double(rows.mean_delay_us);
        [lam,idx]=sort(lam); delay=delay(idx);
        plot(lam,delay,'-o','Color',colors(pi,:),'Marker',markers{pi},...
            'MarkerFaceColor',colors(pi,:),'LineWidth',1.5,'DisplayName',proto);
    end
    hold off; xlabel('\lambda (pkts/STA/s)'); ylabel('Mean end-to-end delay (\mus)');
    title(sprintf('%s: Delay vs Arrival Rate',title_prefix));
    legend('Location','northwest'); grid on; set(gca,'YScale','log');
    saveas(gcf,fullfile(fig_dir,'delay_vs_lambda.png')); close(gcf);
    figure('Position',[100 100 900 550],'Visible','off'); hold on;
    for pi=1:numel(protocols)
        proto=char(protocols(pi));
        rows=data(string(data.protocol)==proto,:);
        lam=double(rows.lambda_base); acc=double(rows.mean_access_delay_us);
        [lam,idx]=sort(lam); acc=acc(idx);
        plot(lam,acc,'-s','Color',colors(pi,:),'Marker',markers{pi},...
            'MarkerFaceColor',colors(pi,:),'LineWidth',1.5,'DisplayName',proto);
    end
    hold off; xlabel('\lambda (pkts/STA/s)'); ylabel('Mean access delay (\mus)');
    title(sprintf('%s: Access Delay vs Arrival Rate',title_prefix));
    legend('Location','northwest'); grid on; set(gca,'YScale','log');
    saveas(gcf,fullfile(fig_dir,'access_delay_vs_lambda.png')); close(gcf);
end
