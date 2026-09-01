function run_q1_verify()
%RUN_Q1_VERIFY 极低负载固定 q=1 理论验证
%   M=1, lambda=3, ready_queue, 所有协议固定 q=1
%   对比：理论接入时延 vs 仿真接入时延

    cfg = default_experiment_config('analysis');
    cfg.txop_mode = 'ready_queue';
    cfg.M_values = 1;
    cfg.lambda_values = 3;
    cfg.load_modes = {'fixed_packet'};
    cfg.run_preflight_tests = false;
    cfg.parallel = false;
    cfg.n_workers = 1;
    cfg.arrival_end_us = cfg.warmup_us + cfg.measure_us;
    cfg.sim_hard_end_us = cfg.arrival_end_us + cfg.drain_max_us;

    protocols = {'sf_cf','sf_cb','sb_cf','sb_cb','unslotted','s7_clean','s7_busy'};
    n_seeds = 3;
    scenario = prepare_scenario_v2(cfg, cfg.topology_seed);

    % 时序常量
    C = 162.5; S = 9.0; D = 34.0; S7_CTRL = 83.4;

    rows = struct();
    for pi = 1:numel(protocols)
        proto = protocols{pi};
        accs = nan(n_seeds,1); totals = nan(n_seeds,1); stables = false(n_seeds,1);
        for r = 1:n_seeds
            arrival_seed = experiment_arrival_seed(cfg, 3, r, 30000, 1, 2);
            trace = generate_arrival_trace(3, cfg, arrival_seed);
            proto_seed = mod(cfg.protocol_seed_base + 30000 + pi*1000000 + 1*10000 + r, 2^31-2) + 1;
            res = run_protocol_v2(proto, trace, scenario, cfg, 1, 1.0, proto_seed);
            accs(r) = res.summary.mean_access_delay_us;
            totals(r) = res.summary.mean_delay_us;
            stables(r) = res.summary.stable;
        end
        acc_mean = mean(accs,'omitnan');
        tot_mean = mean(totals,'omitnan');
        stable_frac = mean(stables);

        % 理论接入
        switch proto
            case 'sf_cf',  th = 0.5*C + C;
            case 'sf_cb',  th = 0.5*C + C + C;
            case 'sb_cf',  th = 0.5*S + D + C;
            case 'sb_cb',  th = 0.5*S + D + C + C;
            case 'unslotted', th = 0 + C + C;   % 无边界、无DIFS
            case 's7_clean', th = 0.5*S + D + S7_CTRL + C;
            case 's7_busy',  th = 0.5*S + D + S7_CTRL + C;
        end
        err_us = acc_mean - th;
        err_pct = 100*err_us/th;

        rows(pi).protocol = proto;
        rows(pi).theory = th;
        rows(pi).exp_access = acc_mean;
        rows(pi).exp_total = tot_mean;
        rows(pi).err_us = err_us;
        rows(pi).err_pct = err_pct;
        rows(pi).stable = stable_frac;
        rows(pi).seeds = accs;
    end

    % 控制台表格
    fprintf('\n=== 极低负载 M=1 固定 q=1：理论 vs 仿真 ===\n');
    fprintf('%-10s %-12s %-12s %-12s %-12s %-10s\n','协议','理论接入(us)','仿真接入(us)','误差(us)','误差%','稳定');
    fprintf('%s\n', repmat('-',1,72));
    for pi = 1:numel(protocols)
        r = rows(pi);
        fprintf('%-10s %-12.2f %-12.2f %-12.2f %-10.2f %-10.2f\n', ...
            r.protocol, r.theory, r.exp_access, r.err_us, r.err_pct, r.stable);
    end

    % 保存 CSV
    out_csv = fullfile('0819_R9_results','q1_verify_theory_experiment.csv');
    T = struct2table(rows);
    writetable(T, out_csv);
    fprintf('\nCSV 已保存: %s\n', out_csv);

    % 画对比图
    out_png = fullfile('0819_R9_results','q1_verify_theory_experiment.png');
    fig = figure('Position',[100 100 1100 520],'Visible','off','Color','w');
    protos = {rows.protocol};
    th = [rows.theory]; ex = [rows.exp_access];
    x = 1:numel(protos);
    b = bar(x, [th(:) ex(:)], 'grouped');
    b(1).FaceColor = [0.30 0.45 0.75];
    b(2).FaceColor = [0.85 0.33 0.10];
    set(gca,'XTick',x,'XTickLabel',protos,'FontSize',12);
    ylabel('接入时延 (us)','FontSize',13);
    title('M=1, q=1, lambda=3：理论 vs 仿真接入时延','FontSize',14);
    legend({'理论','仿真'},'Location','northwest');
    grid on;
    % 标注误差%
    for i = 1:numel(protos)
        text(i+0.15, ex(i)+8, sprintf('%+.1f%%',rows(i).err_pct), ...
            'FontSize',10,'HorizontalAlignment','center');
    end
    exportgraphics(fig, out_png, 'Resolution', 200);
    close(fig);
    fprintf('图已保存: %s\n', out_png);
end
