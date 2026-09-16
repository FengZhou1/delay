function plot_R10_cts_result(data,pkt_us,path,run_label)
%PLOT_R10_CTS_RESULT Plot one combined mean-delay result.

    % Only the protocols kept by run_R10_cts_mode are plotted.
    proto_order = {'sf_cf','sf_cb','sb_cf','sb_cb', ...
        's7_clean','s7_busy'};
    fig = figure('Visible','off','Color','white','Units','pixels', ...
        'Position',[100 100 1350 620]);
    hold on;
    for i = 1:numel(proto_order)
        protocol = proto_order{i};
        keep_p = string(data.protocol) == protocol;
        if ~any(keep_p), continue; end
        Ms = unique(double(data.M(keep_p)));
        for j = 1:numel(Ms)
            M = Ms(j);
            sub = data(keep_p & abs(double(data.M)-M) < 1e-9,:);
            if isempty(sub), continue; end
            x = double(sub.total_load);
            y = double(sub.mean_delay_us);
            stable = double(sub.stable_fraction) >= 1-1e-12 & ...
                double(sub.completion_ratio) >= 0.99 & isfinite(y);
            [x,order] = sort(x);
            y = y(order);
            stable = stable(order);
            color = protocol_color(protocol);
            marker = protocol_marker(protocol);
            line_style = '--';
            if abs(M-1) < 1e-9, line_style = '-'; end
            if any(stable)
                plot(x(stable),y(stable),'Color',color, ...
                    'LineStyle',line_style,'Marker',marker, ...
                    'LineWidth',1.6,'MarkerSize',5, ...
                    'MarkerFaceColor',color, ...
                    'DisplayName',display_protocol(protocol,M));
            end
            if any(~stable)
                plot(x(~stable),y(~stable),'Color',color, ...
                    'LineStyle','none','Marker',marker, ...
                    'MarkerSize',5,'MarkerFaceColor','none', ...
                    'HandleVisibility','off');
            end
        end
    end
    hold off;
    grid on; box on;
    xlabel('Total offered load');
    ylabel('Mean end-to-end delay (\mus)');
    title(sprintf('%s: delay vs load, packet=%g us',run_label,pkt_us));
    set(gca,'YScale','log');
    xlim([0 0.85]);
    legend('Location','eastoutside','Interpreter','none','FontSize',9);
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

function label = display_protocol(protocol,M)
    switch protocol
        case 'sf_cf', base = 'SF-CF';
        case 'sf_cb', base = 'SF-CB';
        case 'sb_cf', base = 'SB-CF';
        case 'sb_cb', base = 'SB-CB';
        case 'unslotted', base = 'Unslotted';
        case 's7_clean', base = 'S7-AN(nS=0)';
        case 's7_busy', base = 'S7-AN(nS=10)';
        otherwise, base = protocol;
    end
    label = sprintf('%s(M=%g)',base,M);
end
