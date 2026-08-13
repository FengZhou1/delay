function output = plot_saturation_throughput_v2(output_dir)
%PLOT_SATURATION_THROUGHPUT_V2 Legacy-style maximum throughput versus Tp.
%
% The main plot intentionally reproduces the visual grammar of
% 老吞吐参考代�?plot_improved.py.  PCHIP is used only for display and for
% roots bracketed by measured samples; it is never extrapolated to invent an
% intersection outside the sampled domain.

    summary_path = fullfile(output_dir,'saturation_summary.csv');
    if ~exist(summary_path,'file')
        error('plot_saturation_throughput_v2:MissingSummary', ...
            'saturation_summary.csv was not found in %s.',output_dir);
    end
    data = readtable(summary_path,'VariableNamingRule','preserve');
    required = {'protocol','M','Tp_us'};
    if any(~ismember(required,data.Properties.VariableNames))
        error('plot_saturation_throughput_v2:Columns', ...
            'The saturation summary is missing required plot columns.');
    end
    if ismember('effective_payload_fraction_mean',data.Properties.VariableNames)
        throughput_column = 'effective_payload_fraction_mean';
    elseif ismember('payload_airtime_fraction_mean',data.Properties.VariableNames)
        % Backward compatibility for results created before fractional M.
        throughput_column = 'payload_airtime_fraction_mean';
    else
        error('plot_saturation_throughput_v2:Columns', ...
            'No effective-payload throughput column was found.');
    end

    protocols = {'sf_cf','sf_cb','sb_cf','sb_cb','s7_clean','s7_busy','unslotted'};
    display_names = {'SF-CF','SF-CB','SB-CF','SB-CB', ...
        'S7-AS ($n_{S}=0$)','S7-AS ($n_{S}=10$)','Unslotted-SF-CB'};
    styles = protocol_styles();

    figure_dir = fullfile(output_dir,'figures');
    if ~exist(figure_dir,'dir'), mkdir(figure_dir); end
    png_path = fullfile(figure_dir,'saturation_throughput_vs_Tp.png');
    pdf_path = fullfile(figure_dir,'saturation_throughput_vs_Tp.pdf');
    intersections_path = fullfile(output_dir,'intersections.csv');

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
    ax.XAxisLocation = 'bottom';
    ax.YAxisLocation = 'left';
    ax.Layer = 'top';      % 坐标轴层次置于最上，不被粗曲线遮�?
    box(ax,'on');

    plotted_handles = gobjects(0);
    plotted_names = cell(0,1);
    curve = struct();
    for i = 1:numel(protocols)
        protocol = protocols{i};
        keep = string(data.protocol) == string(protocol);
        if ~any(keep), continue; end
        x = double(data.Tp_us(keep));
        y = double(data.(throughput_column)(keep));
        valid = isfinite(x) & isfinite(y);
        x = x(valid); y = y(valid);
        [x,order] = sort(x); y = y(order);
        [x,unique_idx] = unique(x,'stable'); y = y(unique_idx);
        if isempty(x), continue; end

        style = styles.(protocol);
        if numel(x) >= 3
            x_smooth = linspace(min(x),max(x),225);
            y_smooth = ppval(pchip(x,y),x_smooth);
        else
            x_smooth = x;
            y_smooth = y;
        end
        n_markers = min(14,numel(x_smooth));
        marker_index = unique(round(linspace(1,numel(x_smooth),n_markers)));
        % 绘制粗线条（线宽 4.5�?
        plot(ax,x_smooth,y_smooth, ...
            'Color',style.color,'LineStyle',style.line_style, ...
            'LineWidth',4.5,'HandleVisibility','off');
        % 绘制曲线上的标记（边缘细�?.8�?
        plot(ax,x_smooth(marker_index),y_smooth(marker_index), ...
            'Color',style.color,'LineStyle','none','Marker',style.marker, ...
            'MarkerSize',10,'MarkerFaceColor','white', ...
            'MarkerEdgeColor',style.color,'LineWidth',2.0, ...
            'HandleVisibility','off');
        % 创建图例句柄（同一对象同时包含线和标记，线宽与标记边缘同为 4.5�?
        handle = plot(ax,NaN,NaN, ...
            'Color',style.color,'LineStyle',style.line_style, ...
            'LineWidth',2.5,'Marker',style.marker, ...
            'MarkerSize',10,'MarkerFaceColor','white', ...
            'MarkerEdgeColor',style.color);
        plotted_handles(end+1,1) = handle; %#ok<AGROW>
        plotted_names{end+1,1} = display_names{i}; %#ok<AGROW>
        if numel(x) >= 2
            pp = pchip(x,y);
        else
            pp = [];
        end
        curve.(protocol) = struct('x',x,'y',y,'pp',pp);
    end

    conn_slot_us = median(double(data.Tp_us)./double(data.M),'omitnan');
    intersection_rows = find_intersections(curve,conn_slot_us);
    annot_color = [140 140 140]/255;
    for i = 1:numel(intersection_rows)
        item = intersection_rows(i);
        scatter(ax,item.Tp_us,item.throughput,30,annot_color,'filled', ...
            'HandleVisibility','off');
        plot(ax,[item.Tp_us item.Tp_us],[0 item.throughput], ...
            '--','Color',annot_color,'LineWidth',1.2, ...
            'HandleVisibility','off');
    end

    xlabel(ax,'$T_p$ ($\mu$s)','Interpreter','latex','FontSize',18);
    ylabel(ax,'Maximum Throughput','FontSize',18);
    xlim(ax,[0 1200]);
    ylim(ax,[0 1]);
    xticks(ax,0:200:1200);
    grid(ax,'off');
    if ~isempty(plotted_handles)
        legend(ax,plotted_handles,plotted_names,'Interpreter','latex', ...
            'Location','southeast','FontSize',13,'Box','on', ...
            'NumColumns',1);
    end
    drawnow;
    add_intersection_arrows(fig,ax,intersection_rows);

    intersection_table = intersection_table_from_rows(intersection_rows);
    writetable(intersection_table,intersections_path);
    exportgraphics(fig,png_path,'Resolution',600);
    exportgraphics(fig,pdf_path,'ContentType','vector');

    output = struct('png_path',png_path,'pdf_path',pdf_path, ...
        'intersections_path',intersections_path, ...
        'intersections',intersection_table);
end

function styles = protocol_styles()
    blue = [127 179 209]/255;
    orange = [232 161 76]/255;
    green = [94 156 94]/255;
    styles = struct();
    styles.sf_cf = style(blue,'o','-');
    styles.sf_cb = style(orange,'o',':');
    styles.sb_cf = style(blue,'s','-');
    styles.sb_cb = style(orange,'s',':');
    styles.s7_clean = style(green,'^','-');
    styles.s7_busy = style(green,'^',':');
    red = [217 83 79]/255;
    styles.unslotted = style(red,'d','-');
end

function value = style(color,marker,line_style)
    value = struct('color',color,'marker',marker,'line_style',line_style);
end

function rows = find_intersections(curve,conn_slot_us)
    pairs = {{'sf_cf','sf_cb','SF-CF','SF-CB'}, ...
             {'sb_cf','sb_cb','SB-CF','SB-CB'}};
    rows = struct('protocol_a',{},'protocol_b',{},'Tp_us',{}, ...
        'M_equivalent',{},'throughput',{});
    for p = 1:numel(pairs)
        spec = pairs{p};
        a = spec{1}; b = spec{2};
        if ~isfield(curve,a) || ~isfield(curve,b), continue; end
        ca = curve.(a); cb = curve.(b);
        common_x = intersect(ca.x,cb.x);
        if numel(common_x) < 2, continue; end
        da = ppval(ca.pp,common_x);
        db = ppval(cb.pp,common_x);
        difference = da-db;
        roots = zeros(0,1);
        for i = 1:numel(common_x)-1
            if difference(i) == 0
                roots(end+1,1) = common_x(i); %#ok<AGROW>
            elseif difference(i)*difference(i+1) < 0
                objective = @(x) ppval(ca.pp,x)-ppval(cb.pp,x);
                roots(end+1,1) = fzero(objective, ...
                    [common_x(i),common_x(i+1)]); %#ok<AGROW>
            end
        end
        if difference(end) == 0
            roots(end+1,1) = common_x(end); %#ok<AGROW>
        end
        roots = unique(round(roots,9));
        for i = 1:numel(roots)
            x = roots(i);
            y = ppval(ca.pp,x);
            rows(end+1) = struct( ... %#ok<AGROW>
                'protocol_a',spec{3},'protocol_b',spec{4}, ...
                'Tp_us',x,'M_equivalent',x/conn_slot_us,'throughput',y);
        end
    end
    if ~isempty(rows)
        [~,order] = sort([rows.Tp_us]);
        rows = rows(order);
    end
end

function add_intersection_arrows(fig,ax,rows)
    if isempty(rows), return; end
    old_units = ax.Units;
    ax.Units = 'normalized';
    position = ax.Position;
    ax.Units = old_units;
    x_limits = xlim(ax);
    label_offsets = [-70 80];
    for i = 1:numel(rows)
        target_x = position(1) + ...
            (rows(i).Tp_us-x_limits(1))/diff(x_limits)*position(3);
        label_data_x = rows(i).Tp_us + ...
            label_offsets(mod(i-1,numel(label_offsets))+1);
        label_x = position(1) + ...
            (label_data_x-x_limits(1))/diff(x_limits)*position(3);
        target_y = position(2);
        label_y = max(0.002,position(2)-0.075);
        annotation(fig,'textarrow',[label_x target_x],[label_y target_y], ...
            'String',sprintf('%d',round(rows(i).Tp_us)), ...
            'FontName','Arial','FontSize',13,'Color',[0.15 0.15 0.15], ...
            'LineWidth',1,'HeadLength',6,'HeadWidth',6, ...
            'HorizontalAlignment','center','VerticalAlignment','top');
    end
end

function value = intersection_table_from_rows(rows)
    if isempty(rows)
        value = table('Size',[0 5], ...
            'VariableTypes',{'string','string','double','double','double'}, ...
            'VariableNames',{'protocol_a','protocol_b','Tp_us', ...
                             'M_equivalent','throughput'});
        return;
    end
    value = struct2table(rows);
    value.protocol_a = string(value.protocol_a);
    value.protocol_b = string(value.protocol_b);
end
