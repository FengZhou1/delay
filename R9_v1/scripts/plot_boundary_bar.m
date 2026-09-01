function plot_boundary_bar()
% 临时：生成 M=5 稳定边界条形图
    rows = readtable('0819_R9_results/stability_boundary/M5/summary.csv','VariableNamingRule','preserve');
    protocols = {'sf_cb','sb_cb','unslotted','s7_clean','s7_busy','sf_cf','sb_cf'};
    names = containers.Map({'sf_cb','sb_cb','unslotted','s7_clean','s7_busy','sf_cf','sb_cf'}, ...
        {'SF-CB','SB-CB','Unslotted','S7-Clean','S7-Busy','SF-CF','SB-CF'});
    colors = containers.Map({'sf_cb','sb_cb','unslotted','s7_clean','s7_busy','sf_cf','sb_cf'}, ...
        {[0.85 0.33 0.10],[0 0.45 0.74],[0.93 0.69 0.13],[0.47 0.67 0.19],[0.49 0.18 0.56],[0.30 0.75 0.93],[0.64 0.08 0.18]});
    max_lams = zeros(numel(protocols),1);
    for i=1:numel(protocols)
        p = protocols{i};
        sub = rows(string(rows.protocol)==p,:);
        lam = double(sub.lambda_base);
        st = double(sub.stable_fraction) >= 1-1e-12 & double(sub.completion_ratio) >= 0.99;
        if any(st)
            max_lams(i) = max(lam(st));
        else
            max_lams(i) = 0;
        end
    end

    figure('Position',[100 100 950 520],'Visible','off','Color','w');
    b = barh(max_lams,'FaceColor','flat');
    for i=1:numel(protocols)
        b.CData(i,:) = colors(protocols{i});
    end
    set(gca,'YTick',1:numel(protocols),'YTickLabel',cellfun(@(x) names(x),protocols,'UniformOutput',false));
    xlabel('Maximum stable \lambda (pkt/STA/s)');
    title('M=5 Stability Boundary (ready_queue)');
    grid on;
    xlim([0 130]);
    for i=1:numel(protocols)
        text(max_lams(i)+2, i, sprintf('%d', max_lams(i)), 'VerticalAlignment','middle','FontSize',11);
    end
    out = fullfile('0819_R9_results','stability_boundary','M5','figures','stability_boundary_bar_M5.png');
    if ~isfolder(fileparts(out)), mkdir(fileparts(out)); end
    exportgraphics(gcf, out, 'Resolution', 200);
    fprintf('saved: %s\n', out);
    close(gcf);
end
