function [arrivals, p_arr_mmw, p_arr_sub7] = arrival_rate(lambda, sim_time_total_us, n_nodes, band)
%ARRIVAL_RATE 由 λ(pkt/sta/s) 换算 mmWave 与 sub7G 各自 minislot 的
%   pkt/sta/minislot 到达概率，并在对应 minislot 绝对时隙做伯努利到达。
%
%   [arrivals, p_arr_mmw, p_arr_sub7] = ARRIVAL_RATE(lambda, sim_time_total_us, n_nodes, band)
%
%   说明:
%     λ 单位为 pkt/sta/s（每节点每秒到达包数）。
%     毫米波 minislot = MMW.SLOT_TIME_US = 5 us   -> p_arr_mmw  = λ * 5e-6
%     sub7G  minislot = SUB7.SLOT_TIME_US = 9 us  -> p_arr_sub7 = λ * 9e-6
%     本函数对指定 band 的 minislot 网格逐时隙做伯努利到达判断：
%       arrivals(t,u)=true 表示节点 u 在第 t 个 minislot 有包到达。
%     各协议调用本函数拿到 arrivals 后，在自己时隙开始时判断队列中是否有包。
%
%   输入:
%     lambda            - 每节点每秒到达率 (pkt/sta/s)，默认 5
%     sim_time_total_us - 仿真总时长 (us)，默认 1e7
%     n_nodes           - 节点数，默认 40
%     band              - 'mmw'(毫米波) 或 'sub7'(sub7G)，默认 'mmw'
%
%   输出:
%     arrivals   - [steps x n_nodes] logical 到达矩阵（按 band 的 minislot 网格）
%     p_arr_mmw  - 毫米波每 minislot 每节点到达概率
%     p_arr_sub7 - sub7G  每 minislot 每节点到达概率

    if nargin < 1 || isempty(lambda),            lambda = 5;       end
    if nargin < 2 || isempty(sim_time_total_us), sim_time_total_us = 1e7; end
    if nargin < 3 || isempty(n_nodes),           n_nodes = 40;     end
    if nargin < 4 || isempty(band),              band = 'mmw';     end

    utils = sim_utils();
    [~, ~, MMW, SUB7, ~] = utils.get_common_params();

    % 两条 band 的 minislot 到达概率（λ -> pkt/sta/minislot）
    p_arr_mmw  = lambda * MMW.SLOT_TIME_US  * 1e-6;
    p_arr_sub7 = lambda * SUB7.SLOT_TIME_US * 1e-6;

    % 选取目标 band 的 minislot 网格（绝对时隙）
    if strcmpi(band, 'sub7')
        slot_us = SUB7.SLOT_TIME_US;
        p_arr   = p_arr_sub7;
    else
        slot_us = MMW.SLOT_TIME_US;
        p_arr   = p_arr_mmw;
    end

    steps = round(sim_time_total_us / slot_us);
    arrivals = false(steps, n_nodes);

    % 分块生成以控制峰值内存（避免一次性 rand(steps,n_nodes) 的大临时矩阵）
    CHUNK = 2e5;   % 每块 20 万行
    for s = 1:CHUNK:steps
        e = min(s + CHUNK - 1, steps);
        arrivals(s:e, :) = rand(e - s + 1, n_nodes) < p_arr;
    end
end
