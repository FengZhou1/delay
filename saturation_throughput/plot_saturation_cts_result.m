function plot_saturation_cts_result(data,path,run_label)
%PLOT_SATURATION_CTS_RESULT Plot throughput versus TXOP for one CTS mode.

    proto_order = {'sf_cf','sf_cb','sb_cf','sb_cb', ...
        'unslotted','s7_clean','s7_busy'};
    variants = unique(string(data.cts_variant),'stable');
    fig = figure('Visible','off','Color','white','Units','pixels', ...
        'Position',[100 100 1350 620]);
    hold on;
    for vi = 1:numel(variants)
        variant = variants(vi);
        for pi = 1:numel(proto_order)
            protocol = proto_order{pi};
            keep = string(data.protocol) == protocol & ...
                string(data.cts_variant) == variant;
            if ~any(keep), continue; end
            sub = data(keep,:);
            x = double(sub.Tp_us);
            y = double(sub.payload_airtime_fraction_mean);
            [x,order] = sort(x);
            y = y(order);
            color = protocol_color(protocol);
            marker = protocol_marker(protocol);
            line_style = '-';
            if numel(variants) > 1
                if contains(char(variant),'m3dB')
                    line_style = '-';
                else
                    line_style = '--';
                end
            end
            label = display_protocol(protocol);
            if numel(variants) > 1
                label = sprintf('%s (%s)',label,char(variant));
            end
            plot(x,y,'Color',color,'LineStyle',line_style, ...
                'Marker',marker,'LineWidth',1.5,'MarkerSize',5, ...
                'DisplayName',label);
        end
    end
    hold off;
    grid on; box on;
    xlabel('TXOP length T_p (\mus)');
    ylabel('Saturation throughput');
    title(sprintf('%s: saturation throughput vs TXOP',run_label));
    legend('Location','eastoutside','Interpreter','none','FontSize',8);
    drawnow;
    print(fig,path,'-dpng','-r300');
    close(fig);
end

function color = protocol_color(protocol)
    switch protocol
        case 'sf_cf', color = [0.00 0.35 0.75];
        case 'sb_cf', color = [0.30 0.75 0.93];
        case 'sf_cb', color = [0.75 0.05 0.15];
        case 'sb_cb', color = [0.95 0.50 0.10];
        case 'unslotted', color = [0.20 0.60 0.20];
        case 's7_clean', color = [0.60 0.20 0.80];
        case 's7_busy', color = [0.00 0.65 0.65];
        otherwise, color = [0.3 0.3 0.3];
    end
end

function marker = protocol_marker(protocol)
    switch protocol
        case 'sf_cf', marker = 'o';
        case 'sb_cf', marker = 's';
        case 'sf_cb', marker = '^';
        case 'sb_cb', marker = 'd';
        case 'unslotted', marker = 'v';
        case 's7_clean', marker = 'p';
        case 's7_busy', marker = 'h';
        otherwise, marker = 'o';
    end
end

function label = display_protocol(protocol)
    switch protocol
        case 'sf_cf', label = 'SF-CF';
        case 'sf_cb', label = 'SF-CB';
        case 'sb_cf', label = 'SB-CF';
        case 'sb_cb', label = 'SB-CB';
        case 'unslotted', label = 'Unslotted';
        case 's7_clean', label = 'S7-AN(nS=0)';
        case 's7_busy', label = 'S7-AN(nS=10)';
        otherwise, label = protocol;
    end
end
