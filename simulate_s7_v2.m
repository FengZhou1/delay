function result = simulate_s7_v2(protocol, trace, scenario, cfg, M, q, seed)
%SIMULATE_S7_V2 Ideal omnidirectional Sub-7 assisted access model.
% The Sub-7 control channel uses 9-us contention boundaries.  MLO arrivals
% remain on the common mmWave physical trace, and mmWave/SLO payloads last
% exactly M connection slots without rounding.

    if strcmp(protocol, 's7_clean')
        n_slo = 0;
    elseif strcmp(protocol, 's7_busy')
        n_slo = 10;
    else
        error('simulate_s7_v2:BadProtocol', 'Expected s7_clean or s7_busy.');
    end
    is_saturation = isfield(cfg,'traffic_mode') && ...
        strcmpi(char(cfg.traffic_mode),'saturation');
    batch_requests = is_batch_txop_mode(cfg) && ~is_saturation;
    if ~isscalar(M) || ~isfinite(M) || M <= 0 || ...
            (~is_saturation && (M < 1 || M ~= round(M)))
        error('simulate_s7_v2:BadM', ...
            'M must be an integer >=1 for delay or positive for saturation.');
    end

    n_mlo = cfg.n_nodes;
    n_total = n_mlo + n_slo;
    conn_slot_us = double(scenario.MMW_REAL.CONN_OVERHEAD_US);
    if is_saturation
        tp_us = double(scenario.MMW_REAL.CONN_OVERHEAD_US) * M;
    else
        tp_us = double(scenario.MMW_REAL.CONN_OVERHEAD_US) * M;
    end
    slot_us = double(scenario.SUB7.SLOT_TIME_US);
    sifs_us = double(scenario.SUB7.SIFS_US);
    difs_us = double(scenario.SUB7.DIFS_US);
    req_us = double(scenario.SUB7.RTS_US);
    cts_us = double(scenario.SUB7.CTS_US);
    % Successful handshake: RTS + SIFS + CTS + SIFS.
    resp_wait_us = sifs_us + cts_us + sifs_us;
    % Collision retry: wait the CTS timeout (SIFS + CTS), matching SB-CB.
    cts_timeout_us = sifs_us + cts_us;

    IDLE = uint8(0); TX_REQ = uint8(1); WAIT_RESP = uint8(2);
    WAIT_TIMEOUT = uint8(3); TX_DATA_MMW = uint8(4); TX_DATA_SLO = uint8(5);
    state = repmat(IDLE, n_total, 1);
    deadline = inf(n_total, 1);
    nav_until = zeros(n_total, 1);
    difs_elapsed = zeros(n_total, 1);
    sense_start = nan(n_total, 1);
    can_count_prev = false(n_total, 1);
    request_is_mlo = false(n_total, 1);

    stream = RandStream('mt19937ar', 'Seed', double(seed));
    node_packets = trace.packet_ids_by_node;
    arrived_tail = zeros(n_total, 1);
    head_pos = ones(n_total, 1);
    batch_fill = zeros(n_total, 1);
    request_count = zeros(n_total, 1);
    backlog = 0;

    n_pkt = trace.n_packets;
    pkt = struct();
    pkt.node_id = double(trace.node_id(:));
    pkt.arrival_us = double(trace.times_us(:));
    pkt.hol_us = nan(n_pkt, 1);
    pkt.first_attempt_us = nan(n_pkt, 1);
    pkt.completion_us = nan(n_pkt, 1);
    pkt.attempts = zeros(n_pkt, 1);
    pkt.difs_wait_us = zeros(n_pkt, 1);
    pkt.probability_wait_us = zeros(n_pkt, 1);

    diag = struct();
    diag.mlo_request_attempts = 0;
    diag.slo_request_attempts = 0;
    diag.request_rounds = 0;
    diag.request_collision_rounds = 0;
    diag.request_success_mlo = 0;
    diag.request_success_slo = 0;
    diag.mlo_collision_timeouts = 0;
    diag.slo_collision_timeouts = 0;
    diag.mlo_payload_success = 0;
    diag.slo_payload_success = 0;
    diag.slo_payload_success_measure = 0;
    diag.slo_payload_overlap_us = 0;
    diag.collision_waste_us = 0;
    diag.collision_channel_time_us = 0;
    diag.collision_tx_airtime_us = 0;
    diag.collision_channel_time_measure_us = 0;
    diag.collision_tx_airtime_measure_us = 0;
    diag.Tp_us = tp_us;
    diag.txop_mode = txop_mode(cfg);
    diag.batch_requests = batch_requests;

    system_area = 0;
    service_area = 0;
    payload_overlap = 0;
    saturation_per_node_completions = zeros(n_mlo,1);
    sample_t = zeros(ceil(cfg.measure_us/max(1,cfg.stats_sample_us))+4,1);
    sample_n = zeros(size(sample_t));
    sample_idx = 0;

    event_idx = 1;
    next_tick = 0;
    next_sample = cfg.warmup_us;
    reserved_until = 0;
    req_n_to_send_stored = ones(n_total, 1);  % stored at request, used at completion
    last_t = 0;
    t = 0;

    while true
        next_arrival = inf;
        if event_idx <= n_pkt
            next_arrival = trace.times_us(event_idx);
        end
        next_deadline = min(deadline);
        arrival_boundary = inf;
        if t < trace.arrival_end_us
            arrival_boundary = trace.arrival_end_us;
        end
        hard_boundary = inf;
        if t < trace.hard_end_us
            hard_boundary = trace.hard_end_us;
        end
        candidates = [next_arrival, next_tick, next_deadline, next_sample, ...
                      arrival_boundary, hard_boundary];
        candidates = candidates(candidates >= t - 1e-9);
        t_next = min(candidates);
        if ~isfinite(t_next)
            t_next = trace.hard_end_us;
        end
        if t_next < t - 1e-9
            error('simulate_s7_v2:TimeReversal', 'Event calendar moved backwards.');
        end

        dt_measure = interval_overlap_us(last_t, t_next, ...
                                         cfg.warmup_us, cfg.arrival_end_us);
        active_payload = sum(state(1:n_mlo) == TX_DATA_MMW);
        system_area = system_area + backlog * dt_measure;
        service_area = service_area + active_payload * dt_measure;
        last_t = t_next;
        t = t_next;

        % Arrivals precede all protocol decisions at the same timestamp.
        while event_idx <= n_pkt && trace.times_us(event_idx) == t
            u = trace.node_id(event_idx);
            was_empty = head_pos(u) > arrived_tail(u);
            arrived_tail(u) = arrived_tail(u) + 1;
            pid = node_packets{u}(arrived_tail(u));
            if was_empty
                pkt.hol_us(pid) = t;
                difs_elapsed(u) = 0;
                can_count_prev(u) = false;
                if ~batch_requests
                    sense_start(u) = t;
                end
            end
            if batch_requests && u <= n_mlo
                batch_fill(u) = batch_fill(u) + 1;
                if batch_fill(u) >= M
                    batch_fill(u) = 0;
                    request_count(u) = request_count(u) + 1;
                    if request_count(u) == 1
                        sense_start(u) = t;
                        difs_elapsed(u) = 0;
                        can_count_prev(u) = false;
                    end
                end
            end
            backlog = backlog + 1;
            event_idx = event_idx + 1;
        end

        % Complete state intervals ending at t.
        ending = find(deadline == t);
        if ~isempty(ending)
            ending_state = state(ending);
            req_done = ending(ending_state == TX_REQ);
            if ~isempty(req_done)
                diag.request_rounds = diag.request_rounds + 1;
                if numel(req_done) == 1
                    w = req_done(1);
                    state(w) = WAIT_RESP;
                    deadline(w) = t + resp_wait_us;
                    response_end = deadline(w);
                    reserved_until = max(reserved_until, response_end);
                    if request_is_mlo(w)
                        diag.request_success_mlo = diag.request_success_mlo + 1;
                        qd_w = arrived_tail(w) - head_pos(w) + 1;
                        req_n_to_send_w = max(1, min(qd_w, M));
                        data_end = response_end + req_n_to_send_w * conn_slot_us;
                        other_mlo = (1:n_mlo)' ~= w;
                        nav_until(1:n_mlo) = max(nav_until(1:n_mlo), ...
                                                data_end * double(other_mlo));
                        if n_slo > 0
                            nav_until(n_mlo+1:end) = max( ...
                                nav_until(n_mlo+1:end), response_end);
                        end
                    else
                        diag.request_success_slo = diag.request_success_slo + 1;
                        qd_w = arrived_tail(w) - head_pos(w) + 1;
                        req_n_to_send_w = max(1, min(qd_w, M));
                        data_end = response_end + req_n_to_send_w * conn_slot_us;
                        others = true(n_total,1); others(w) = false;
                        nav_until(others) = max(nav_until(others), data_end);
                        reserved_until = max(reserved_until, data_end);
                    end
                else
                    diag.request_collision_rounds = diag.request_collision_rounds + 1;
                    diag.collision_waste_us = diag.collision_waste_us + ...
                                               numel(req_done) * req_us;
                    diag.collision_channel_time_us = ...
                        diag.collision_channel_time_us + req_us;
                    diag.collision_tx_airtime_us = ...
                        diag.collision_tx_airtime_us + numel(req_done)*req_us;
                    collision_measure=interval_overlap_us(t-req_us,t, ...
                        cfg.warmup_us,cfg.arrival_end_us);
                    diag.collision_channel_time_measure_us = ...
                        diag.collision_channel_time_measure_us + collision_measure;
                    diag.collision_tx_airtime_measure_us = ...
                        diag.collision_tx_airtime_measure_us + ...
                        numel(req_done)*collision_measure;
                    for k = 1:numel(req_done)
                        u = req_done(k);
                        state(u) = WAIT_TIMEOUT;
                        deadline(u) = t + cts_timeout_us;
                        if request_is_mlo(u)
                            diag.mlo_collision_timeouts = diag.mlo_collision_timeouts + 1;
                        else
                            diag.slo_collision_timeouts = diag.slo_collision_timeouts + 1;
                        end
                    end
                end
            end

            response_done = ending(ending_state == WAIT_RESP);
            for k = 1:numel(response_done)
                u = response_done(k);
                if request_is_mlo(u)
                    state(u) = TX_DATA_MMW;
                else
                    state(u) = TX_DATA_SLO;
                    qd_uu = arrived_tail(u) - head_pos(u) + 1;
                    n_uu = max(1, min(qd_uu, M));
                    reserved_until = max(reserved_until, t + n_uu * conn_slot_us);
                end
                if is_saturation
                    n_u = M;
                else
                    qd_u = arrived_tail(u) - head_pos(u) + 1;
                    n_u = max(1, min(qd_u, M));
                end
                deadline(u) = t + n_u * conn_slot_us;
                req_n_to_send_stored(u) = n_u;
            end

            timeout_done = ending(ending_state == WAIT_TIMEOUT);
            if ~isempty(timeout_done)
                state(timeout_done) = IDLE;
                deadline(timeout_done) = inf;
                difs_elapsed(timeout_done) = 0;
                sense_start(timeout_done) = t;
                can_count_prev(timeout_done) = false;
            end

            n_to_send = 1;  % default (used by SLO block if no MLO)
            mlo_done = ending(ending_state == TX_DATA_MMW);
            for k = 1:numel(mlo_done)
                u = mlo_done(k);
                pid = node_packets{u}(head_pos(u));
                diag.mlo_payload_success = diag.mlo_payload_success + 1;
                n_to_send = req_n_to_send_stored(u);
                payload_overlap = payload_overlap + interval_overlap_us( ...
                    t - n_to_send * conn_slot_us, t, cfg.warmup_us, cfg.arrival_end_us);
                if is_saturation
                    for pp = 1:n_to_send
                        if t >= cfg.warmup_us && t < cfg.arrival_end_us
                            saturation_per_node_completions(u) = ...
                                saturation_per_node_completions(u) + 1;
                        end
                    end
                    pkt.hol_us(pid) = max(t, pkt.arrival_us(pid));
                    pkt.first_attempt_us(pid) = NaN;
                    pkt.completion_us(pid) = NaN;
                    pkt.attempts(pid) = 0;
                    pkt.difs_wait_us(pid) = 0;
                    pkt.probability_wait_us(pid) = 0;
                else
                    for pp = 1:n_to_send
                        if head_pos(u) <= arrived_tail(u)
                            cpid = node_packets{u}(head_pos(u));
                            pkt.completion_us(cpid) = t - n_to_send * conn_slot_us + pp * conn_slot_us;
                            pkt.data_delay_us(cpid) = conn_slot_us;
                            if pp == 1
                                pkt.control_delay_us(cpid) = req_us + resp_wait_us;
                            else
                                pkt.hol_us(cpid) = t - n_to_send * conn_slot_us + (pp-1) * conn_slot_us;
                            end
                            head_pos(u) = head_pos(u) + 1;
                            backlog = backlog - 1;
                            if head_pos(u) <= arrived_tail(u)
                                npid = node_packets{u}(head_pos(u));
                                pkt.hol_us(npid) = max(t, pkt.arrival_us(npid));
                            end
                        end
                    end
                end
                if ~is_saturation && batch_requests && u <= n_mlo
                    request_count(u) = max(0, request_count(u) - 1);
                end
                state(u) = IDLE;
                deadline(u) = inf;
                difs_elapsed(u) = 0;
                sense_start(u) = t;
                can_count_prev(u) = false;
                if ~is_saturation && head_pos(u) <= arrived_tail(u)
                    next_pid = node_packets{u}(head_pos(u));
                    pkt.hol_us(next_pid) = max(t, pkt.arrival_us(next_pid));
                end
            end

            slo_done = ending(ending_state == TX_DATA_SLO);
            if ~isempty(slo_done)
                diag.slo_payload_success = diag.slo_payload_success + numel(slo_done);
                slo_overlap = interval_overlap_us(t - n_to_send * conn_slot_us,t, ...
                    cfg.warmup_us,cfg.arrival_end_us);
                diag.slo_payload_overlap_us = ...
                    diag.slo_payload_overlap_us + numel(slo_done)*slo_overlap;
                if t >= cfg.warmup_us && t < cfg.arrival_end_us
                    diag.slo_payload_success_measure = ...
                        diag.slo_payload_success_measure + numel(slo_done);
                end
                state(slo_done) = IDLE;
                deadline(slo_done) = inf;
                difs_elapsed(slo_done) = 0;
                sense_start(slo_done) = t;
                can_count_prev(slo_done) = false;
            end
        end

        if t == next_sample
            sample_idx = sample_idx + 1;
            if sample_idx > numel(sample_t)
                sample_t(end+1000,1) = 0;
                sample_n(end+1000,1) = 0;
            end
            sample_t(sample_idx) = t;
            sample_n(sample_idx) = backlog;
            next_sample = next_sample + cfg.stats_sample_us;
            if next_sample >= cfg.arrival_end_us
                next_sample = inf;
            end
        end

        if t == next_tick
            % Credit only complete idle Sub-7 minislots after a HOL exists.
            difs_elapsed(can_count_prev) = difs_elapsed(can_count_prev) + slot_us;
            difs_elapsed(~can_count_prev) = 0;
            % Nodes that could not count (busy / NAV) restart DIFS from now.
            if any(~can_count_prev)
                sense_start(~can_count_prev) = t;
            end

            has_mlo = false(n_mlo,1);
            for u = 1:n_mlo
                has_mlo(u) = has_mlo_contention(u);
            end
            has_packet = [has_mlo; true(n_slo,1)];
            % DIFS is boundary-aligned (matching mmWave SB-CB):
            % align_up(sense_start + SIFS) + 2 slots.
            difs_ok = nan(n_total,1);
            idle_ready = state == IDLE & has_packet & nav_until <= t & ...
                         reserved_until <= t & isfinite(sense_start);
            if any(idle_ready)
                difs_ok(idle_ready) = ...
                    ceil((sense_start(idle_ready) + sifs_us) / slot_us) * slot_us ...
                    + 2 * slot_us;
            end
            ready = idle_ready & t >= difs_ok;
            if any(ready)
                p = q * ones(n_total,1);
                if n_slo > 0
                    p(n_mlo+1:end) = 1/(2*n_slo);
                end
                will_tx = ready & rand(stream,n_total,1) < p;
                deferred_mlo = find(ready(1:n_mlo) & ~will_tx(1:n_mlo));
                for kk = 1:numel(deferred_mlo)
                    u = deferred_mlo(kk);
                    pid = node_packets{u}(head_pos(u));
                    pkt.probability_wait_us(pid) = ...
                        pkt.probability_wait_us(pid) + slot_us;
                end
                tx_ids = find(will_tx);
                if ~isempty(tx_ids)
                    request_is_mlo(tx_ids) = tx_ids <= n_mlo;
                    state(tx_ids) = TX_REQ;
                    deadline(tx_ids) = t + req_us;
                    difs_elapsed(tx_ids) = 0;
                    can_count_prev(tx_ids) = false;
                    reserved_until = max(reserved_until, t + req_us);
                    diag.mlo_request_attempts = diag.mlo_request_attempts + ...
                                                sum(tx_ids <= n_mlo);
                    diag.slo_request_attempts = diag.slo_request_attempts + ...
                                                sum(tx_ids > n_mlo);
                    for kk = 1:numel(tx_ids)
                        u = tx_ids(kk);
                        if u <= n_mlo
                            pid = node_packets{u}(head_pos(u));
                            pkt.attempts(pid) = pkt.attempts(pid) + 1;
                            if ~isfinite(pkt.first_attempt_us(pid))
                                pkt.first_attempt_us(pid) = t;
                            end
                            pkt.difs_wait_us(pid) = pkt.difs_wait_us(pid) + difs_us;
                        end
                    end
                end
            end

            has_mlo = false(n_mlo,1);
            for u = 1:n_mlo
                has_mlo(u) = has_mlo_contention(u);
            end
            has_packet = [has_mlo; true(n_slo,1)];
            can_count_prev = state == IDLE & has_packet & nav_until <= t & ...
                             reserved_until <= t;
            next_tick = next_tick + slot_us;
        end

        if t >= trace.arrival_end_us && backlog == 0
            break;
        end
        if t >= trace.hard_end_us
            break;
        end
    end

    raw = struct();
    completed_mask = isfinite(pkt.completion_us);
    pkt.boundary_wait_us = mod(slot_us - mod(pkt.hol_us,slot_us),slot_us);
    pkt.boundary_wait_us(~isfinite(pkt.hol_us)) = 0;
    pkt.collision_delay_us = zeros(n_pkt,1);
    pkt.collision_delay_us(completed_mask) = ...
        max(0,pkt.attempts(completed_mask)-1) * (req_us+resp_wait_us);
    pkt.control_delay_us(completed_mask) = 0;
    has_attempts = completed_mask & pkt.attempts > 0;
    pkt.control_delay_us(has_attempts) = req_us + resp_wait_us;
    pkt.data_delay_us = zeros(n_pkt,1);
    pkt.data_delay_us(completed_mask) = conn_slot_us;
    component_sum = pkt.boundary_wait_us + pkt.difs_wait_us + ...
        pkt.probability_wait_us + pkt.collision_delay_us + ...
        pkt.control_delay_us + pkt.data_delay_us;
    pkt.busy_nav_wait_us = zeros(n_pkt,1);
    pkt.busy_nav_wait_us(completed_mask) = ...
        pkt.completion_us(completed_mask)-pkt.hol_us(completed_mask)- ...
        component_sum(completed_mask);
    pkt.other_access_delay_us = zeros(n_pkt,1);
    raw.packet_log = pkt;
    structural_censored = false(n_pkt, 1);
    if ~is_saturation && batch_requests
        for u = 1:n_mlo
            if batch_fill(u) > 0
                first = arrived_tail(u) - batch_fill(u) + 1;
                ids = node_packets{u}(first:arrived_tail(u));
                structural_censored(ids) = true;
            end
        end
    end
    raw.structural_censored = structural_censored;
    diag.structural_censored = sum(structural_censored);
    raw.final_backlog = backlog;
    raw.sim_end_us = t;
    raw.system_area_measure_us = system_area;
    raw.service_area_measure_us = service_area;
    raw.payload_success_overlap_us = payload_overlap;
    raw.backlog_sample_us = sample_t(1:sample_idx);
    raw.backlog_sample_n = sample_n(1:sample_idx);
    raw.diagnostics = diag;
    if is_saturation
        raw.saturation_per_node_completions = ...
            saturation_per_node_completions;
        result = finalize_saturation_result(raw,cfg,protocol,M,q);
    else
        result = finalize_sim_result(raw, trace, cfg, protocol, M, q);
    end

    function flag = has_mlo_contention(u)
        if batch_requests
            flag = request_count(u) > 0;
        else
            flag = head_pos(u) <= arrived_tail(u);
        end
    end
end
