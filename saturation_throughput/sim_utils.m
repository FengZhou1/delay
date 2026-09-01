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
    % 绾︽潫锛氭瘡涓墖鍖?STA 鏁伴噺鐩稿悓
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
            deg  = low_deg + sector_width * rand();  % 褰撳墠鎵囧尯鍐?AP->STA 鐨勮搴?
            ang  = deg2rad(deg);

            pos(idx, :) = ap_pos + dist * [cos(ang), sin(ang)];
            angles(idx) = deg; % AP -> STA 瑙掑害
            sectors(idx) = s;
            idx = idx + 1;
        end
    end
end

function mat = precalc_interference_mmw(pos, ang, phy)
    % 鐢ㄤ簬璁＄畻 STA 闂村共鎵?渚﹀惉鑳介噺鐭╅樀
    % 鍦烘櫙锛?
    %   Tx (骞叉壈婧?:姝ｅ湪鍚?AP 鍙戦€佹暟鎹紝娉㈡潫瀵瑰噯 AP (鏈夊畾鍚戝彂灏勫鐩?
    %   Rx (琚共鎵拌€?渚﹀惉鑰?: 姝ｅ湪鍏ㄥ悜渚﹀惉淇￠亾 (鎺ユ敹澧炵泭 = 0 dBi)
    %
    % mat(tx, rx): Tx 鍙戦€佹椂锛孯x 澶勬敹鍒扮殑鑳介噺 (Watts)

    n = size(pos,1); 
    mat = zeros(n,n);

    % 1. 璁＄畻鎵€鏈?STA 鎸囧悜 AP 鐨勫彂灏勮搴?
    % 杈撳叆鐨?ang 鏄?AP->STA 鐨勮搴︼紝鎵€浠?STA->AP 闇€瑕?+180 搴?
    ang_sta_to_ap = mod(ang + 180, 360);

    for tx = 1:n
        % Tx 鐞嗘兂鐨勬尝鏉熸柟鍚?(瀵瑰噯 AP)
        tx_aiming_dir = ang_sta_to_ap(tx);

        for rx = 1:n
            if tx == rx, continue; end
            
            d = norm(pos(rx,:) - pos(tx,:));
            
            % 2. 浠?Tx 鎸囧悜 Rx 鐨勭墿鐞嗚搴?(骞叉壈娉勯湶鏂瑰悜)
            dir_tx_to_rx = atan2d(pos(rx,2)-pos(tx,2), pos(rx,1)-pos(tx,1));
            
            % 3. 鍙戦€佸鐩?(Tx Gain)
            % Tx 涓荤摚瀵瑰噯 AP锛孯x 鍦?dir_tx_to_rx 鏂瑰悜锛岃绠楀洜涓哄亸绂讳富鐡ｅ鑷寸殑琛板噺/鏃佺摚澧炵泭
            g_tx = calculate_ula_mrt_gain(dir_tx_to_rx, tx_aiming_dir, phy.Nt, phy.FREQ);
            
            % 4. 鎺ユ敹澧炵泭 (Rx Gain) - 鍏ㄥ悜鐩戝惉
            g_rx = 0; % Omni-directional
            
            % 5. 璺緞鎹熻€?
            pl = 20*log10(d) + 20*log10(phy.FREQ/1e9) + 32.44;
            
            % 璁＄畻鎺ユ敹淇″彿寮哄害 (RSSI)
            p_rx_dbm = phy.TX_POWER_DBM + g_tx + g_rx - pl;
            mat(tx,rx) = 10^((p_rx_dbm - 30)/10); % 杞崲涓虹嚎鎬у姛鐜?(Watts)
        end
    end
end

function mat = precalc_ap_rx_power_mmw(pos, phy)
    % 鐢ㄤ簬璁＄畻 AP 鎺ユ敹淇″彿璐ㄩ噺 (鐢ㄤ簬 SINR/纰版挒鍒ゆ柇)
    % 鍦烘櫙:
    %   AP: 鎺ユ敹鏂癸紝娉㈡潫瀵瑰噯鏈熸湜鐨?STA (desired_sta)
    %   Tx: 鍙戦€佹柟锛屾尝鏉熷鍑?AP
    
    n = size(pos, 1);
    mat = zeros(n, n);
    
    % AP 浣嶇疆鍥哄畾锛岃绠?AP->STA 璺濈鍜岃搴?
    d_ap = zeros(n, 1);
    ang_ap_to_sta = zeros(n, 1); % AP 鐪嬪悜 STA 鐨勬柟鍚?
    ang_sta_to_ap = zeros(n, 1); % STA 鐪嬪悜 AP 鐨勬柟鍚?(鍙戝皠鏂瑰悜)
    
    for i = 1:n
        d_ap(i) = norm(pos(i, :) - phy.AP_POS);
        ang_temp = atan2d(pos(i,2) - phy.AP_POS(2), pos(i,1) - phy.AP_POS(1));
        ang_ap_to_sta(i) = mod(ang_temp, 360);
        ang_sta_to_ap(i) = mod(ang_temp + 180, 360);
    end
    
    for desired_sta = 1:n
        % AP 姝ゆ椂灏嗘帴鏀舵尝鏉熷鍑?desired_sta
        ap_look_dir = ang_ap_to_sta(desired_sta);

        for tx_sta = 1:n
            % 淇″彿瀹為檯鏉ユ簮鏂瑰悜 (Tx STA 鎵€鍦ㄧ殑鏂逛綅)
            arrival_dir = ang_ap_to_sta(tx_sta);
            
            % AP 鎺ユ敹澧炵泭: AP 鎸囧悜 desired_sta, 浣嗕俊鍙锋潵鑷?tx_sta
            g_ap_rx = calculate_ula_mrt_gain(arrival_dir, ap_look_dir, phy.Nt, phy.FREQ);
            
            % STA 鍙戦€佸鐩? STA 鎬绘槸瀵瑰噯 AP 鍙戦€?(鏈€澶у鐩?
            % 鍥犱负 Tx STA 鎸囧悜 AP锛孉P 灏卞湪鍏朵富鐡ｈ酱绾夸笂
            g_sta_tx = 10*log10(phy.Nt); 
            
            % 璺緞鎹熻€?
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
    % AP 鎵囧尯鎵弿涓嬭鍙戝皠鍔熺巼鐭╅樀
    % mat(sta, sector): AP 娉㈡潫鎸囧悜 sector 鏃讹紝sta 鎺ユ敹鐨勫姛鐜?(Watts)

    n = size(pos, 1);
    mat = zeros(n, n_sectors);

    if ~isfield(phy, 'AP_POS')
        error('precalc_ap_sector_tx_power_mmw:MissingField', 'phy.AP_POS 缂哄け');
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
            g_sta_rx = 0; % STA 鐩戝惉/鎺ユ敹鎸夊叏鍚戝鐞?
            pl = 20*log10(max(d_ap(sta), 1e-3)) + 20*log10(phy.FREQ/1e9) + 32.44;
            pwr_dbm = phy.TX_POWER_DBM + g_ap_tx + g_sta_rx - pl;
            mat(sta, s) = 10^((pwr_dbm - 30)/10);
        end
    end
end
