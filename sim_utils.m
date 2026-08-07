% filepath: d:\Dian\802.11bq\channel access simulation5\sim_utils.m
function utils = sim_utils()
    utils.generate_topology = @generate_topology;
    utils.precalc_interference_mmw = @precalc_interference_mmw;
    utils.precalc_ap_rx_power_mmw = @precalc_ap_rx_power_mmw; 
    utils.precalc_ap_sector_tx_power_mmw = @precalc_ap_sector_tx_power_mmw;
    utils.calculate_ula_mrt_gain = @calculate_ula_mrt_gain;
    utils.get_common_params = @get_common_params;
end

function [pos, angles, sectors] = generate_topology(n, ap_pos, n_sectors)
    % 约束：每个扇区 STA 数量相同
    if mod(n, n_sectors) ~= 0
        error('generate_topology: n must be divisible by n_sectors for equal-per-sector deployment.');
    end

    per_sector = n / n_sectors;
    pos = zeros(n, 2);
    angles = zeros(n, 1);
    sectors = zeros(n, 1);

    sector_width = 360 / n_sectors;
    idx = 1;

    for s = 1:n_sectors
        low_deg = (s - 1) * sector_width;

        for k = 1:per_sector
            dist = 1 + 9 * rand();                   % [1,10] m
            deg  = low_deg + sector_width * rand();  % 当前扇区内 AP->STA 的角度
            ang  = deg2rad(deg);

            pos(idx, :) = ap_pos + dist * [cos(ang), sin(ang)];
            angles(idx) = deg; % AP -> STA 角度
            sectors(idx) = s;
            idx = idx + 1;
        end
    end
end

function mat = precalc_interference_mmw(pos, ang, phy)
    % 用于计算 STA 间干扰/侦听能量矩阵
    % 场景：
    %   Tx (干扰源):正在向 AP 发送数据，波束对准 AP (有定向发射增益)
    %   Rx (被干扰者/侦听者): 正在全向侦听信道 (接收增益 = 0 dBi)
    %
    % mat(tx, rx): Tx 发送时，Rx 处收到的能量 (Watts)

    n = size(pos,1); 
    mat = zeros(n,n);

    % 1. 计算所有 STA 指向 AP 的发射角度
    % 输入的 ang 是 AP->STA 的角度，所以 STA->AP 需要 +180 度
    ang_sta_to_ap = mod(ang + 180, 360);

    for tx = 1:n
        % Tx 理想的波束方向 (对准 AP)
        tx_aiming_dir = ang_sta_to_ap(tx);

        for rx = 1:n
            if tx == rx, continue; end
            
            d = norm(pos(rx,:) - pos(tx,:));
            
            % 2. 从 Tx 指向 Rx 的物理角度 (干扰泄露方向)
            dir_tx_to_rx = atan2d(pos(rx,2)-pos(tx,2), pos(rx,1)-pos(tx,1));
            
            % 3. 发送增益 (Tx Gain)
            % Tx 主瓣对准 AP，Rx 在 dir_tx_to_rx 方向，计算因为偏离主瓣导致的衰减/旁瓣增益
            g_tx = calculate_ula_mrt_gain(dir_tx_to_rx, tx_aiming_dir, phy.Nt, phy.FREQ);
            
            % 4. 接收增益 (Rx Gain) - 全向监听
            g_rx = 0; % Omni-directional
            
            % 5. 路径损耗
            pl = 20*log10(d) + 20*log10(phy.FREQ/1e9) + 32.44;
            
            % 计算接收信号强度 (RSSI)
            p_rx_dbm = phy.TX_POWER_DBM + g_tx + g_rx - pl;
            mat(tx,rx) = 10^((p_rx_dbm - 30)/10); % 转换为线性功率 (Watts)
        end
    end
end

function mat = precalc_ap_rx_power_mmw(pos, phy)
    % 用于计算 AP 接收信号质量 (用于 SINR/碰撞判断)
    % 场景:
    %   AP: 接收方，波束对准期望的 STA (desired_sta)
    %   Tx: 发送方，波束对准 AP
    
    n = size(pos, 1);
    mat = zeros(n, n);
    
    % AP 位置固定，计算 AP->STA 距离和角度
    d_ap = zeros(n, 1);
    ang_ap_to_sta = zeros(n, 1); % AP 看向 STA 的方向
    ang_sta_to_ap = zeros(n, 1); % STA 看向 AP 的方向 (发射方向)
    
    for i = 1:n
        d_ap(i) = norm(pos(i, :) - phy.AP_POS);
        ang_temp = atan2d(pos(i,2) - phy.AP_POS(2), pos(i,1) - phy.AP_POS(1));
        ang_ap_to_sta(i) = mod(ang_temp, 360);
        ang_sta_to_ap(i) = mod(ang_temp + 180, 360);
    end
    
    for desired_sta = 1:n
        % AP 此时将接收波束对准 desired_sta
        ap_look_dir = ang_ap_to_sta(desired_sta);

        for tx_sta = 1:n
            % 信号实际来源方向 (Tx STA 所在的方位)
            arrival_dir = ang_ap_to_sta(tx_sta);
            
            % AP 接收增益: AP 指向 desired_sta, 但信号来自 tx_sta
            g_ap_rx = calculate_ula_mrt_gain(arrival_dir, ap_look_dir, phy.Nt, phy.FREQ);
            
            % STA 发送增益: STA 总是对准 AP 发送 (最大增益)
            % 因为 Tx STA 指向 AP，AP 就在其主瓣轴线上
            g_sta_tx = 10*log10(phy.Nt); 
            
            % 路径损耗
            pl = 20*log10(d_ap(tx_sta)) + 20*log10(phy.FREQ/1e9) + 32.44;
            
            pwr_dbm = phy.TX_POWER_DBM + g_sta_tx - pl + g_ap_rx; 
            mat(desired_sta, tx_sta) = 10^((pwr_dbm - 30) / 10);
        end
    end
end

function gain = calculate_ula_mrt_gain(target, desired, N, freq)
    lambda = 3e8/freq; d = lambda/2; k = 2*pi/lambda;
    pos = ((0:N-1)-(N-1)/2)*d;
    w = conj(exp(1j*k*pos*sin(deg2rad(desired))))/sqrt(N);
    a = exp(1j*k*pos*sin(deg2rad(target)));
    af = abs(w*a.'); 
    gain = 20*log10(af+1e-10);
    if abs(target-desired) < 0.1, gain = 10*log10(N); end
end

function[SYS, PHY_MMW, MMW, SUB7, SIM] = get_common_params(cfg)
    if nargin < 1
        cfg = struct();
    end
    timing = mmw_timing_config(cfg);
    SYS.N_SECTORS = timing.N_SECTORS;
    
    PHY_MMW.FREQ         = 60e9;        
    PHY_MMW.TX_POWER_DBM = 10;          
    PHY_MMW.RX_SENS_DBM  = -62;         
    PHY_MMW.Nt           = 4;          
    PHY_MMW.AP_POS       = [0, 0];      
    
    MMW.SLOT_TIME_US = timing.SLOT_US;
    MMW.R_D_BPS = timing.DATA_RATE_BPS;
    MMW.R_B_BPS = timing.CONTROL_RATE_BPS;
    MMW.PHY_HEADER = timing.PHY_HEADER_SLOTS;
    MMW.RTS_BITS = timing.RTS_BITS;
    MMW.CTS_BITS = timing.CTS_BITS;
    MMW.N_RTS = timing.RTS_SLOTS;
    MMW.N_CTS = timing.CTS_SLOTS;
    MMW.SIFS = timing.SIFS_SLOTS;
    MMW.DIFS = timing.DIFS_SLOTS;
    MMW.conn_overhead = timing.CONN_SLOT_SLOTS;
    
    SUB7.SLOT_TIME_US = 9;
    % Real-time (non slot-aligned) Sub-7 timing, matching the mmWave
    % SB-CB access procedure (RTS/DIFS boundary aligned, omni sensing
    % without hidden nodes).
    SUB7.SIFS_US = 16;
    SUB7.DIFS_US = 34;
    SUB7.RTS_US  = 26.7;
    SUB7.CTS_US  = 24.7;
    SUB7.CTS_TIMEOUT_US = SUB7.SIFS_US + SUB7.CTS_US;   % 40.7 us
    SUB7.SLO_TXOP_LEN = 500;
    SUB7.SLO_DATA_LEN = SUB7.SLO_TXOP_LEN;
    SUB7.N_SLO_CLEAN = 0;
    SUB7.N_SLO_BUSY  = 10;

    SIM.TIME_TOTAL_US = 2000000;
    SIM.STEPS_MMW  = round(SIM.TIME_TOTAL_US / MMW.SLOT_TIME_US);
    SIM.STEPS_SUB7 = round(SIM.TIME_TOTAL_US / SUB7.SLOT_TIME_US);

    SIM.SATURATION_LOAD = 2.0;
    SIM.Q_RANGE = [0.001:0.002:0.02, 0.025:0.01:0.15, 0.2:0.2:1.0];
    SIM.UNIT_SLOTS = MMW.conn_overhead;
end

function mat = precalc_ap_sector_tx_power_mmw(pos, phy, n_sectors)
    % AP 扇区扫描下行发射功率矩阵
    % mat(sta, sector): AP 波束指向 sector 时，sta 接收的功率 (Watts)

    n = size(pos, 1);
    mat = zeros(n, n_sectors);

    if ~isfield(phy, 'AP_POS')
        error('precalc_ap_sector_tx_power_mmw:MissingField', 'phy.AP_POS 缺失');
    end

    sector_width = 360 / n_sectors;
    sector_centers = (0:n_sectors-1) * sector_width + sector_width/2;

    d_ap = zeros(n, 1);
    ang_ap_to_sta = zeros(n, 1);
    for i = 1:n
        d_ap(i) = norm(pos(i, :) - phy.AP_POS);
        ang_ap_to_sta(i) = mod(atan2d(pos(i,2)-phy.AP_POS(2), pos(i,1)-phy.AP_POS(1)), 360);
    end

    for s = 1:n_sectors
        ap_aim_dir = sector_centers(s);
        for sta = 1:n
            g_ap_tx = calculate_ula_mrt_gain(ang_ap_to_sta(sta), ap_aim_dir, phy.Nt, phy.FREQ);
            g_sta_rx = 0; % STA 监听/接收按全向处理
            pl = 20*log10(max(d_ap(sta), 1e-3)) + 20*log10(phy.FREQ/1e9) + 32.44;
            pwr_dbm = phy.TX_POWER_DBM + g_ap_tx + g_sta_rx - pl;
            mat(sta, s) = 10^((pwr_dbm - 30)/10);
        end
    end
end
