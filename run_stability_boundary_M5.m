function run_stability_boundary_M5()
%RUN_STABILITY_BOUNDARY_M5 稳定性边界扫描（M=5）
%   方案一 ready_queue，M=5，7 协议
%   λ=[30,35,40,45,50,60,70,80]
%   输出到 0819_R9_results/stability_boundary_M5/

    root = fullfile(pwd,'0819_R9_results');
    protocols_all = {'sf_cb','sb_cb','unslotted','s7_clean','s7_busy','sf_cf','sb_cf'};

    fprintf('\n===== 稳定性边界扫描 M=5 =====\n');
    cfg = default_experiment_config('analysis');
    cfg.txop_mode = 'ready_queue';
    cfg.protocols = protocols_all;
    cfg.M_values = 5;
    cfg.lambda_values = [30, 35, 40, 45, 50, 60, 70, 80, 90, 100, 120, 150, 200];
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
    cfg.output_dir = fullfile('results_v2','R9_stability_boundary_M5');
    exp_sb = run_experiment(cfg);
    fprintf('稳定性边界 M=5 扫描完成: %s\n', exp_sb.output_dir);

    sb_dir = fullfile(root,'stability_boundary','M5');
    if ~isfolder(sb_dir), mkdir(sb_dir); end
    sb_sum = readtable(fullfile(exp_sb.output_dir,'summary.csv'),'VariableNamingRule','preserve');
    writetable(sb_sum, fullfile(sb_dir,'summary.csv'));

    % 稳定边界表
    boundary = compute_stability_boundary(sb_sum);
    writetable(boundary, fullfile(sb_dir,'stability_boundary.csv'));
    fprintf('稳定边界表 M=5:\n');
    disp(boundary);

    try
        plot_stability_vs_lambda(sb_sum, fullfile(sb_dir,'figures'));
    catch ME
        warning('稳定性绘图失败: %s', ME.message);
    end
    try
        theory_validation(fullfile(sb_dir,'summary.csv'), sb_dir);
    catch ME
        warning('理论验证失败: %s', ME.message);
    end

    fprintf('\n===== 完成 =====\n');
    fprintf('结果目录: %s\n', sb_dir);
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

function plot_stability_vs_lambda(data, fig_dir)
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
    title('Stability vs Arrival Rate (M=5)');
    legend('Location','northeast'); grid on; ylim([0 1.05]);
    saveas(gcf,fullfile(fig_dir,'stability_vs_lambda.png')); close(gcf);
end
