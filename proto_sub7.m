function [th_mmw, queue_delays, access_delays, miss_prob, mean_qlen] = proto_sub7(arrivals, n_mlo, n_slo, q, proto)
    % Optimized Sub-7G Assisted Protocol (Parallel/Pipelined Transmission)
    % When MLO nodes transmit data on mmWave, Sub-7G channel is open for SLO contention.
    % End-to-end delay split into queueing delay + access delay (MLO only).
   
    n_total = n_mlo + n_slo;
    steps = size(arrivals, 1);
    
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
    
    % Queue: MLO uses infinite FIFO queue (arrival timestamps), SLO single-packet saturated
    queues = cell(n_total, 1);
    has_packet = false(n_total, 1);
    hol_become_time = zeros(n_total, 1); % MLO only: when current HOL became HOL
    
    % Protocol constants
    DIFS_LIMIT = proto.DIFS;
    ICF_LEN = proto.ICF;
    ICR_LEN = proto.ICR;
    SIFS = proto.SIFS;
    DATA_MMW = proto.MLO_DATA_MMW_LEN;
    SLO_RTS_LEN = proto.SLO_RTS_LEN;
    SLO_CTS_LEN = proto.SLO_CTS_LEN;

    SLO_TXOP_LEN = DATA_MMW;

   % Pre-allocate delays
   max_delays = ceil(steps / max(1, DATA_MMW)) * n_mlo;
    queue_delays = zeros(max_delays, 1);
    access_delays = zeros(max_delays, 1);
   d_idx = 0;
    
   success_slots_mlo = 0;
    success_slots_slo = 0;

    qlen_accum = 0;          % MLO 时间平均队列长度累积量 (包*slot)
    
    is_mlo = (1:n_total)' <= n_mlo;
    
    if n_slo > 0
       q_slo = 1 / (2 * n_slo);
    else
       q_slo = 0;
    end
    
    p_tx_array = zeros(n_total, 1);
    p_tx_array(is_mlo) = q;
    p_tx_array(~is_mlo) = q_slo;
    
    for t = 1:steps
        % --- 1. Arrivals ---
        a_idx = find(arrivals(t, :));
        for k = 1:numel(a_idx)
            u = a_idx(k);
            if isempty(queues{u})
                hol_become_time(u) = t;
            end
            queues{u}(end+1) = t;
            has_packet(u) = true;
        end
        % SLO: always saturated (single-packet model, no queue needed)
        no_packet_slo = ~is_mlo & ~has_packet;
        has_packet(no_packet_slo) = true;
        
        % --- 采样当前 slot MLO 队列长度 (到达后状态) ---
        sum_q = 0;
        for u = 1:n_mlo
            sum_q = sum_q + numel(queues{u});
        end
        qlen_accum = qlen_accum + sum_q;
        
        % --- 2. Check Sub-7G busy (Vectorized) ---
        is_sub7_busy = any(state == TX_ICF | state == WAIT_ICR | state == RX_ICR | ...
                   state == TX_RTS_SUB7 | state == WAIT_CTS_SUB7 | state == TX_DATA_SUB7);
        
        % --- 3. NAV countdown (Vectorized) ---
        nav(nav > 0) = nav(nav > 0) - 1;
        
        % --- 4. DIFS counting (Vectorized) ---
        can_count = (state == IDLE) & (nav == 0) & ~is_sub7_busy;
        difs(~can_count) = 0;
        difs(can_count) = difs(can_count) + 1;
        
        % --- 5. New transmissions (Vectorized) ---
        ready = (state == IDLE) & has_packet & (difs > DIFS_LIMIT);
        if any(ready)
            will_tx = ready & (rand(n_total, 1) < p_tx_array);
            
            if any(will_tx)
                tx_idx = find(will_tx);
                n_tx = length(tx_idx);

                mlo_tx = will_tx & is_mlo;
                slo_tx = will_tx & ~is_mlo;
                
                state(mlo_tx) = TX_ICF;
                timer(mlo_tx) = ICF_LEN;
                
                state(slo_tx) = TX_RTS_SUB7;
                timer(slo_tx) = SLO_RTS_LEN;
                
                difs(will_tx) = 0;
                
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
                timer(sifs_done) = ICR_LEN + SIFS;  
                
                for uid = find(sifs_done)'
                    other_mlos = is_mlo;
                    other_mlos(uid) = false;
                    nav(other_mlos) = max(nav(other_mlos), ICR_LEN + SIFS + DATA_MMW);
                    
                    slos = ~is_mlo;
                    nav(slos) = max(nav(slos), ICR_LEN);
                end
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
                    timer(slo_rts_success) = SIFS + SLO_CTS_LEN + SIFS;

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
                success_slots_mlo = success_slots_mlo + sum(mmw_done) * DATA_MMW;

                ids = find(mmw_done);
                for k = 1:length(ids)
                    uid = ids(k);
                    d_idx = d_idx + 1;
                    if d_idx > numel(queue_delays)
                        queue_delays(end+1000) = 0;
                        access_delays(end+1000) = 0;
                    end
                    queue_delays(d_idx) = hol_become_time(uid) - queues{uid}(1);
                    access_delays(d_idx) = t - hol_become_time(uid);
                    queues{uid}(1) = [];
                    if isempty(queues{uid})
                        has_packet(uid) = false;
                    else
                        hol_become_time(uid) = t;
                    end
                end

                state(mmw_done) = IDLE;
            end

            % TX_DATA_SUB7 -> IDLE (SLO Success)
            slo_done = expired & (prev_state == TX_DATA_SUB7);
            if any(slo_done)
            slo_success = slo_done & ~fail;

               success_slots_slo = success_slots_slo + sum(slo_success) * SLO_TXOP_LEN;
                % SLO delay recording intentionally omitted (kept out of MLO results)
                slo_replenish = slo_success & ~is_mlo;
                if any(slo_replenish)
                    has_packet(slo_replenish) = true;
                end
                state(slo_done) = IDLE;
            end
        end
    end

    % Uncompleted MLO packets at sim end (infinite queue, consistent with other protocols)
    for u = 1:n_mlo
        for j = 1:numel(queues{u})
            d_idx = d_idx + 1;
            if d_idx > numel(queue_delays)
                queue_delays(end+1000) = 0;
                access_delays(end+1000) = 0;
            end
            if j == 1
                queue_delays(d_idx) = hol_become_time(u) - queues{u}(j);
            else
                queue_delays(d_idx) = steps - queues{u}(j);
            end
            access_delays(d_idx) = NaN;
        end
    end

    queue_delays = queue_delays(1:d_idx);
    access_delays = access_delays(1:d_idx);

    th_mmw = success_slots_mlo / steps;  
    miss_prob = 0;

    if steps > 0
        mean_qlen = qlen_accum / steps;
    else
        mean_qlen = 0;
    end
end
