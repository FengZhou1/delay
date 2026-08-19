function theory_table = theory_validation(summary_path, output_dir)
%THEORY_VALIDATION 对实验 summary 做理论后处理
%   读取 summary.csv，对每个条件计算理论接入时延和总时延
%   输出 theory_validation.csv

    if nargin < 1 || isempty(summary_path)
        error('需要提供 summary.csv 路径');
    end
    if nargin < 2 || isempty(output_dir)
        output_dir = fileparts(summary_path);
    end

    data = readtable(summary_path, 'VariableNamingRule', 'preserve');
    if isempty(data)
        warning('summary.csv 为空');
        theory_table = table();
        return;
    end

    % 协议固定参数
    C = 162.5;   % conn_slot (us)
    S = 9.0;     % mmWave slot (us)
    D = 34.0;    % DIFS (us)

    % 判断是否有 component 字段
    has_components = all(ismember({'mean_boundary_wait_us','mean_difs_wait_us',...
        'mean_probability_wait_us','mean_busy_nav_wait_us',...
        'mean_collision_delay_us','mean_control_delay_us',...
        'mean_data_delay_us'}, data.Properties.VariableNames));

    n = height(data);
    theory_rows = cell(n, 1);

    for i = 1:n
        row = data(i, :);
        proto = char(row.protocol);
        lam = double(row.lambda_base);
        M = double(row.M);
        q = double(row.best_q);
        ma = double(row.mean_attempts_completed);
        exp_delay = double(row.mean_delay_us);
        exp_queue = double(row.mean_queue_delay_us);
        exp_access = double(row.mean_access_delay_us);
        exp_cond_delay = double(row.conditional_mean_delay_us);
        stable = double(row.stable_fraction);
        comp_ratio = double(row.completion_ratio);

        % 提取实验 component 值（如果存在）
        if has_components
            exp_boundary = safe_val(row.mean_boundary_wait_us);
            exp_difs = safe_val(row.mean_difs_wait_us);
            exp_prob = safe_val(row.mean_probability_wait_us);
            exp_nav = safe_val(row.mean_busy_nav_wait_us);
            exp_collision = safe_val(row.mean_collision_delay_us);
            exp_control = safe_val(row.mean_control_delay_us);
            exp_data = safe_val(row.mean_data_delay_us);
        else
            [exp_boundary, exp_difs, exp_prob, exp_nav, ...
             exp_collision, exp_control, exp_data] = deal(NaN);
        end

        % 理论计算
        [theo_access, details] = compute_theory_access(proto, q, ma, M, C, S, D);

        % 总时延 = 理论接入 + 实验排队
        if isfinite(theo_access) && isfinite(exp_queue)
            theo_total = theo_access + exp_queue;
        else
            theo_total = NaN;
        end

        % 误差
        access_err = exp_access - theo_access;
        total_err = exp_delay - theo_total;
        if isfinite(theo_access) && theo_access > 0
            access_err_pct = 100 * access_err / theo_access;
        else
            access_err_pct = NaN;
        end
        if isfinite(theo_total) && theo_total > 0
            total_err_pct = 100 * total_err / theo_total;
        else
            total_err_pct = NaN;
        end

        % 理论排队时延（用 M/G/1 近似）
        % 对稳定系统，排队时延 = 系统包数/到达率 - 服务时间
        % 但对非 M/M/1 系统，这个关系不一定成立，所以直接用实验值
        theo_queue = exp_queue;  % 使用实验排队时延

        tr = struct();
        tr.protocol = string(proto);
        tr.lambda_base = lam;
        tr.M = M;
        tr.best_q = q;
        tr.stable = stable;
        tr.completion_ratio = comp_ratio;
        tr.K_active = details.K_active;
        tr.Ps = details.Ps;
        tr.E_slots = details.E_slots;
        tr.theory_access_us = theo_access;
        tr.theory_total_delay_us = theo_total;
        tr.exp_access_us = exp_access;
        tr.exp_total_delay_us = exp_delay;
        tr.exp_queue_delay_us = exp_queue;
        tr.access_error_us = access_err;
        tr.total_error_us = total_err;
        tr.access_error_pct = access_err_pct;
        tr.total_error_pct = total_err_pct;

        if has_components
            tr.exp_boundary_wait_us = exp_boundary;
            tr.exp_difs_wait_us = exp_difs;
            tr.exp_probability_wait_us = exp_prob;
            tr.exp_nav_wait_us = exp_nav;
            tr.exp_collision_delay_us = exp_collision;
            tr.exp_control_delay_us = exp_control;
            tr.exp_data_delay_us = exp_data;
        end

        theory_rows{i} = tr;
    end

    theory_table = struct2table(vertcat(theory_rows{:}));
    out_path = fullfile(output_dir, 'theory_validation.csv');
    writetable(theory_table, out_path);
    fprintf('理论验证结果已保存: %s\n', out_path);
end

function [access, details] = compute_theory_access(proto, q, ma, M, C, S, D)
%COMPUTE_THEORY_ACCESS 计算理论接入时延
    details = struct('K_active', NaN, 'Ps', NaN, 'E_slots', NaN);

    if ~isfinite(ma) || ma <= 0 || ~isfinite(q) || q <= 0 || q >= 1
        access = NaN;
        return;
    end

    % 从 mean_attempts 反推 K_active
    % ma = 1/(1-q)^(K-1)  =>  K = 1 - ln(ma)/ln(1-q)
    K = 1 - log(ma) / log(1 - q);
    if ~isfinite(K) || K <= 0
        access = NaN;
        return;
    end

    % Ps = K * q * (1-q)^(K-1)
    Ps = K * q * (1 - q)^(K - 1);
    if Ps <= 0
        access = NaN;
        return;
    end
    E_slots = 1 / Ps;

    details.K_active = K;
    details.Ps = Ps;
    details.E_slots = E_slots;

    switch proto
        case 'sf_cf'
            % 时隙ALOHA: slot=162.5us, 包含数据
            % 接入 = 边界 + E[slot] * slot
            access = C/2 + E_slots * C;

        case 'sf_cb'
            % 预约ALOHA: slot=162.5us, 成功需要RTS/CTS+数据
            % 接入 = 边界 + E[slot]*slot(竞争+RTS) + data
            access = C/2 + E_slots * C + M * C;

        case 'sb_cf'
            % CSMA无RTS: 9us slot, DIFS, 数据
            % 接入 = 4.5 + DIFS + (E[slot]-1)*9 + data
            access = S/2 + D + (E_slots - 1) * S + M * C;

        case 'sb_cb'
            % CSMA有RTS: 9us slot, DIFS, RTS/CTS, 数据
            % 接入 = 4.5 + DIFS + (E[slot]-1)*9 + RTS/CTS + data
            if strcmp(proto, 'sb_cb')
                % 控制开销 = RTS/CTS = 1 conn_slot
                access = S/2 + D + (E_slots - 1) * S + C + M * C;
            else
                access = NaN;
            end

        case 's7_clean'
            % Sub7辅助: 9us slot, sub7 RTS/CTS, 数据
            access = S/2 + D + (E_slots - 1) * S + 83.4 + M * C;

        case 's7_busy'
            access = S/2 + D + (E_slots - 1) * S + 83.4 + M * C;

        case 'unslotted'
            % 纯ALOHA: 连续时间, 指数退避
            % 无法用简单公式计算，返回NaN
            access = NaN;

        otherwise
            access = NaN;
    end
end

function v = safe_val(x)
    if isnumeric(x)
        v = double(x);
    else
        v = NaN;
    end
end
