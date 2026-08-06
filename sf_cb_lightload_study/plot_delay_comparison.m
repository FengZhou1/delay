function png_path = plot_delay_comparison(data, png_path)
%PLOT_DELAY_COMPARISON Delay comparison figure: one subplot per lambda.
    protocols = data.protocols;
    lambdas = data.lambda_values;
    M = data.M_values;
    n_rows = numel(lambdas);
    display_names = struct( ...
        'sf_cb','SF-CB', ...
        'batch_clear','batch\_clear', ...
        'unslotted','unslotted', ...
        'sb_cb','SB-CB');

    fig = figure('Visible','off','Color','white','Units','pixels', ...
        'Position',[80 80 900 1050]);
    cleanup = onCleanup(@() close(fig));
    for li = 1:n_rows
        subplot(n_rows,1,li);
        hold on;
        for pi = 1:numel(protocols)
            proto = protocols{pi};
            x = M;
            y = nan(size(x));
            for Mi = 1:numel(M)
                hit = find(strcmp({data.results.protocol},proto).' & ...
                    [data.results.lambda].' == lambdas(li) & ...
                    [data.results.M].' == M(Mi), 1);
                if ~isempty(hit)
                    y(Mi) = data.results(hit).delay_us;
                end
            end
            plot(x, y, 'o-', 'LineWidth', 1.6, 'MarkerSize', 6);
        end
        set(gca,'YScale','log','FontSize',12,'TickDir','in');
        xlabel('M');
        ylabel('Mean end-to-end delay (\mus)');
        title(sprintf('\\lambda = %g pkt/s/node', lambdas(li)));
        grid on;
    end
    names = cell(size(protocols));
    for i = 1:numel(protocols)
        names{i} = display_names.(protocols{i});
    end
    legend(names, 'Location','best');
    saveas(fig, png_path);
end
