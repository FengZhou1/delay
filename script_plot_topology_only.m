% filepath: d:\Dian\802.11bq\channel access simulation5\script_plot_topology_only.m
function script_plot_topology_only()
    clc; close all;

    utils = sim_utils();
    [SYS, PHY, ~, ~, ~] = utils.get_common_params();

    STA_PER_SECTOR = 5;
    N_STA = SYS.N_SECTORS * STA_PER_SECTOR;   % 40
    TOPOLOGY_SEED = 20260325;                 % 与 run_protocol_sweeps 一致

    rng(TOPOLOGY_SEED, 'twister');
    [pos, ~, sectors] = utils.generate_topology(N_STA, PHY.AP_POS, SYS.N_SECTORS);

    figure('Color', 'w', 'Name', 'AP-STA Topology');
    hold on; axis equal; grid on;

    % AP
    plot(PHY.AP_POS(1), PHY.AP_POS(2), 'kp', 'MarkerSize', 14, ...
        'MarkerFaceColor', 'y', 'DisplayName', 'AP');

    % STA (按扇区着色)
    cmap = lines(SYS.N_SECTORS);
    for s = 1:SYS.N_SECTORS
        idx = (sectors == s);
        scatter(pos(idx,1), pos(idx,2), 36, cmap(s,:), 'filled', ...
            'DisplayName', sprintf('Sector %d', s));
    end

    % 画扇区边界线
    r_max = max(sqrt(sum((pos - PHY.AP_POS).^2, 2))) * 1.15;
    for s = 0:SYS.N_SECTORS-1
        th = deg2rad(s * 360 / SYS.N_SECTORS);
        x2 = PHY.AP_POS(1) + r_max * cos(th);
        y2 = PHY.AP_POS(2) + r_max * sin(th);
        plot([PHY.AP_POS(1), x2], [PHY.AP_POS(2), y2], 'k--', 'LineWidth', 0.8, ...
            'HandleVisibility', 'off');
    end

    xlabel('x (m)');
    ylabel('y (m)');
    title(sprintf('Topology Only | N=%d (%d STA/sector), Seed=%d', ...
        N_STA, STA_PER_SECTOR, TOPOLOGY_SEED));
    legend('Location', 'eastoutside');

    % 在命令行打印关键信息
    fprintf('AP position: [%.3f, %.3f]\n', PHY.AP_POS(1), PHY.AP_POS(2));
    fprintf('Total STA: %d\n', N_STA);
    for s = 1:SYS.N_SECTORS
        fprintf('  Sector %d: %d STA\n', s, sum(sectors==s));
    end

    % 可选保存
    if ~exist('results', 'dir'), mkdir('results'); end
    saveas(gcf, fullfile('results', 'topology_only.png'));
end