function output = plot_sfcb_lightload_results(condition_table,output_dir)
%PLOT_SFCB_LIGHTLOAD_RESULTS One figure for total, queue and access delay.

    required = {'variant','lambda_per_node','M','Tp_us', ...
        'mean_total_delay_us','mean_queue_delay_us','mean_access_delay_us'};
    if any(~ismember(required,condition_table.Properties.VariableNames))
        error('plot_sfcb_lightload_results:MissingColumns', ...
            'Condition table does not contain all delay metrics.');
    end

    figure_dir = fullfile(output_dir,'figures');
    if ~exist(figure_dir,'dir'), mkdir(figure_dir); end
    png_path = fullfile(figure_dir, ...
        'sf_cb_lightload_delay_comparison.png');
    pdf_path = fullfile(figure_dir, ...
        'sf_cb_lightload_delay_comparison.pdf');

    all_variants = {'baseline','fast_first','unslotted','batch_clear'};
    all_names = {'Original SF-CB','Fast-first','Unslotted','Batch-clear'};
    all_colors = [ ...
        0.35 0.55 0.75; ...
        0.90 0.55 0.20; ...
        0.35 0.65 0.40; ...
        0.60 0.40 0.70];
    all_markers = {'o','s','^','d'};
    present = false(size(all_variants));
    for i = 1:numel(all_variants)
        present(i) = any(string(condition_table.variant)==all_variants{i});
    end
    variants = all_variants(present);
    names = all_names(present);
    colors = all_colors(present,:);
    markers = all_markers(present);
    if isempty(variants)
        error('plot_sfcb_lightload_results:NoKnownVariant', ...
            'Condition table contains no recognized SF-CB variant.');
    end
    metrics = {'mean_total_delay_us','mean_queue_delay_us', ...
        'mean_access_delay_us'};
    metric_titles = {'End-to-end delay','Queueing delay','Access delay'};
    lambdas = unique(double(condition_table.lambda_per_node)).';

    fig_height = max(4.8,2.6*numel(lambdas));
    fig = figure('Visible','off','Color','white','Units','inches', ...
        'Position',[1 1 12 fig_height]);
    cleanup = onCleanup(@() close(fig));
    layout = tiledlayout(fig,numel(lambdas),3, ...
        'TileSpacing','compact','Padding','compact');
    handles = gobjects(numel(variants),1);

    for li = 1:numel(lambdas)
        lambda = lambdas(li);
        for mi = 1:numel(metrics)
            ax = nexttile(layout,(li-1)*3+mi);
            hold(ax,'on');
            for vi = 1:numel(variants)
                keep = string(condition_table.variant)==variants{vi} & ...
                    condition_table.lambda_per_node==lambda;
                subset = condition_table(keep,:);
                [x,order] = sort(double(subset.Tp_us));
                y = double(subset.(metrics{mi})(order))/1000;
                h = plot(ax,x,y,'LineWidth',2.1, ...
                    'Color',colors(vi,:),'Marker',markers{vi}, ...
                    'MarkerSize',6.5,'MarkerFaceColor','white');
                if li==1 && mi==1
                    handles(vi) = h;
                end
            end
            grid(ax,'on');
            box(ax,'on');
            ax.FontName = 'Arial';
            ax.FontSize = 10.5;
            ax.LineWidth = 1;
            title(ax,sprintf('%s,  \\lambda = %g pkt/STA/s', ...
                metric_titles{mi},lambda),'FontWeight','normal');
            xlabel(ax,'T_p (\mus)');
            ylabel(ax,'Mean delay (ms)');
            xlim(ax,[0 max(condition_table.Tp_us)*1.04]);
            ylim(ax,[0 inf]);
        end
    end
    lgd = legend(handles,names,'Orientation','horizontal', ...
        'NumColumns',numel(variants),'Box','off');
    lgd.Layout.Tile = 'north';
    title(layout,'SF-CB light-load MAC variants', ...
        'FontName','Arial','FontSize',14,'FontWeight','normal');

    exportgraphics(fig,png_path,'Resolution',400);
    exportgraphics(fig,pdf_path,'ContentType','vector');
    output = struct('png_path',png_path,'pdf_path',pdf_path);
end
