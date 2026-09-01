function run_logic2_m5_ext()
%RUN_LOGIC2_M5_EXT 补跑 logic2 batch_M M=5 的高 λ 点
%   λ=[60,80,90,95,100]，5 协议，4 worker
%   合并进 logic2/lambda_sweep/M5 并更新 merged_summary 和图

    root = fullfile(pwd,'0819_R9_results');
    out2 = fullfile(root,'logic2','lambda_sweep');
    protocols = {'sf_cb','sb_cb','unslotted','s7_clean','s7_busy'};
    new_lams = [60, 80, 90, 95, 100];

    cfg = default_experiment_config('analysis');
    cfg.txop_mode = 'batch_M';
    cfg.protocols = protocols;
    cfg.M_values = 5;
    cfg.lambda_values = new_lams;
    cfg.load_modes = {'fixed_packet'};
    cfg.resume = true;
    cfg.run_preflight_tests = false;
    cfg.n_eval_runs = 3;
    cfg.condition_timeout_s = 1800;
    cfg.n_workers = 1;
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
    cfg.output_dir = fullfile('results_v2','R9_logic2_lamM5_ext3');
    exp = run_experiment(cfg);
    fprintf('补跑完成: %s\n', exp.output_dir);

    new = readtable(fullfile(exp.output_dir,'summary.csv'),'VariableNamingRule','preserve');
    fprintf('新增行数: %d\n', height(new));
    for i=1:height(new)
        fprintf('  %s lam=%d delay=%.1f stable=%.2f\n', char(new.protocol(i)), ...
            new.lambda_base(i), new.mean_delay_us(i), new.stable_fraction(i));
    end

    % 合并进 M5/summary.csv
    m5_path = fullfile(out2,'M5','summary.csv');
    old = readtable(m5_path,'VariableNamingRule','preserve');
    copyfile(m5_path, [m5_path '.bak_ext_' datestr(now,'yyyymmdd_HHMMSS')]);
    new = new(:, old.Properties.VariableNames);
    merged_m5 = [old; new];
    merged_m5 = unique(merged_m5,'rows','stable');
    writetable(merged_m5, m5_path);
    fprintf('M5/summary.csv 已更新，总行数 %d\n', height(merged_m5));

    % 重画 M5 图
    plot_delay_vs_lambda(merged_m5, fullfile(out2,'M5','figures'), 'Logic2 M=5');
    theory_validation(m5_path, fullfile(out2,'M5'));

    % 更新 merged_summary.csv（重新拼所有 M）
    merged_path = fullfile(out2,'merged_summary.csv');
    old_merged = readtable(merged_path,'VariableNamingRule','preserve');
    copyfile(merged_path, [merged_path '.bak_ext_' datestr(now,'yyyymmdd_HHMMSS')]);
    m1 = readtable(fullfile(out2,'M1','summary.csv'),'VariableNamingRule','preserve');
    m5 = readtable(m5_path,'VariableNamingRule','preserve');
    if ~ismember('fixed_M_baseline', m5.Properties.VariableNames)
        m5.fixed_M_baseline = false(height(m5),1);
    end
    m5 = m5(:, old_merged.Properties.VariableNames);
    merged = [m1; m5];
    merged = unique(merged,'rows','stable');
    writetable(merged, merged_path);
    fprintf('merged_summary.csv 已更新，总行数 %d\n', height(merged));
    fprintf('\n===== 完成 =====\n');
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