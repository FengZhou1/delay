function run_lightload_stability()
%RUN_LIGHTLOAD_STABILITY 轻负载精细扫描 + 稳定性边界扫描
%   方案一 ready_queue，M=1，7 协议
%   轻负载: λ=[2,3,5,8,10,12,15]
%   稳定性: λ=[30,35,40,45,50,60,70,80]
%   输出到 0819_R9_results/lightload_sweep 和 stability_boundary

    root = fullfile(pwd,'0819_R9_results');

    protocols_all = {'sf_cb','sb_cb','unslotted','s7_clean','s7_busy','sf_cf','sb_cf'};

    %% ===== 1. 轻负载扫描 =====
    fprintf('\n===== [1/2] 轻负载精细扫描 =====\n');
    cfg = default_experiment_config('analysis');
    cfg.txop_mode = 'ready_queue';
    cfg.protocols = protocols_all;
    cfg.M_values = 1;
    cfg.lambda_values = [2, 3, 5, 8, 10, 12, 15];
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
    for p = 1:numel(protocols_all)
        cfg.protocol_q_grids.(protocols_all{p}) = qgrid;
    end
    cfg.stability_rate_tolerance = 0.05;
    cfg.stability_censor_tolerance = 0.01;
    cfg.stability_slope_fraction = 0.05;
    cfg.stability_require_slope = true;
    cfg.output_dir = fullfile('results_v2','R9_lightload_sweep');
    exp_ll = run_experiment(cfg);
    fprintf('轻负载扫描完成: %s\n', exp_ll.output_dir);

    ll_dir = fullfile(root,'lightload_sweep');
    if ~isfolder(ll_dir), mkdir(ll_dir); end
    ll_sum = readtable(fullfile(exp_ll.output_dir,'summary.csv'),'VariableNamingRule','preserve');
    writetable(ll_sum, fullfile(ll_dir,'summary.csv'));
    try
        plot_delay_vs_lambda(ll_sum, fullfile(ll_dir,'figures'), 'Light-load M=1');
    catch ME
        warning('轻负载绘图失败: %s', ME.message);
    end
    try
        theory_validation(fullfile(ll_dir,'summary.csv'), ll_dir);
    catch ME
        warning('轻负载理论验证失败: %s', ME.message);
    end

    %% ===== 2. 稳定性边界扫描 =====
    fprintf('\n===== [2/2] 稳定性边界扫描 =====\n');
    cfg2 = cfg;
    cfg2.lambda_values = [30, 35, 40, 45, 50, 60, 70, 80];
    cfg2.output_dir = fullfile('results_v2','R9_stability_boundary');
    exp_sb = run_experiment(cfg2);
    fprintf('稳定性边界扫描完成: %s\n', exp_sb.output_dir);

    sb_dir = fullfile(root,'stability_boundary');
    if ~isfolder(sb_dir), mkdir(sb_dir); end
    sb_sum = readtable(fullfile(exp_sb.output_dir,'summary.csv'),'VariableNamingRule','preserve');
    writetable(sb_sum, fullfile(sb_dir,'summary.csv'));

    % 生成稳定边界表：每个协议最后一个 stable=1 的 λ
    boundary = compute_stability_boundary(sb_sum);
    writetable(boundary, fullfile(sb_dir,'stability_boundary.csv'));
    fprintf('稳定边界表:\n');
    disp(boundary);

    try
        plot_stability_vs_lambda(sb_sum, fullfile(sb_dir,'figures'));
    catch ME
        warning('稳定性绘图失败: %s', ME.message);
    end
    try
        theory_validation(fullfile(sb_dir,'summary.csv'), sb_dir);
    catch ME
        warning('稳定性理论验证失败: %s', ME.message);
    end

    fprintf('\n===== 全部完成 =====\n');
    fprintf('轻负载: %s\n', ll_dir);
    fprintf('稳定性边界: %s\n', sb_dir);
end

function boundary = compute_stability_boundary(summary)
% 对每个协议，找最后一个 stable_fraction==1 且 completion_ratio>=0.99 的 λ
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
        % 边界处时延
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

function plot_stability_vs_lambda(data, fig_dir)
% 画稳定/不稳定状态 vs λ
    if ~isfolder(fig_dir), mkdir(fig_dir); end
    protocols = unique(data.protocol,'stable');
    colors = lines(numel(protocols));
    figure('Position',[100 100 900 550],'Visible','off'); hold on;
    for pi=1:numel(protocols)
        proto=char(protocols(pi));
        rows=data(string(data.protocol)==proto,:);
        lam=double(rows.lambda_base);
        st=double(rows.stable_fraction);
        [lam,idx]=sort(lam); st=st(idx);
        plot(lam,st,'-o','Color',colors(pi,:),'Marker','o','MarkerFaceColor',colors(pi,:),...
            'LineWidth',1.5,'DisplayName',proto);
    end
    hold off; xlabel('\lambda (pkts/STA/s)'); ylabel('stable_fraction');
    title('Stability vs Arrival Rate (M=1)');
    legend('Location','northeast'); grid on; ylim([0 1.05]);
    saveas(gcf,fullfile(fig_dir,'stability_vs_lambda.png')); close(gcf);
end
