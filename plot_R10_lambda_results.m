function plot_R10_lambda_results(out_dir, run_label)
%PLOT_R10_LAMBDA_RESULTS Draw R10 lambda-sweep delay results.
%   Reads R10_results/lambda_sweep/summary.csv and produces
%   delay/access/queue vs total-load figures with distinguishable styles.

    if nargin < 1 || isempty(out_dir)
        out_dir = fullfile(pwd,'R10_results','lambda_sweep');
    end
    if nargin < 2 || isempty(run_label)
        run_label = 'R10';
    end
    data = readtable(fullfile(out_dir,'summary.csv'), ...
        'VariableNamingRule','preserve');
    if ~ismember('total_load', data.Properties.VariableNames)
        data.total_load = double(data.lambda_base) * 40 * 162.5e-6;
    end
    if ~isfolder(fullfile(out_dir,'figures'))
        mkdir(fullfile(out_dir,'figures'));
    end

    plot_metric(data, out_dir, 'mean_delay_us', ...
        'Mean end-to-end delay (\mus)', 'delay_vs_load', run_label);
    plot_metric(data, out_dir, 'mean_access_delay_us', ...
        'Mean access delay (\mus)', 'access_delay_vs_load', run_label);
    plot_metric(data, out_dir, 'mean_queue_delay_us', ...
        'Mean queue delay (\mus)', 'queue_delay_vs_load', run_label);
end

function plot_metric(data, out_dir, metric, y_label, file_tag, run_label)
    proto_order = {'sf_cf','sf_cb','sb_cf','sb_cb', ...
        'unslotted','s7_clean','s7_busy'};
    fig = figure('Visible','off','Color','white','Units','pixels', ...
        'Position',[100 100 1300 620]);
    hold on;
    handles = gobjects(0);
    names = {};
    for i = 1:numel(proto_order)
        p = proto_order{i};
        keep_p = string(data.protocol) == p;
        if ~any(keep_p), continue; end
        Ms = unique(double(data.M(keep_p)));
        for j = 1:numel(Ms)
            M = Ms(j);
            sub = data(keep_p & abs(double(data.M)-M) < 1e-9, :);
            if isempty(sub), continue; end
            x = double(sub.total_load);
            y = double(sub.(metric));
            unstable = double(sub.stable_fraction) < 1-1e-12 | ...
                double(sub.completion_ratio) < 0.99;
            [x, order] = sort(x);
            y = y(order);
            unstable = unstable(order);
            color = protocol_color(p);
            marker = protocol_marker(p);
            line_style = '--';
            if abs(M-1) < 1e-9, line_style = '-'; end
            if any(~unstable)
                plot(x(~unstable), y(~unstable), ...
                    'Color', color, 'LineStyle', line_style, ...
                    'Marker', marker, 'LineWidth', 1.6, ...
                    'MarkerSize', 6, 'MarkerFaceColor', color, ...
                    'DisplayName', display_protocol(p, M));
            end
            if any(unstable)
                plot(x(unstable), y(unstable), ...
                    'Color', color, 'LineStyle', 'none', ...
                    'Marker', marker, 'LineWidth', 1.6, ...
                    'MarkerSize', 6, 'MarkerFaceColor', 'none', ...
                    'HandleVisibility', 'off');
            end
        end
    end
    hold off;
    grid on; box on;
    xlabel('Total offered load');
    ylabel(y_label);
    title(sprintf('%s vs total load (%s)', metric, run_label));
    set(gca,'YScale','log');
    xlim([0 1]);
    legend('Location','eastoutside','Interpreter','none','FontSize',11);
    exportgraphics(fig, fullfile(out_dir,'figures',[file_tag '.png']), ...
        'Resolution', 300);
    close(fig);
end

function color = protocol_color(protocol)
    switch protocol
        case 'sf_cf'
            color = [0.00 0.35 0.75];
        case 'sb_cf'
            color = [0.30 0.75 0.93];
        case 'sf_cb'
            color = [0.75 0.05 0.15];
        case 'sb_cb'
            color = [0.95 0.50 0.10];
        case 'unslotted'
            color = [0.20 0.60 0.20];
        case 's7_clean'
            color = [0.60 0.20 0.80];
        case 's7_busy'
            color = [0.00 0.65 0.65];
        otherwise
            color = [0.3 0.3 0.3];
    end
end

function marker = protocol_marker(protocol)
    switch protocol
        case 'sf_cf'
            marker = 'o';
        case 'sb_cf'
            marker = 's';
        case 'sf_cb'
            marker = '^';
        case 'sb_cb'
            marker = 'd';
        case 'unslotted'
            marker = 'v';
        case 's7_clean'
            marker = 'p';
        case 's7_busy'
            marker = 'h';
        otherwise
            marker = 'o';
    end
end

function label = display_protocol(protocol, M)
    switch protocol
        case 'sf_cf',      base = 'SF-CF';
        case 'sf_cb',      base = 'SF-CB';
        case 'sb_cf',      base = 'SB-CF';
        case 'sb_cb',      base = 'SB-CB';
        case 'unslotted',  base = 'Unslotted';
        case 's7_clean',   base = 'S7-AN(nS=0)';
        case 's7_busy',    base = 'S7-AN(nS=10)';
        otherwise,         base = protocol;
    end
    label = sprintf('%s(M=%g)', base, M);
end
