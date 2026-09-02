function run_R10_lambda_sweep()
%RUN_R10_LAMBDA_SWEEP R10 ready_queue lambda sweep (Real TXOP).
%   Only logic1 (ready_queue) is kept.  CF protocols run at M=1; CB
%   protocols run at M=1 and M=20.  The x axis is total offered load,
%   lambda = load / (n_sta * 162.5e-6).

    root = fullfile(pwd,'R10_results');
    raw_root = fullfile(root,'raw');
    out_dir = fullfile(root,'lambda_sweep');
    if ~isfolder(root), mkdir(root); end
    if ~isfolder(raw_root), mkdir(raw_root); end
    if ~isfolder(out_dir), mkdir(out_dir); end

    n_sta = 40;
    pkt_us = 162.5;
    loads = [0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.8];
    lambda_values = loads / (n_sta * pkt_us * 1e-6);

    cb_protocols = {'sf_cb','sb_cb','unslotted','s7_clean','s7_busy'};
    cf_protocols = {'sf_cf','sb_cf'};

    fprintf('===== R10 CB protocols (M=1,20) =====\n');
    cfg_cb = make_cfg(raw_root,'ready_queue',cb_protocols,[1 20],lambda_values);
    exp_cb = run_experiment(cfg_cb);

    fprintf('===== R10 CF protocols (M=1) =====\n');
    cfg_cf = make_cfg(raw_root,'ready_queue',cf_protocols,1,lambda_values);
    exp_cf = run_experiment(cfg_cf);

    s_cb = readtable(fullfile(exp_cb.output_dir,'summary.csv'), ...
        'VariableNamingRule','preserve');
    s_cf = readtable(fullfile(exp_cf.output_dir,'summary.csv'), ...
        'VariableNamingRule','preserve');
    s_cb.total_load = double(s_cb.lambda_base) * n_sta * pkt_us * 1e-6;
    s_cf.total_load = double(s_cf.lambda_base) * n_sta * pkt_us * 1e-6;
    merged = [s_cb; s_cf];
    writetable(merged, fullfile(out_dir,'summary.csv'));

    plot_lambda_metric(merged, out_dir, 'mean_delay_us', ...
        'Mean end-to-end delay (\mus)', 'delay_vs_load');
    plot_lambda_metric(merged, out_dir, 'mean_access_delay_us', ...
        'Mean access delay (\mus)', 'access_delay_vs_load');
    plot_lambda_metric(merged, out_dir, 'mean_queue_delay_us', ...
        'Mean queue delay (\mus)', 'queue_delay_vs_load');

    write_readme(out_dir, loads);
    fprintf('\n===== R10 ALL DONE =====\n');
    fprintf('Merged summary: %s\n', fullfile(out_dir,'summary.csv'));
end

function cfg = make_cfg(raw_root, txop_mode, protocols, M_values, lambda_values)
    cfg = default_experiment_config('analysis');
    cfg.txop_mode = txop_mode;
    cfg.protocols = protocols;
    cfg.M_values = M_values;
    cfg.lambda_values = lambda_values;
    cfg.load_modes = {'fixed_packet'};
    cfg.results_root = raw_root;
    cfg.resume = true;
    cfg.run_preflight_tests = false;
    cfg.n_eval_runs = 3;
    cfg.condition_timeout_s = 1800;
    cfg.n_workers = 2;
    cfg.q_multi_basin_tuning = true;
    qgrid = build_piecewise_q_grid(NaN);
    cfg.q_coarse = qgrid;
    cfg.protocol_q_grids_enabled = true;
    all_protocols = {'sf_cf','sf_cb','sb_cf','sb_cb', ...
        's7_clean','s7_busy','unslotted'};
    for p = 1:numel(all_protocols)
        cfg.protocol_q_grids.(all_protocols{p}) = qgrid;
    end
    cfg.stability_rate_tolerance = 0.05;
    cfg.stability_censor_tolerance = 0.01;
    cfg.stability_slope_fraction = 0.05;
    cfg.stability_require_slope = true;
end

function plot_lambda_metric(data, out_dir, metric, y_label, file_tag)
    if ~isfolder(fullfile(out_dir,'figures')), mkdir(fullfile(out_dir,'figures')); end
    protocols = unique(string(data.protocol));
    Ms = unique(double(data.M));
    rows = {};
    for i = 1:numel(protocols)
        for j = 1:numel(Ms)
            if any(string(data.protocol) == protocols(i) & ...
                    abs(double(data.M)-Ms(j)) < 1e-9)
                rows(end+1,:) = {char(protocols(i)), Ms(j)}; %#ok<AGROW>
            end
        end
    end
    fig = figure('Visible','off','Position',[100 100 1000 620]);
    hold on;
    colors = lines(size(rows,1));
    for i = 1:size(rows,1)
        protocol = char(rows{i,1});
        M = rows{i,2};
        sub = data(string(data.protocol) == protocol & ...
            abs(double(data.M)-M) < 1e-9, :);
        if isempty(sub), continue; end
        x = double(sub.total_load);
        y = double(sub.(metric));
        unstable = double(sub.stable_fraction) < 1-1e-12 | ...
            double(sub.completion_ratio) < 0.99;
        [x, order] = sort(x);
        y = y(order);
        unstable = unstable(order);
        if any(unstable)
            plot(x(~unstable), y(~unstable), '-o', ...
                'Color', colors(i,:), 'LineWidth', 1.5, ...
                'MarkerFaceColor', colors(i,:), ...
                'DisplayName', display_protocol(protocol, M));
            plot(x(unstable), y(unstable), 'o', ...
                'Color', colors(i,:), 'LineWidth', 1.5, ...
                'MarkerFaceColor', 'none', ...
                'HandleVisibility', 'off');
        else
            plot(x, y, '-o', 'Color', colors(i,:), ...
                'LineWidth', 1.5, 'MarkerFaceColor', colors(i,:), ...
                'DisplayName', display_protocol(protocol, M));
        end
    end
    hold off;
    grid on; box on;
    xlabel('Total offered load');
    ylabel(y_label);
    title(sprintf('%s vs total load (R10)', metric));
    set(gca,'YScale','log');
    xlim([0 1]);
    legend('Location','northwest','Interpreter','none');
    exportgraphics(fig, fullfile(out_dir,'figures',[file_tag '.png']), ...
        'Resolution', 300);
    close(fig);
end

function label = display_protocol(protocol, M)
    switch protocol
        case 'sf_cf',  base = 'SF-CF';
        case 'sf_cb',  base = 'SF-CB';
        case 'sb_cf',  base = 'SB-CF';
        case 'sb_cb',  base = 'SB-CB';
        case 'unslotted', base = 'Unslotted';
        case 's7_clean', base = 'S7-AN(nS=0)';
        case 's7_busy',  base = 'S7-AN(nS=10)';
        otherwise, base = protocol;
    end
    label = sprintf('%s(M=%g)', base, M);
end

function write_readme(out_dir, loads)
    path = fullfile(out_dir,'README.md');
    fid = fopen(path,'w');
    if fid < 0, return; end
    cleanup = onCleanup(@() fclose(fid));
    fprintf(fid,'# R10 lambda sweep (ready_queue / Real TXOP)\n\n');
    fprintf(fid,'- TXOP: Real TXOP = min(queue, M); CF M=1, CB M=1/20\n');
    fprintf(fid,'- Total loads: %s\n', mat2str(loads));
    fprintf(fid,'- lambda = load / (40 x 162.5 us)\n');
    fprintf(fid,'- Mean delay, access delay and queue delay are plotted with a log y axis.\n');
    fprintf(fid,'- Hollow markers: conditions that could not find a stable q.\n');
end
