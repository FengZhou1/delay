function run_protocol_sweeps(proto_name, func_factory, is_sub7, q_range)
% RUN_PROTOCOL_SWEEPS 协议仿真 M 扫描主流程（纯吞吐量，饱和模式）
%
% 输入:
%   proto_name:   协议名称字符串
%   func_factory: 函数句柄工厂，返回 opt_func = @(steps, q) [th, miss_prob]
%   is_sub7:      是否为 Sub-7GHz 协议
%   q_range:      发送概率扫描范围

    % 1. 加载参数
    utils = sim_utils();
    [SYS_BASE, PHY_BASE, MMW_BASE, SUB7_BASE, SIM] = utils.get_common_params();
    if nargin < 4 || isempty(q_range), q_range = SIM.Q_RANGE; end

    % 2. 场景配置 (固定拓扑)
    STA_PER_SECTOR = 5;
    FIXED_N = SYS_BASE.N_SECTORS * STA_PER_SECTOR; % 总站数 = 8 * 5 = 40

    M_VALUES = [1/10, 1/5, 2/5, 3/5, 1, 2, 3, 4, 5, 6, 8, 10, 15, 20];

    TOPOLOGY_SEED = 20260325;

    fprintf('\n=== Running Protocol: %s ===\n', proto_name);
    if ~exist('results', 'dir'), mkdir('results'); end
    fprintf('--- Sweep M (Fixed N=%d, %d STA/sector, Saturation) ---\n', FIXED_N, STA_PER_SECTOR);

    % 3. 结果容器初始化
    res_M.th = zeros(length(M_VALUES), 1);
    res_M.miss = zeros(length(M_VALUES), 1);
    res_M.best_q = zeros(length(M_VALUES), 1);

    % 4. 生成统一拓扑
    SYS = SYS_BASE; SYS.N_MLO = FIXED_N;
    rng(TOPOLOGY_SEED, 'twister');
    [node_pos, angles, sectors] = utils.generate_topology(SYS.N_MLO, PHY_BASE.AP_POS, SYS.N_SECTORS);

    % 预计算物理层参数矩阵
    PHY = PHY_BASE;
    PHY.Int_Matrix = utils.precalc_interference_mmw(node_pos, angles, PHY);
    PHY.AP_Rx_Matrix = utils.precalc_ap_rx_power_mmw(node_pos, PHY);
    PHY.AP_Sector_Tx_Matrix = utils.precalc_ap_sector_tx_power_mmw(node_pos, PHY, SYS.N_SECTORS);

    % 5. 扫描循环 (Sweep M)
    for i = 1:length(M_VALUES)
        current_M = M_VALUES(i);

        % 根据 M 计算 N_DATA
        MMW = MMW_BASE;
        MMW.M_BATCH = current_M;
        MMW.N_DATA  = entry_check(current_M * SIM.UNIT_SLOTS);
        MMW.CONN_SLOT = MMW_BASE.conn_overhead;

        SUB7 = SUB7_BASE;
        if is_sub7
            SUB7.MLO_DATA_MMW_LEN = ceil(MMW.N_DATA * MMW_BASE.SLOT_TIME_US / SUB7_BASE.SLOT_TIME_US);
        end

        opt_func = func_factory(SYS, MMW, SUB7, PHY, sectors, SYS.N_SECTORS);

        % 饱和吞吐量优化
        [best_th, best_q, best_miss] = optimize_q(opt_func, SIM.STEPS_MMW, SIM.STEPS_SUB7, is_sub7, q_range);

        res_M.th(i) = best_th;
        res_M.miss(i) = best_miss;
        res_M.best_q(i) = best_q;

        fprintf('  M=%-4.2f: TH=%.7f, q=%.8f, Miss=%.4f\n', current_M, best_th, best_q, best_miss);
    end

    % 6. 保存数据
    save(['results/res_M_' proto_name '.mat'], 'res_M', 'M_VALUES');
end

% ---------------- 辅助函数 ----------------

function v = entry_check(v)
    if v < 1, v = 1; else, v = round(v); end
end

function [best_th, best_q, best_miss] = optimize_q(opt_func, steps_mmw, steps_sub7, is_sub7, q_range)
    best_th = -inf; best_q = q_range(1); best_miss = 0;

    steps = steps_mmw;
    if is_sub7, steps = steps_sub7; end

    for q = q_range
        [th, mp] = opt_func(steps, q);
        if th > best_th
            best_th = th; best_q = q; best_miss = mp;
        end
    end

    if ~isfinite(best_th), best_th = 0; best_q = 0; best_miss = 0; end
end
