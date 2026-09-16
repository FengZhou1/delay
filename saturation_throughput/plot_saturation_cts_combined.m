function out = plot_saturation_cts_combined(result_root, out_dir)
%PLOT_SATURATION_CTS_COMBINED One overall saturation figure across CTS modes.
%   Collects the saturation summaries of result1, result2, result4 and the
%   result5 variants (result3 only if it still exists) under RESULT_ROOT and
%   writes two figures into OUT_DIR (default <result_root>/combined):
%
%     combined_by_mode.png     - one panel per CTS mode, curves = protocols
%                                (the CB curves of that mode plus the reference
%                                 rows copied from result1)
%     combined_by_protocol.png - one panel per CB protocol, curves = CTS modes
%
%   Per-mode panels use whichever protocols the summary contains, so a mode 5
%   run that only re-simulated the CB protocols still shows SF-CF / SB-CF /
%   S7-AN through its reference rows.
%
%   plot_saturation_cts_combined(result_root)
%   plot_saturation_cts_combined(result_root, out_dir)

    if nargin < 1 || isempty(result_root)
        result_root = fileparts(mfilename('fullpath'));
    end
    if nargin < 2 || isempty(out_dir)
        out_dir = fullfile(result_root,'combined');
    end
    if ~isfolder(out_dir), mkdir(out_dir); end

    variants = collect_variants(result_root);
    if isempty(variants)
        error('plot_saturation_cts_combined:NoData', ...
            'No saturation_summary.csv was found under %s.',result_root);
    end

    proto_order = {'sf_cf','sf_cb','sb_cf','sb_cb','s7_clean','s7_busy'};
    proto_names  = {'SF-CF','SF-CB','SB-CF','SB-CB','S7-AN ($n_S=0$)','S7-AN ($n_S=10$)'};
    proto_styles = protocol_styles();

    % ---------- figure 1: one panel per CTS mode ----------
    n = numel(variants);
    ncol = min(3,n); nrow = ceil(n/ncol);
    fig1 = figure('Visible','off','Color','white','Units','inches', ...
        'Position',[1 1 5.2*ncol 3.6*nrow]);
    cleanup1 = onCleanup(@() close(fig1));
    legend_handles = gobjects(0); legend_names = {};
    ax_first = [];
    for v = 1:n
        ax = subplot(nrow,ncol,v,'Parent',fig1);
        if v == 1, ax_first = ax; end
        data = readtable(variants(v).path,'VariableNamingRule','preserve');
        y_col = throughput_column(data);
        hold(ax,'on');
        for i = 1:numel(proto_order)
            keep = string(data.protocol) == string(proto_order{i});
            if ~any(keep), continue; end
            [x,y] = clean_xy(double(data.Tp_us(keep)),double(data.(y_col)(keep)));
            if isempty(x), continue; end
            st = proto_styles.(proto_order{i});
            plot(ax,x,y,'Color',st.color,'LineStyle',st.line_style, ...
                'LineWidth',2.0,'Marker',st.marker,'MarkerSize',5, ...
                'MarkerFaceColor','white','MarkerEdgeColor',st.color);
            if v == 1
                legend_handles(end+1,1) = plot(ax,NaN,NaN,'Color',st.color, ...
                    'LineStyle',st.line_style,'LineWidth',2.0, ...
                    'Marker',st.marker,'MarkerSize',5, ...
                    'MarkerFaceColor','white','MarkerEdgeColor',st.color); %#ok<AGROW>
                legend_names{end+1,1} = proto_names{i}; %#ok<AGROW>
            end
        end
        hold(ax,'off');
        style_axis(ax);
        title(ax,variants(v).label,'Interpreter','latex', ...
            'FontName','Times New Roman','FontSize',12);
        if v == 1
            xlabel(ax,'$T_p$ ($\mu$s)','Interpreter','latex', ...
                'FontName','Times New Roman','FontSize',12);
            ylabel(ax,'Maximum Throughput','Interpreter','latex', ...
                'FontName','Times New Roman','FontSize',12);
        end
    end
    if ~isempty(legend_handles)
        lg = legend(ax_first,legend_handles,legend_names,'Interpreter','latex', ...
            'FontName','Times New Roman','FontSize',8,'Box','on', ...
            'Orientation','horizontal');
        lg.Position = [0.35 0.01 0.30 0.04];
        lg.ItemTokenSize = [18 6];
    end
    png1 = fullfile(out_dir,'combined_by_mode.png');
    pdf1 = fullfile(out_dir,'combined_by_mode.pdf');
    exportgraphics(fig1,png1,'Resolution',200);
    exportgraphics(fig1,pdf1,'ContentType','vector');

    % ---------- figure 2: one panel per CB protocol ----------
    proto2 = {'sf_cb','sb_cb'};
    fig2 = figure('Visible','off','Color','white','Units','inches', ...
        'Position',[1 1 11 4.2]);
    cleanup2 = onCleanup(@() close(fig2));
    lg2_handles = gobjects(0); lg2_names = {};
    ax2_first = [];
    colors = lines(numel(variants));
    for k = 1:numel(proto2)
        ax = subplot(1,2,k,'Parent',fig2);
        if k == 1, ax2_first = ax; end
        hold(ax,'on');
        for v = 1:n
            data = readtable(variants(v).path,'VariableNamingRule','preserve');
            y_col = throughput_column(data);
            keep = string(data.protocol) == string(proto2{k});
            if ~any(keep), continue; end
            [x,y] = clean_xy(double(data.Tp_us(keep)),double(data.(y_col)(keep)));
            if isempty(x), continue; end
            plot(ax,x,y,'Color',colors(v,:),'LineWidth',2.0, ...
                'Marker','o','MarkerSize',5,'MarkerFaceColor','white', ...
                'MarkerEdgeColor',colors(v,:));
            if k == 1
                lg2_handles(end+1,1) = plot(ax,NaN,NaN,'Color',colors(v,:), ...
                    'LineWidth',2.0,'Marker','o','MarkerSize',5, ...
                    'MarkerFaceColor','white','MarkerEdgeColor',colors(v,:)); %#ok<AGROW>
                lg2_names{end+1,1} = variants(v).label; %#ok<AGROW>
            end
        end
        hold(ax,'off');
        style_axis(ax);
        title(ax,upper(strrep(proto2{k},'_','-')),'Interpreter','none', ...
            'FontName','Times New Roman','FontSize',13);
        xlabel(ax,'$T_p$ ($\mu$s)','Interpreter','latex', ...
            'FontName','Times New Roman','FontSize',12);
        ylabel(ax,'Maximum Throughput','Interpreter','latex', ...
            'FontName','Times New Roman','FontSize',12);
    end
    if ~isempty(lg2_handles)
        legend(ax2_first,lg2_handles,lg2_names,'Interpreter','none', ...
            'FontName','Times New Roman','FontSize',9,'Box','on', ...
            'Location','southeast');
    end
    png2 = fullfile(out_dir,'combined_by_protocol.png');
    pdf2 = fullfile(out_dir,'combined_by_protocol.pdf');
    exportgraphics(fig2,png2,'Resolution',200);
    exportgraphics(fig2,pdf2,'ContentType','vector');

    out = struct('by_mode_png',png1,'by_mode_pdf',pdf1, ...
                 'by_protocol_png',png2,'by_protocol_pdf',pdf2, ...
                 'variants',{ {variants.label} });
    fprintf('Combined figures written to %s\n',out_dir);
end

function variants = collect_variants(root)
    specs = {'result1','Mode 1: 8-sector sweep'; ...
             'result2','Mode 2: ideal quasi-omni'; ...
             'result3','Mode 3: physical QO (legacy)'; ...
             'result4','Mode 4: directional winner'};
    variants = struct('key',{},'label',{},'path',{});
    for i = 1:size(specs,1)
        p = fullfile(root,specs{i,1},'saturation_summary.csv');
        if isfile(p)
            variants(end+1) = struct('key',specs{i,1},'label',specs{i,2},'path',p); %#ok<AGROW>
        end
    end
    d = dir(fullfile(root,'result5','*','saturation_summary.csv'));
    for i = 1:numel(d)
        folder = d(i).folder;
        [~,tag] = fileparts(folder);
        tok = regexp(tag,'qo_iso_(-?[0-9.]+)dB','tokens','once');
        if isempty(tok)
            label = sprintf('Mode 5: %s',tag);
        else
            label = sprintf('Mode 5: quasi-omni %s dB',tok{1});
        end
        variants(end+1) = struct('key',tag,'label',label,'path',d(i).fullfile); %#ok<AGROW>
    end
end

function col = throughput_column(data)
    if ismember('effective_payload_fraction_mean',data.Properties.VariableNames)
        col = 'effective_payload_fraction_mean';
    else
        col = 'payload_airtime_fraction_mean';
    end
end

function [x,y] = clean_xy(x,y)
    keep = isfinite(x) & isfinite(y);
    x = x(keep); y = y(keep);
    [x,order] = sort(x); y = y(order);
    [x,idx] = unique(x,'stable'); y = y(idx);
end

function style_axis(ax)
    ax.FontName = 'Times New Roman';
    ax.FontSize = 11;
    ax.LineWidth = 1.0;
    ax.TickDir = 'in';
    ax.Layer = 'top';
    box(ax,'on');
    grid(ax,'off');
    xlim(ax,[0 3300]);
    ylim(ax,[0 1]);
    xticks(ax,0:500:3000);
end

function styles = protocol_styles()
    styles.sf_cf = struct('color',[0.00 0.35 0.75],'line_style','-','marker','o');
    styles.sf_cb = struct('color',[0.75 0.05 0.15],'line_style','-','marker','^');
    styles.sb_cf = struct('color',[0.30 0.75 0.93],'line_style','--','marker','s');
    styles.sb_cb = struct('color',[0.95 0.50 0.10],'line_style','--','marker','d');
    styles.s7_clean = struct('color',[0.60 0.20 0.80],'line_style','-.','marker','p');
    styles.s7_busy  = struct('color',[0.00 0.65 0.65],'line_style','-.','marker','h');
end