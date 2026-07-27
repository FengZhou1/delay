function [th_mmw, delays, miss_prob, th_sub7] = proto_sub7(steps, n_mlo, n_slo, p_arr, q, proto)
    % Optimized Sub-7G Assisted Protocol (Parallel/Pipelined Transmission)
    % 当 MLO 节点在毫米波上发送数据时，Sub-7G 信道对 SLO 节点开放竞争
    
    n_total = n_mlo + n_slo;
    is_saturation = (p_arr >= 1);
    
    % States
    IDLE = 0;
    TX_ICF = 1; WAIT_ICR = 2; RX_ICR = 3; TX_DATA_MMW = 4;
    TX_RTS_SUB7 = 5; WAIT_CTS_SUB7 = 6; TX_DATA_SUB7 = 7;
    
    % State vectors
    state = zeros(n_total, 1);
    timer = zeros(n_total, 1);
    nav   = zeros(n_total, 1);
    difs  = zeros(n_total, 1);
    fail  = false(n_total, 1);
    
    % Queue: MLO 使用无限队列（与其他协议一致）, SLO 使用单包饱和模型
    queues = cell(n_total, 1);        % 每个节点的包到达时间队列 (MLO only)
    has_packet = false(n_total, 1);   % MLO: 队列非空; SLO: 始终有包
    hol_arrival = zeros(n_total, 1);  % 仅 SLO 使用
    
    % Protocol constants
    DIFS_LIMIT = proto.DIFS;
    ICF_LEN = proto.ICF;
    ICR_LEN = proto.ICR;
    SIFS = proto.SIFS;
    DATA_MMW = proto.MLO_DATA_MMW_LEN;
    SLO_RTS_LEN = proto.SLO_RTS_LEN;
    SLO_CTS_LEN = proto.SLO_CTS_LEN;

    % 将 SLO 的 TXOP 设置为与 MLO 相同的绝对时间
    % MLO_DATA_MMW_LEN 已经是按 Sub-7G 时隙换算好的绝对时间长度
    SLO_TXOP_LEN = DATA_MMW;

    % Pre-allocate delays
    max_delays = ceil(steps / max(1, DATA_MMW)) * n_mlo;
    delays = zeros(max_delays, 1);
    d_idx = 0;
    
    % 吞吐量统计（分别统计 MLO 和 SLO）
    success_slots_mlo = 0; % 用于统计 MLO 节点的成功时隙
    success_slots_slo = 0; % 用于统计 SLO 节点的成功时隙
    
    % Pre-compute MLO mask
    is_mlo = (1:n_total)' <= n_mlo;
    
    % ========================================================
    % 【修改点】：分离 MLD(MLO) 和 SLD(SLO) 的发送概率
    % ========================================================
    if n_slo > 0
       q_slo = 1 / (2 * n_slo);
        %q_slo = 0.4;
    else
        q_slo = 0; % 防止 n_slo 为 0 时除零报错
    end
    
    % 构建异构概率数组，避免在循环内重复判断，提高运行效率
    p_tx_array = zeros(n_total, 1);
    p_tx_array(is_mlo) = q;         % MLD 按照原概率参数 q 扫描竞争
    p_tx_array(~is_mlo) = q_slo;    % SLD 固定采用 q_slo
    % ========================================================
    
    for t = 1:steps
        % --- 1. Arrivals ---
        % MLD: 无限队列（与其他协议一致）
        if is_saturation
            for u = 1:n_mlo
                if isempty(queues{u})
                    queues{u}(end+1) = t;
                end
            end
            has_packet(1:n_mlo) = true;
        else
            arrivals_mlo = is_mlo & (rand(n_total, 1) < p_arr);
            a_idx = find(arrivals_mlo);
            for k = 1:numel(a_idx)
                u = a_idx(k);
                queues{u}(end+1) = t;
                has_packet(u) = true;
            end
        end
        % SLD: always saturated (single-packet model, no queue needed)
        no_packet_slo = ~is_mlo & ~has_packet;
        if any(no_packet_slo)
            has_packet(no_packet_slo) = true;
            hol_arrival(no_packet_slo) = t;
        end
        
        % --- 2. Check Sub-7G busy (Vectorized) ---
        % 注意：这里没有包含 TX_DATA_MMW，意味着毫米波发数据时，Sub-7G 物理上是空闲的
        is_sub7_busy = any(state == TX_ICF | state == WAIT_ICR | state == RX_ICR | ...
                   state == TX_RTS_SUB7 | state == WAIT_CTS_SUB7 | state == TX_DATA_SUB7);
        
        % --- 3. NAV countdown (Vectorized) ---
        nav(nav > 0) = nav(nav > 0) - 1;
        
        % --- 4. DIFS counting (Vectorized) ---
        % 竞争条件：物理信道空闲 & NAV为0
        can_count = (state == IDLE) & (nav == 0) & ~is_sub7_busy;
        difs(~can_count) = 0;
        difs(can_count) = difs(can_count) + 1;
        
        % --- 5. New transmissions (Vectorized) ---
        ready = (state == IDLE) & has_packet & (difs > DIFS_LIMIT);
        if any(ready)
            % 【修改点】：使用提前算好的异构概率数组 p_tx_array 代替单一的 q
            will_tx = ready & (rand(n_total, 1) < p_tx_array);
            
            if any(will_tx)
                tx_idx = find(will_tx);
                n_tx = length(tx_idx);

                % MLO nodes send ICF, SLO nodes send RTS for reservation
                mlo_tx = will_tx & is_mlo;
                slo_tx = will_tx & ~is_mlo;
                
                state(mlo_tx) = TX_ICF;
                timer(mlo_tx) = ICF_LEN;
                
                state(slo_tx) = TX_RTS_SUB7;
                timer(slo_tx) = SLO_RTS_LEN;
                
                difs(will_tx) = 0;
                
                % Collision detection
                if n_tx > 1
                    fail(will_tx) = true;
                else
                    fail(will_tx) = false;
                end
            end
        end
        
        % --- 6. Timer update and state transitions ---
        active_mask = (state ~= IDLE);
        prev_state = state;
        timer(active_mask) = timer(active_mask) - 1;
        expired = active_mask & (timer == 0);
        
        if any(expired)
            % TX_ICF -> WAIT_ICR or IDLE
            icf_done = expired & (prev_state == TX_ICF);
            if any(icf_done)
                icf_fail = icf_done & fail;
                icf_success = icf_done & ~fail;
                
                state(icf_fail) = IDLE;
                state(icf_success) = WAIT_ICR;
                timer(icf_success) = SIFS;  
            end
            
            % WAIT_ICR -> RX_ICR
            sifs_done = expired & (prev_state == WAIT_ICR);
            if any(sifs_done)
                state(sifs_done) = RX_ICR;
                % 【修正】：增加 ICR 接收完毕后到 DATA 发送前的第二个 SIFS
                timer(sifs_done) = ICR_LEN + SIFS;  
                
                % ========================================================
                % 分离 MLO 和 SLO 的 NAV 设定
                % ========================================================
                for uid = find(sifs_done)'
                    % 1. 对于其他 MLO 节点：NAV 锁定到毫米波数据传完
                    % 因为当前毫米波发射机被占用，其他 MLO 不能再发起竞争
                    other_mlos = is_mlo;
                    other_mlos(uid) = false;
                    nav(other_mlos) = max(nav(other_mlos), ICR_LEN + SIFS + DATA_MMW);
                    
                    % 2. 对于 SLO 节点：NAV 只需要避开当前的 ICR 控制帧
                    % ICR 发送完毕后，SLO 节点可以立刻在 Sub-7G 上开始 DIFS 倒数并发送数据！
                    slos = ~is_mlo;
                    nav(slos) = max(nav(slos), ICR_LEN);
                end
                % ========================================================
            end
            
            % RX_ICR -> TX_DATA_MMW
            icr_done = expired & (prev_state == RX_ICR);
            if any(icr_done)
                state(icr_done) = TX_DATA_MMW;
                timer(icr_done) = DATA_MMW;
            end

            % TX_RTS_SUB7 -> WAIT_CTS_SUB7 / IDLE
            slo_rts_done = expired & (prev_state == TX_RTS_SUB7);
            if any(slo_rts_done)
                slo_rts_fail = slo_rts_done & fail;
                slo_rts_success = slo_rts_done & ~fail;

                state(slo_rts_fail) = IDLE;

                if any(slo_rts_success)
                    state(slo_rts_success) = WAIT_CTS_SUB7;
                    % 【修复】：增加 CTS 发送完毕后，到 DATA 发送前的第二个 SIFS
                    timer(slo_rts_success) = SIFS + SLO_CTS_LEN + SIFS;

                    % RTS/CTS 预约后，对其他节点设置 NAV 覆盖 CTS + 2*SIFS + TXOP
                    nav_lock = SIFS + SLO_CTS_LEN + SIFS + SLO_TXOP_LEN;
                    for uid = find(slo_rts_success)'
                        others = true(n_total, 1);
                        others(uid) = false;
                        nav(others) = max(nav(others), nav_lock);
                    end
                end
            end

            % WAIT_CTS_SUB7 -> TX_DATA_SUB7 (TXOP)
            slo_cts_done = expired & (prev_state == WAIT_CTS_SUB7);
            if any(slo_cts_done)
                state(slo_cts_done) = TX_DATA_SUB7;
                timer(slo_cts_done) = SLO_TXOP_LEN;
                fail(slo_cts_done) = false;
            end
            
            % TX_DATA_MMW -> IDLE (MLO Success)
            mmw_done = expired & (prev_state == TX_DATA_MMW);
            if any(mmw_done)
                % 累加毫米波的成功时间
                success_slots_mlo = success_slots_mlo + sum(mmw_done) * DATA_MMW;

                ids = find(mmw_done);
                for k = 1:length(ids)
                    uid = ids(k);
                    d_idx = d_idx + 1;
                    if d_idx > numel(delays), delays(end+1000) = 0; end
                    % 排队时延：发送开始时刻 - 到达时刻（队头出队）
                    delays(d_idx) = t - (ICF_LEN + SIFS + ICR_LEN + SIFS + DATA_MMW) + 1 - queues{uid}(1);
                    queues{uid}(1) = [];
                    if isempty(queues{uid})
                        has_packet(uid) = false;
                    end
                end

                state(mmw_done) = IDLE;
            end

            % TX_DATA_SUB7 -> IDLE (SLO Success)
            slo_done = expired & (prev_state == TX_DATA_SUB7);
            if any(slo_done)
                slo_success = slo_done & ~fail;

                % 累加 SLO 在 Sub-7G 上的成功 TXOP 时间
                success_slots_slo = success_slots_slo + sum(slo_success) * SLO_TXOP_LEN;
                
                % ==========================================
                % 【修改点 1】：注释掉 SLO 节点的时延记录，使其不混入 MLO 的结果中
                % ==========================================
                % ids = find(slo_success);
                % for k = 1:length(ids)
                %     uid = ids(k);
                %     if d_idx < max_delays
                %         d_idx = d_idx + 1;
                %         if d_idx > numel(delays), delays(end+1000) = 0; end
                %         delays(d_idx) = t - (SLO_RTS_LEN + SIFS + SLO_CTS_LEN + SIFS + SLO_TXOP_LEN) - hol_arrival(uid);
                %     end
                % end
                % ==========================================
                
                if is_saturation
                    no_packet_mlo = slo_success & is_mlo;
                    if any(no_packet_mlo)
                        has_packet(no_packet_mlo) = true;
                        hol_arrival(no_packet_mlo) = t;
                    end
                end
                % (non-saturation: MLO has_packet 由队列状态决定，不做额外处理)
                % SLD always saturated: immediately replenish
                slo_replenish = slo_success & ~is_mlo;
                if any(slo_replenish)
                    has_packet(slo_replenish) = true;
                    hol_arrival(slo_replenish) = t;
                end
                state(slo_done) = IDLE;
            end
        end
    end

    % 将最终未发出的包也统计其剩余排队时间（无限队列，与其他协议一致）
    for u = 1:n_mlo
        for j = 1:numel(queues{u})
            d_idx = d_idx + 1;
            if d_idx > numel(delays), delays(end+1000) = 0; end
            delays(d_idx) = steps - queues{u}(j);
        end
    end

    delays = delays(1:d_idx);

    % 输出分别的吞吐量
    th_mmw = success_slots_mlo / steps;  
    th_sub7 = success_slots_slo / steps; 
    miss_prob = 0;
end