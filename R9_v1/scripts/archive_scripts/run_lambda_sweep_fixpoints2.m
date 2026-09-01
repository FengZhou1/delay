function run_lambda_sweep_fixpoints2()
%RUN_LAMBDA_SWEEP_FIXPOINTS2 Stabilize sb_cb lam=5 with 5-seed tuning
%   and 5-seed evaluation, then merge into the final sweep directory and
%   regenerate its figures.  The first fixpoint pass left this condition
%   with a very wide CI (bimodal across seeds), so more seeds are used.

    main_dir = 'results_v2\lambda_sweep_20260814_060540_597e78800cf0';

    cfg = default_experiment_config('analysis');
    cfg.protocols = {'sf_cf','sf_cb','sb_cf','sb_cb','s7_clean','s7_busy','unslotted'};
    cfg.M_values = 1;
    cfg.lambda_values = [5, 10, 16, 20];
    cfg.load_modes = {'fixed_packet'};
    cfg.resume = false;
    cfg.condition_timeout_s = 900;
    cfg.run_preflight_tests = false;

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

    cfg.condition_filter = {'sb_cb_fixed_packet_lam5_M1'};
    cfg.n_tune_runs = 5;   % 5 seeds per q point during tuning
    cfg.n_eval_runs = 5;   % 5 seeds for the final evaluation

    run_stamp = datestr(now, 'yyyymmdd_HHMMSS');
    cfg_hash = experiment_config_hash(cfg);
    cfg.output_dir = fullfile('results_v2', ['lambda_sweep_fixpoints2_' run_stamp '_' cfg_hash]);
    fprintf('Fix-points output: %s\n', cfg.output_dir);

    run_experiment(cfg);

    %% Merge the fixed row into the final sweep directory
    fix_summary = fullfile(cfg.output_dir, 'summary.csv');
    main_summary = fullfile(main_dir, 'summary.csv');
    if ~isfile(fix_summary) || ~isfile(main_summary)
        error('run_lambda_sweep_fixpoints2:MergeMissing', ...
              'Missing summary file(s) for merge.');
    end
    T = readtable(main_summary, 'VariableNamingRule', 'preserve');
    F = readtable(fix_summary, 'VariableNamingRule', 'preserve');

    if ~isfile([main_summary '.pre_fix2.bak'])
        copyfile(main_summary, [main_summary '.pre_fix2.bak']);
    end

    for r = 1:height(F)
        proto = string(F.protocol(r));
        lam = F.lambda_base(r);
        tag = sprintf('%s_fixed_packet_lam%g_M1', char(proto), lam);
        sel = string(T.protocol) == proto & T.lambda_base == lam & T.M == 1;
        if sum(sel) ~= 1
            warning('Expected exactly one row for %s, got %d; skipping merge.', tag, sum(sel));
            continue;
        end
        T(sel, :) = F(r, :);
        src_cp = fullfile(cfg.output_dir, 'checkpoints', [tag '.mat']);
        dst_cp = fullfile(main_dir, 'checkpoints', [tag '.mat']);
        if isfile(dst_cp) && ~isfile([dst_cp '.pre_fix2.bak'])
            copyfile(dst_cp, [dst_cp '.pre_fix2.bak']);
        end
        if isfile(src_cp)
            copyfile(src_cp, dst_cp);
        else
            warning('Checkpoint not found: %s', src_cp);
        end
        fprintf('Merged: %s -> best_q=%.4g delay=%.1f us (CI95 half=%.1f us)\n', ...
            tag, F.best_q(r), F.mean_delay_us(r), F.mean_delay_us_ci95(r));
    end
    writetable(T, main_summary);

    %% Regenerate figures from the merged summary
    summary = readtable(main_summary, 'VariableNamingRule', 'preserve');
    fig_dir = fullfile(main_dir, 'figures');
    if ~isfolder(fig_dir), mkdir(fig_dir); end
    plot_lambda_sweep_figures2(summary, fig_dir);
    fprintf('Figures regenerated in %s\n', fig_dir);
    fprintf('\n=== FIXPOINT2 MERGE COMPLETE ===\n');
end

function plot_lambda_sweep_figures2(summary, fig_dir)
    protocols = unique(summary.protocol, 'stable');
    colors = lines(numel(protocols));
    markers = {'o','s','^','d','v','p','h'};

    names = {'delay_vs_lambda.png', 'access_delay_vs_lambda.png', ...
             'completion_vs_lambda.png'};
    for f = 1:numel(names)
        png = fullfile(fig_dir, names{f});
        if isfile(png) && ~isfile([png '.pre_fix2.bak'])
            copyfile(png, [png '.pre_fix2.bak']);
        end
    end

    figure('Position', [100, 100, 900, 550]);
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
    saveas(gcf, fullfile(fig_dir, names{1}));
    fprintf('Figure saved: %s\n', fullfile(fig_dir, names{1}));

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
    saveas(gcf, fullfile(fig_dir, names{2}));
    fprintf('Figure saved: %s\n', fullfile(fig_dir, names{2}));

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
    saveas(gcf, fullfile(fig_dir, names{3}));
    fprintf('Figure saved: %s\n', fullfile(fig_dir, names{3}));
end