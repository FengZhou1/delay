function png_path = plot_throughput_comparison(data, png_path)
%PLOT_THROUGHPUT_COMPARISON Normalized-throughput comparison figure.
    protocols = data.protocols;
    M = data.M_values;
    timing = data.timing;
    display_names = struct( ...
        'sf_cb','SF-CB', ...
        'batch_clear','batch\_clear', ...
        'unslotted','unslotted', ...
        'sb_cb','SB-CB');

    fig = figure('Visible','off','Color','white','Units','inches', ...
        'Position',[1 1 8 5]);
    cleanup = onCleanup(@() close(fig));
    ax = axes(fig);
    hold(ax,'on');
    ax.FontName = 'Arial';
    ax.FontSize = 15;
    ax.LineWidth = 1.2;
    ax.TickDir = 'in';
    ax.XMinorTick = 'on';
    ax.YMinorTick = 'on';
    ax.Layer = 'top';
    box(ax,'on');

    for pi = 1:numel(protocols)
        proto = protocols{pi};
        x = timing.CONN_SLOT_US * M;
        y = nan(size(x));
        for Mi = 1:numel(M)
            hit = find(strcmp({data.results.protocol},proto).' & ...
                [data.results.M].' == M(Mi), 1);
            if ~isempty(hit)
                y(Mi) = data.results(hit).throughput;
            end
        end
        plot(x, y, 'o-', 'LineWidth', 1.8, 'MarkerSize', 7);
    end

    xlabel(ax,'T_p = M \times 164.1 \mus');
    ylabel(ax,'Normalized throughput (payload airtime fraction)');
    legend(ax, cellfun(@(p) display_names.(p), protocols, ...
        'UniformOutput', false), 'Location','best');
    grid(ax,'on');
    saveas(fig, png_path);
end
