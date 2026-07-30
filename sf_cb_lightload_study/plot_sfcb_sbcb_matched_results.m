function output = plot_sfcb_sbcb_matched_results(condition_table,output_dir)
%PLOT_SFCB_SBCB_MATCHED_RESULTS Plot four SF-CB variants and matched SB-CB.

    required = {'variant','lambda_per_node','M','Tp_us', ...
        'mean_total_delay_us','mean_queue_delay_us','mean_access_delay_us'};
    if any(~ismember(required,condition_table.Properties.VariableNames))
        error('plot_sfcb_sbcb_matched_results:MissingColumns', ...
            'Condition table does not contain all delay metrics.');
    end

    figure_dir = fullfile(output_dir,'figures');
    if ~exist(figure_dir,'dir'), mkdir(figure_dir); end
    png_path = fullfile(figure_dir, ...
        'sf_cb_lightload_delay_comparison_with_sb_cb.png');
    pdf_path = fullfile(figure_dir, ...
        'sf_cb_lightload_delay_comparison_with_sb_cb.pdf');

    variants = {'baseline','fast_first','unslotted','batch_clear','sb_cb'};
    names = {'Original SF-CB','Fast-first','Unslotted', ...
        'Batch-clear','Matched SB-CB'};
    colors = [ ...
        0.35 0.55 0.75; ...
        0.90 0.55 0.20; ...
        0.35 0.65 0.40; ...
        0.60 0.40 0.70; ...
        0.15 0.15 0.15];
    markers = {'o','s','^','d','x'};
    line_styles = {'-','-','-','-','--'};
    metrics = {'mean_total_delay_us','mean_queue_delay_us', ...
        'mean_access_delay_us'};
    metric_titles = {'End-to-end delay','Queueing delay','Access delay'};
    lambdas = unique(double(condition_table.lambda_per_node)).';
    expected_m = unique(double(condition_table.M)).';

    fig_height = max(4.8,2.6*numel(lambdas));
    fig = figure('Visible','off','Color','white','Units','inches', ...
        'Position',[1 1 12 fig_height]);
    cleanup = onCleanup(@() close(fig));
    layout = tiledlayout(fig,numel(lambdas),3, ...
        'TileSpacing','compact','Padding','compact');
    handles = gobjects(numel(variants),1);

    for li = 1:numel(lambdas)
        lambda = lambdas(li);
        for metric_index = 1:numel(metrics)
            ax = nexttile(layout,(li-1)*3+metric_index);
            hold(ax,'on');
            for variant_index = 1:numel(variants)
                keep = string(condition_table.variant)== ...
                    variants{variant_index} & ...
                    condition_table.lambda_per_node==lambda;
                subset = condition_table(keep,:);
                if height(subset) ~= numel(expected_m)
                    error('plot_sfcb_sbcb_matched_results:IncompleteCurve', ...
                        '%s lambda=%g has %d points, expected %d.', ...
                        variants{variant_index},lambda,height(subset), ...
                        numel(expected_m));
                end
                [x,order] = sort(double(subset.Tp_us));
                y = double(subset.(metrics{metric_index})(order))/1000;
                marker_face = 'white';
                marker_size = 6.5;
                if strcmp(variants{variant_index},'sb_cb')
                    marker_face = 'none';
                    marker_size = 7.5;
                end
                h = plot(ax,x,y,'LineWidth',2.1, ...
                    'LineStyle',line_styles{variant_index}, ...
                    'Color',colors(variant_index,:), ...
                    'Marker',markers{variant_index}, ...
                    'MarkerSize',marker_size, ...
                    'MarkerFaceColor',marker_face);
                if li==1 && metric_index==1
                    handles(variant_index) = h;
                end
            end
            grid(ax,'on');
            box(ax,'on');
            ax.FontName = 'Arial';
            ax.FontSize = 10.5;
            ax.LineWidth = 1;
            title(ax,sprintf('%s,  \\lambda = %g pkt/STA/s', ...
                metric_titles{metric_index},lambda), ...
                'FontWeight','normal');
            xlabel(ax,'T_p (\mus)');
            ylabel(ax,'Mean delay (ms)');
            xlim(ax,[0 max(condition_table.Tp_us)*1.04]);
            ylim(ax,[0 inf]);
        end
    end
    lgd = legend(handles,names,'Orientation','horizontal', ...
        'NumColumns',5,'Box','off');
    lgd.Layout.Tile = 'north';
    title(layout,'SF-CB light-load variants vs matched SB-CB', ...
        'FontName','Arial','FontSize',14,'FontWeight','normal');

    exportgraphics(fig,png_path,'Resolution',400);
    exportgraphics(fig,pdf_path,'ContentType','vector');
    output = struct('png_path',png_path,'pdf_path',pdf_path);
end
