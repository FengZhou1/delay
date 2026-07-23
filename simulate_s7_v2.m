function result = simulate_s7_v2(protocol, trace, scenario, cfg, M, q, seed)
%SIMULATE_S7_V2 Ideal omnidirectional Sub-7 assisted access model.
% The Sub-7 control channel uses 9-us contention boundaries.  MLO arrivals
% remain on the common 5-us physical trace, and mmWave/SLO payloads last the
% exact physical Tp=190*M us without rounding to a Sub-7 minislot.

    if strcmp(protocol, 's7_clean')
        n_slo = 0;
    elseif strcmp(protocol, 's7_busy')
        n_slo = 10;
    else
        error('simulate_s7_v2:BadProtocol', 'Expected s7_clean or s7_busy.');
    end
    if M < 1 || M ~= round(M)
        error('simulate_s7_v2:BadM', 'M must be an integer >= 1.');
    end

    n_mlo = cfg.n_nodes;
    n_total = n_mlo + n_slo;
    tp_us = 190 * M;
    slot_us = scenario.SUB7.SLOT_TIME_US;
    difs_us = scenario.SUB7.DIFS_US;
    req_us = scenario.SUB7.ICF_US;
    resp_wait_us = scenario.SUB7.SIFS_US + scenario.SUB7.ICR_US + ...
                   scenario.SUB7.SIFS_US;

    IDLE = uint8(0); TX_REQ = uint8(1); WAIT_RESP = uint8(2);
    WAIT_TIMEOUT = uint8(3); TX_DATA_MMW = uint8(4); TX_DATA_SLO = uint8(5);
    state = repmat(IDLE, n_total, 1);
    deadline = inf(n_total, 1);
    nav_until = zeros(n_total, 1);
    difs_elapsed = zeros(n_total, 1);
    can_count_prev = false(n_total, 1);
    request_is_mlo = false(n_total, 1);

    stream = RandStream('mt19937ar', 'Seed', double(seed));
    node_packets = trace.packet_ids_by_node;
    arrived_tail = zeros(n_mlo, 1);
    head_pos = ones(n_mlo, 1);
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
    diag.collision_waste_us = 0;
    diag.collision_channel_time_us = 0;
    diag.collision_tx_airtime_us = 0;
    diag.collision_channel_time_measure_us = 0;
    diag.collision_tx_airtime_measure_us = 0;

    system_area = 0;
    service_area = 0;
    payload_overlap = 0;
    sample_t = zeros(ceil(cfg.measure_us/max(1,cfg.stats_sample_us))+4,1);
    sample_n = zeros(size(sample_t));
    sample_idx = 0;

    event_idx = 1;
    next_tick = 0;
    next_sample = cfg.warmup_us;
    reserved_until = 0;
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
                        data_end = response_end + tp_us;
                        other_mlo = (1:n_mlo)' ~= w;
                        nav_until(1:n_mlo) = max(nav_until(1:n_mlo), ...
                                                data_end * double(other_mlo));
                        if n_slo > 0
                            nav_until(n_mlo+1:end) = max( ...
                                nav_until(n_mlo+1:end), response_end);
                        end
                    else
                        diag.request_success_slo = diag.request_success_slo + 1;
                        data_end = response_end + tp_us;
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
                        deadline(u) = t + resp_wait_us;
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
                    reserved_until = max(reserved_until, t + tp_us);
                end
                deadline(u) = t + tp_us;
            end

            timeout_done = ending(ending_state == WAIT_TIMEOUT);
            if ~isempty(timeout_done)
                state(timeout_done) = IDLE;
                deadline(timeout_done) = inf;
                difs_elapsed(timeout_done) = 0;
                can_count_prev(timeout_done) = false;
            end

            mlo_done = ending(ending_state == TX_DATA_MMW);
            for k = 1:numel(mlo_done)
                u = mlo_done(k);
                pid = node_packets{u}(head_pos(u));
                pkt.completion_us(pid) = t;
                head_pos(u) = head_pos(u) + 1;
                backlog = backlog - 1;
                diag.mlo_payload_success = diag.mlo_payload_success + 1;
                payload_overlap = payload_overlap + interval_overlap_us( ...
                    t-tp_us, t, cfg.warmup_us, cfg.arrival_end_us);
                state(u) = IDLE;
                deadline(u) = inf;
                difs_elapsed(u) = 0;
                can_count_prev(u) = false;
                if head_pos(u) <= arrived_tail(u)
                    next_pid = node_packets{u}(head_pos(u));
                    pkt.hol_us(next_pid) = t;
                end
            end

            slo_done = ending(ending_state == TX_DATA_SLO);
            if ~isempty(slo_done)
                diag.slo_payload_success = diag.slo_payload_success + numel(slo_done);
                state(slo_done) = IDLE;
                deadline(slo_done) = inf;
                difs_elapsed(slo_done) = 0;
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

            has_mlo = false(n_mlo,1);
            for u = 1:n_mlo
                has_mlo(u) = head_pos(u) <= arrived_tail(u);
            end
            has_packet = [has_mlo; true(n_slo,1)];
            ready = state == IDLE & has_packet & nav_until <= t & ...
                    difs_elapsed >= difs_us & reserved_until <= t;
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
                has_mlo(u) = head_pos(u) <= arrived_tail(u);
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
    pkt.control_delay_us = zeros(n_pkt,1);
    pkt.control_delay_us(completed_mask) = req_us + resp_wait_us;
    pkt.data_delay_us = zeros(n_pkt,1);
    pkt.data_delay_us(completed_mask) = tp_us;
    component_sum = pkt.boundary_wait_us + pkt.difs_wait_us + ...
        pkt.probability_wait_us + pkt.collision_delay_us + ...
        pkt.control_delay_us + pkt.data_delay_us;
    pkt.busy_nav_wait_us = zeros(n_pkt,1);
    pkt.busy_nav_wait_us(completed_mask) = max(0, ...
        pkt.completion_us(completed_mask)-pkt.hol_us(completed_mask)- ...
        component_sum(completed_mask));
    pkt.other_access_delay_us = zeros(n_pkt,1);
    raw.packet_log = pkt;
    raw.final_backlog = backlog;
    raw.sim_end_us = t;
    raw.system_area_measure_us = system_area;
    raw.service_area_measure_us = service_area;
    raw.payload_success_overlap_us = payload_overlap;
    raw.backlog_sample_us = sample_t(1:sample_idx);
    raw.backlog_sample_n = sample_n(1:sample_idx);
    raw.diagnostics = diag;
    result = finalize_sim_result(raw, trace, cfg, protocol, M, q);
end
