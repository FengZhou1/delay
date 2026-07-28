%GEN_DELAY_PLOTS  Generate queue_delay_by_M.png and access_delay_by_M.png
%   from existing summary.csv files, without re-running the full analysis.
%   Reads the summary CSV in a result directory and its combined_view subfolder,
%   then writes the two new figures into each figures/ subfolder.

function gen_delay_plots(result_dir)
    if nargin < 1 || isempty(result_dir)
        error('gen_delay_plots:MissingDirectory', 'A result directory is required.');
    end

    targets = { ...
        fullfile(result_dir, 'summary.csv'), ...
        fullfile(result_dir, 'figures'), ...
        fullfile(result_dir, 'combined_view', 'summary.csv'), ...
        fullfile(result_dir, 'combined_view', 'figures') ...
    };

    for ti = 1:2:numel(targets)
        csv_path = targets{ti};
        fig_dir  = targets{ti+1};
        if ~isfile(csv_path) || ~isfolder(fig_dir)
            fprintf('Skip (missing): %s\n', csv_path);
            continue;
        end
        fprintf('Processing: %s\n', csv_path);
        summary = readtable(csv_path, 'VariableNamingRule', 'preserve');

        gen_one(summary, 'mean_queue_delay_us', ...
            'Mean queue delay (us)', 'Steady-state mean queue delay', ...
            fullfile(fig_dir, 'queue_delay_by_M.png'));

        gen_one(summary, 'mean_access_delay_us', ...
            'Mean access delay (us)', 'Steady-state mean access delay', ...
            fullfile(fig_dir, 'access_delay_by_M.png'));
    end
    fprintf('Done.\n');
end

function gen_one(summary, metric, y_label, title_prefix, out_path)
    required = {'protocol','load_mode','lambda_base','M',metric};
    if isempty(summary) || ~all(ismember(required, summary.Properties.VariableNames))
        fprintf('  Skip %s: missing columns\n', metric);
        return;
    end

    protocol = string(summary.protocol);
    load_mode = string(summary.load_mode);
    lambda = double(summary.lambda_base);
    M = double(summary.M);
    y = double(summary.(metric));

    % Only show stable points
    if ismember('stable_fraction', summary.Properties.VariableNames)
        stable_fraction = double(summary.stable_fraction);
        y(stable_fraction < 1-1e-12) = NaN;
    else
        y(:) = NaN;
    end

    valid_panel = ~ismissing(load_mode) & isfinite(lambda);
    panel_keys = unique(load_mode(valid_panel) + "|" + string(lambda(valid_panel)), 'stable');
    if isempty(panel_keys)
        fprintf('  Skip %s: no valid panels\n', metric);
        return;
    end

    fig = figure('Visible','off','Color','w','Position',[100 100 1200 700]);
    cleanup = onCleanup(@() close(fig));
    layout = tiledlayout(fig, 'flow', 'TileSpacing','compact', 'Padding','compact');
    protocols = unique(protocol, 'stable');
    colors = lines(max(numel(protocols),1));

    for pi = 1:numel(panel_keys)
        parts = split(panel_keys(pi), '|');
        mode_i = parts(1); lambda_i = str2double(parts(2));
        ax = nexttile(layout);
        hold(ax, 'on'); grid(ax, 'on'); box(ax, 'on');
        for ri = 1:numel(protocols)
            mask = protocol == protocols(ri) & load_mode == mode_i & lambda == lambda_i;
            x_i = M(mask); y_i = y(mask);
            [x_i, order] = sort(x_i); y_i = y_i(order);
            if isempty(x_i), continue; end
            plot(ax, x_i, y_i, '-o', 'LineWidth',1.25, 'MarkerSize',4, ...
                'Color',colors(ri,:), 'DisplayName',display_protocol(protocols(ri)));
        end
        xlabel(ax, 'M'); ylabel(ax, y_label);
        title(ax, sprintf('%s, \\lambda_{base}=%g', ...
              display_load_mode(mode_i), lambda_i), 'Interpreter','tex');
        xticks(ax, unique(M(isfinite(M))));
        set(ax, 'YScale','log');
        if pi == 1, legend(ax, 'Location','best','Interpreter','none'); end
    end
    title(layout, title_prefix);
    exportgraphics(fig, out_path, 'Resolution',180);
    fprintf('  Written: %s\n', out_path);
end

function label = display_protocol(protocol)
    switch lower(char(protocol))
        case 'sf_cf', label = 'SF-CF';
        case 'sf_cb', label = 'SF-CB';
        case 'sb_cf', label = 'SB-CF';
        case 'sb_cb', label = 'SB-CB';
        case 's7_clean', label = 'S7-AS (n_S=0)';
        case 's7_busy', label = 'S7-AS (n_S=10)';
        otherwise, label = char(protocol);
    end
end

function label = display_load_mode(mode)
    switch lower(char(mode))
        case 'fixed_packet', label = 'fixed pkt/STA/s';
        case 'fixed_payload', label = 'fixed normalized payload';
        otherwise, label = char(mode);
    end
end
