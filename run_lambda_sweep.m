function run_lambda_sweep()
%RUN_LAMBDA_SWEEP Delay vs arrival-rate sweep with M=1 for all protocols.
%   Fixed packet length = 1 conn_slot (162.5 us).  Scans lambda across a
%   wide range to produce a "delay vs offered load" plot for fair
%   single-packet comparison of all seven protocols.
%
%   Results are saved to results_v2/lambda_sweep_<timestamp>/ and a
%   delay-vs-lambda figure is generated.

    cfg = default_experiment_config('analysis');
    cfg.protocols = {'sf_cf','sf_cb','sb_cf','sb_cb','s7_clean','s7_busy','unslotted'};
    cfg.M_values = 1;                              % single-packet TXOP
    cfg.lambda_values = [5, 10, 16, 20];   % pkts/STA/s
    cfg.load_modes = {'fixed_packet'};
    cfg.resume = false;
    cfg.condition_timeout_s = 180;  % 3 min max per condition
    cfg.run_preflight_tests = false;
    % The analysis profile enables per-protocol q grids (non-S7 protocols are
    % capped at q=0.2 by default), so cfg.q_coarse alone would be ignored.
    % Override the grids explicitly: extend non-S7 protocols to q=0.45 and
    % keep the established S7 grids (up to q=0.95).
    qgrid_non_s7 = [0.0001:0.00005:0.00095, 0.001:0.0005:0.0095, ...
                    0.01:0.005:0.095, 0.1:0.05:0.95];
    qgrid_s7 = [0.0001:0.00005:0.0009, 0.001:0.0005:0.009, ...
                0.01:0.005:0.09, 0.1:0.05:0.95];
    cfg.q_coarse = qgrid_non_s7;
    cfg.protocol_q_grids_enabled = true;
    cfg.protocol_q_grids.sf_cf = qgrid_non_s7;
    cfg.protocol_q_grids.sf_cb = qgrid_non_s7;
    cfg.protocol_q_grids.sb_cf = qgrid_non_s7;
    cfg.protocol_q_grids.sb_cb = qgrid_non_s7;
    cfg.protocol_q_grids.unslotted = qgrid_non_s7;
    cfg.protocol_q_grids.s7_clean = qgrid_s7;
    cfg.protocol_q_grids.s7_busy = qgrid_s7;

    % Use a dedicated output directory under results_v2
    run_stamp = datestr(now, 'yyyymmdd_HHMMSS');
    cfg_hash = experiment_config_hash(cfg);
    cfg.output_dir = fullfile('results_v2', ['lambda_sweep_' run_stamp '_' cfg_hash]);
    fprintf('Output directory: %s\n', cfg.output_dir);

    fprintf('Conditions: %d lambda x %d protocols = %d total\n', ...
        numel(cfg.lambda_values), numel(cfg.protocols), ...
        numel(cfg.lambda_values)*numel(cfg.protocols));

    %% Run experiment
    experiment = run_experiment(cfg);

    %% Load summary and plot
    summary_path = fullfile(cfg.output_dir, 'summary.csv');
    if ~isfile(summary_path)
        warning('Summary not found at %s', summary_path);
        return;
    end
    summary = readtable(summary_path, 'VariableNamingRule', 'preserve');

    fig_dir = fullfile(cfg.output_dir, 'figures');
    if ~isfolder(fig_dir), mkdir(fig_dir); end

    % ---- Delay vs Lambda ----
    figure('Position', [100, 100, 900, 550]);
    protocols = unique(summary.protocol, 'stable');
    colors = lines(numel(protocols));
    markers = {'o','s','^','d','v','p','h'};
    hold on;
    for pi = 1:numel(protocols)
        proto = char(protocols(pi));
        rows = summary(string(summary.protocol)==proto, :);
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
    title('Delay vs Arrival Rate (M=1, fixed packet = 162.5 \mus)');
    legend('Location', 'northwest');
    grid on;
    set(gca, 'YScale', 'log');
    saveas(gcf, fullfile(fig_dir, 'delay_vs_lambda.png'));
    fprintf('Figure saved: %s\n', fullfile(fig_dir, 'delay_vs_lambda.png'));

    % ---- Access delay vs Lambda ----
    figure('Position', [100, 100, 900, 550]);
    hold on;
    for pi = 1:numel(protocols)
        proto = char(protocols(pi));
        rows = summary(string(summary.protocol)==proto, :);
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
    title('Access Delay vs Arrival Rate (M=1)');
    legend('Location', 'northwest');
    grid on;
    set(gca, 'YScale', 'log');
    saveas(gcf, fullfile(fig_dir, 'access_delay_vs_lambda.png'));
    fprintf('Figure saved: %s\n', fullfile(fig_dir, 'access_delay_vs_lambda.png'));

    % ---- Completion ratio vs Lambda ----
    figure('Position', [100, 100, 900, 550]);
    hold on;
    for pi = 1:numel(protocols)
        proto = char(protocols(pi));
        rows = summary(string(summary.protocol)==proto, :);
        lam = double(rows.lambda_base);
        comp = double(rows.completion_ratio);
        [lam, idx] = sort(lam);
        comp = comp(idx);
        plot(lam, comp*100, '-^', 'Color', colors(pi,:), ...
            'Marker', markers{pi}, 'MarkerFaceColor', colors(pi,:), ...
            'LineWidth', 1.5, 'DisplayName', proto);
    end
    hold off;
    xlabel('\lambda (pkts/STA/s)');
    ylabel('Completion ratio (%)');
    title('Completion Ratio vs Arrival Rate (M=1)');
    legend('Location', 'southwest');
    grid on;
    ylim([0 105]);
    saveas(gcf, fullfile(fig_dir, 'completion_vs_lambda.png'));
    fprintf('Figure saved: %s\n', fullfile(fig_dir, 'completion_vs_lambda.png'));

    fprintf('\n=== LAMBDA SWEEP COMPLETE ===\n');
    fprintf('Results: %s\n', cfg.output_dir);
    fprintf('Figures: %s\n', fig_dir);
end
