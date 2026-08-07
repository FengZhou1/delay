function result = simulate_sb_cf_v2(trace, scenario, cfg, M, q, seed)
%SIMULATE_SB_CF_V2 Connection-free directional CSMA (event-driven).
%   result = simulate_sb_cf_v2(trace, scenario, cfg, M, q, seed)
%
% Identical access procedure to the SB-CB protocol except that the station
% transmits its DATA frame directly instead of reserving the channel with
% an RTS/CTS handshake.  Real-time (non slot-aligned) timings match the
% sf-cb / sb-cb light-load study: DIFS=34 us (aligned to a 36 us boundary),
% DATA = M * 162.5 us.
%
% A HOL packet senses at 9 us tick boundaries and, after a continuous idle
% of DIFS (align_up(sense_start+SIFS)+2 slots), draws Bernoulli(q) at the
% 9 us boundary and starts a real DATA frame of 162.5*M us.  A busy channel
% resets the DIFS counter.  Overlapping DATA frames collide (classic model).
% The AP receives the DATA omnidirectionally and judges success with the
% directional SINR threshold (DATA threshold 21 dB), so a late frame can
% spoil the winner's DATA.
%
% CCA modes: directional (real sensing), disabled (no sensing / no NAV).
%
% The output raw structure is compatible with finalize_sim_result.m /
% finalize_saturation_result.m, so the shared run_experiment pipeline is
% unchanged.

    TR = scenario.MMW_REAL;
    slot_us = double(TR.SLOT_US);              % 9 us sensing granularity
    sifs_us = double(TR.SIFS_US);              % 16 us
    difs_us = double(TR.DIFS_US);              % 34 us
    conn_slot_us = double(TR.CONN_OVERHEAD_US);% 162.5 us
    is_saturation = isfield(cfg,'traffic_mode') && ...
        strcmpi(char(cfg.traffic_mode),'saturation');
    if is_saturation
        tp_us = conn_slot_us * double(M);
    else
        tp_us = conn_slot_us * double(M);
    end
    % Carrier-sensing mode: 'disabled' disables CCA (stations transmit
    % after DIFS without sensing); otherwise the real channel is sensed.
    cca_mode = 'directional';
    if isfield(cfg,'cca_mode') && ~isempty(cfg.cca_mode)
        cca_mode = lower(char(cfg.cca_mode));
    end
    sense_enabled = ~strcmp(cca_mode,'disabled');

    n_nodes = double(cfg.n_nodes);
    n_sectors = double(cfg.n_sectors);
    n_packets = double(trace.n_packets);
    arrival_us = double(trace.times_us(:));
    node_id = double(trace.node_id(:));
    arrival_end_us = double(trace.arrival_end_us);
    hard_end_us = double(trace.hard_end_us);
    left_measure_us = double(cfg.warmup_us);
    right_measure_us = arrival_end_us;
    stats_sample_us = 500;
    if isfield(cfg,'stats_sample_us') && ~isempty(cfg.stats_sample_us)
        stats_sample_us = double(cfg.stats_sample_us);
    end
    stream = RandStream('mt19937ar','Seed',double(seed));

    node_sectors = double(scenario.sectors(:));
    PHY = scenario.PHY;
    int_matrix = PHY.Int_Matrix;
    ap_rx = PHY.AP_Rx_Matrix;
    ap_sector_tx = PHY.AP_Sector_Tx_Matrix;
    noise_w = 10.^((PHY.NOISE_DBM - 30) / 10);
    sens_w = 10.^((cfg.rx_sens_dbm - 30) / 10);
    data_sinr_th = PHY.DATA_SINR_TH_DB;

    % Node state machine constants.
    ST_IDLE = 0; ST_SENSE = 1; ST_READY = 2; ST_TX = 3; ...
        ST_NAV = 7;
    % AP phase constants (sb_cf has no handshake: IDLE or DATA).
    AP_IDLE = 0; AP_DATA = 4;

    % Per-packet bookkeeping (delay mode only).
    if is_saturation
        hol_us = zeros(0,1); first_attempt_us = zeros(0,1);
        completion_us = zeros(0,1); attempts = zeros(0,1);
        probability_wait_us = zeros(0,1); collision_delay_us = zeros(0,1);
        control_delay_us = zeros(0,1); data_delay_us = zeros(0,1);
        difs_wait_us = zeros(0,1);
    else
        hol_us = nan(n_packets,1);
        first_attempt_us = nan(n_packets,1);
        completion_us = nan(n_packets,1);
        attempts = zeros(n_packets,1);
        probability_wait_us = zeros(n_packets,1);
        collision_delay_us = zeros(n_packets,1);
        control_delay_us = zeros(n_packets,1);
        data_delay_us = zeros(n_packets,1);
        difs_wait_us = zeros(n_packets,1);
    end

    node_state = zeros(n_nodes,1);
    next_tick = inf(n_nodes,1);
    tx_end = inf(n_nodes,1);
    nav_until = zeros(n_nodes,1);
    sense_count = zeros(n_nodes,1);
    sense_start = nan(n_nodes,1);
    tx_overlap = false(n_nodes,1);
    ap_idle_at_start = false(n_nodes,1);
    attempt_start = nan(n_nodes,1);
    attempt_pid = zeros(n_nodes,1);
    tx_in_sector = false(n_nodes,1);

    queue_head = ones(n_nodes,1);
    queue_tail = zeros(n_nodes,1);
    queue_count = zeros(n_nodes,1);
    next_arrival = 1;

    ap_phase = AP_IDLE;
    ap_phase_end = inf;
    winner_id = 0;
    winner_data_start = 0;
    winner_data_end = 0;
    data_tx_active = false;
    data_failed = false;

    system_area_measure_us = 0;
    service_area_measure_us = 0;
    payload_success_overlap_us = 0;
    saturation_per_node_completions = zeros(n_nodes,1);
    backlog_sample_us = zeros(0,1);
    backlog_sample_n = zeros(0,1);
    next_backlog_sample_us = 0;

    diagnostics = struct();
    diagnostics.rts_attempts = 0;       % DATA attempt count (legacy name)
    diagnostics.rts_success = 0;        % successful DATA count
    diagnostics.rts_fail_total = 0;
    diagnostics.rts_fail_collision = 0;
    diagnostics.rts_fail_ap_busy = 0;
    diagnostics.data_reservations = 0;
    diagnostics.data_no_cts = 0;
    diagnostics.data_success = 0;
    diagnostics.data_fail_sinr = 0;
    diagnostics.data_fail_cts = 0;
    diagnostics.collision_waste_us = 0;
    diagnostics.collision_waste_measure_us = 0;
    diagnostics.rts_sinr_used = false;
    diagnostics.data_sinr_th_db = data_sinr_th;
    diagnostics.cts_sinr_th_db = PHY.CTS_SINR_TH_DB;
    diagnostics.rts_reception_model = 'classic_collision';
    diagnostics.cts_reception_model = 'none';
    diagnostics.data_reception_model = 'directional_sinr';
    diagnostics.sim_end_us = 0;
    diagnostics.payload_success_overlap_us = 0;
    diagnostics.cca_mode = cca_mode;
    diagnostics.rts_start_times_us = zeros(0,1);
    diagnostics.rts_start_nodes = zeros(0,1);

    t = 0;
    enqueue_until(t);
    while true
        enqueue_until(t);
        backlog_now = sum(queue_count);
        all_arrivals_seen = next_arrival > n_packets;
        radio_idle = ap_phase == AP_IDLE && ~any(node_state == ST_TX);
        if all_arrivals_seen && backlog_now == 0 && radio_idle
            break;
        end
        if t >= hard_end_us
            t = hard_end_us;
            break;
        end

        cand = inf;
        if next_arrival <= n_packets
            cand = min(cand, arrival_us(next_arrival));
        end
        cand = min(cand, min(next_tick));
        cand = min(cand, min(tx_end));
        if ap_phase ~= AP_IDLE
            cand = min(cand, ap_phase_end);
        end
        if ~isfinite(cand)
            error('simulate_sb_cf_v2:NoEvent', ...
                'No event is scheduled; simulation cannot advance.');
        end
        if cand < t
            error('simulate_sb_cf_v2:PastEvent', ...
                'Event time went backwards from %.6f to %.6f.', t, cand);
        end
        next_t = cand;
        if next_t > t
            overlap = interval_overlap_us(t, next_t, ...
                left_measure_us, right_measure_us);
            if overlap > 0
                system_area_measure_us = system_area_measure_us + ...
                    backlog_now * overlap;
                if data_tx_active
                    service_area_measure_us = ...
                        service_area_measure_us + overlap;
                end
            end
            while next_backlog_sample_us <= next_t
                backlog_sample_us(end+1,1) = next_backlog_sample_us; %#ok<AGROW>
                backlog_sample_n(end+1,1) = backlog_now; %#ok<AGROW>
                next_backlog_sample_us = ...
                    next_backlog_sample_us + stats_sample_us;
            end
        end
        t = next_t;

        enqueue_until(t);
        fin = find(tx_end == t).';
        for u = fin
            process_tx_end(u, t);
        end
        if ap_phase ~= AP_IDLE && t == ap_phase_end
            process_ap_phase_end(t);
        end
        tick_nodes = find(next_tick == t).';
        drawers = false(n_nodes,1);
        for u = tick_nodes
            if process_tick(u, t)
                drawers(u) = true;
            end
        end
        for u = find(drawers).'
            start_tx(u, t, drawers);
        end
    end

    sim_end_us = t;
    enqueue_until(sim_end_us);
    if ~is_saturation && next_arrival <= n_packets
        error('simulate_sb_cf_v2:UnseenArrivals', ...
            'Simulation ended before all arrivals were enqueued.');
    end
    final_backlog = sum(queue_count);
    if isempty(backlog_sample_us) || backlog_sample_us(end) ~= sim_end_us
        backlog_sample_us(end+1,1) = sim_end_us; %#ok<AGROW>
        backlog_sample_n(end+1,1) = final_backlog; %#ok<AGROW>
    end

    if ~is_saturation
        difs_wait_us = attempts * difs_us;
        diagnostics.payload_success_overlap_us = payload_success_overlap_us;
    end
    diagnostics.sim_end_us = sim_end_us;

    raw = struct();
    raw.final_backlog = final_backlog;
    raw.sim_end_us = sim_end_us;
    raw.system_area_measure_us = system_area_measure_us;
    raw.service_area_measure_us = service_area_measure_us;
    raw.payload_success_overlap_us = payload_success_overlap_us;
    raw.backlog_sample_us = backlog_sample_us;
    raw.backlog_sample_n = backlog_sample_n;
    raw.diagnostics = diagnostics;
    if is_saturation
        raw.packet_log = struct();
        raw.saturation_per_node_completions = saturation_per_node_completions;
    else
        packet_log = struct();
        packet_log.node_id = node_id;
        packet_log.arrival_us = arrival_us;
        packet_log.hol_us = hol_us;
        packet_log.first_attempt_us = first_attempt_us;
        packet_log.completion_us = completion_us;
        packet_log.attempts = attempts;
        packet_log.probability_wait_us = probability_wait_us;
        packet_log.boundary_wait_us = zeros(n_packets,1);
        packet_log.difs_wait_us = difs_wait_us;
        packet_log.collision_delay_us = collision_delay_us;
        packet_log.control_delay_us = control_delay_us;
        packet_log.data_delay_us = data_delay_us;
        packet_log.other_access_delay_us = zeros(n_packets,1);
        comp_others = packet_log.difs_wait_us + ...
            packet_log.probability_wait_us + packet_log.collision_delay_us + ...
            packet_log.control_delay_us + packet_log.data_delay_us + ...
            packet_log.boundary_wait_us + packet_log.other_access_delay_us;
        completed_mask = isfinite(packet_log.completion_us);
        packet_log.busy_nav_wait_us = zeros(n_packets,1);
        packet_log.busy_nav_wait_us(completed_mask) = max(0, ...
            packet_log.completion_us(completed_mask) - ...
            packet_log.hol_us(completed_mask) - ...
            comp_others(completed_mask));
        raw.packet_log = packet_log;
    end

    if is_saturation
        raw.saturation_per_node_completions = ...
            saturation_per_node_completions;
        result = finalize_saturation_result(raw, cfg, 'sb_cf', M, q);
    else
        result = finalize_sim_result(raw, trace, cfg, 'sb_cf', M, q);
    end

% ---------------- nested helpers ----------------
    function pid = head_packet_id(u)
        pid = trace.packet_ids_by_node{u}(queue_head(u));
    end

    function enqueue_until(limit_us)
        while next_arrival <= n_packets && ...
                arrival_us(next_arrival) <= limit_us
            pid = next_arrival;
            u = node_id(pid);
            queue_tail(u) = queue_tail(u) + 1;
            queue_count(u) = queue_count(u) + 1;
            if queue_count(u) == 1
                if ~is_saturation
                    hol_us(pid) = arrival_us(pid);
                end
                enter_hol(u, arrival_us(pid));
            end
            next_arrival = next_arrival + 1;
        end
    end

    function enter_hol(u, t_hol)
        if nav_until(u) > t_hol
            node_state(u) = ST_NAV;
            sense_count(u) = 0;
            sense_start(u) = nav_until(u);
            next_tick(u) = nav_until(u);
            if next_tick(u) <= t_hol
                next_tick(u) = t_hol + slot_us;
            end
        else
            % Sensing starts at the next 9 us boundary after the HOL
            % instant; DIFS completes at align_up(sense_start + SIFS) +
            % 2*slot, and the DATA is transmitted at a boundary.
            node_state(u) = ST_SENSE;
            sense_count(u) = 0;
            sense_start(u) = t_hol;
            next_tick(u) = ceil(t_hol / slot_us) * slot_us;
        end
    end

    function flag = process_tick(u, t_now)
        flag = false;
        if node_state(u) == ST_IDLE
            next_tick(u) = inf;
            return;
        end
        if queue_count(u) == 0
            node_state(u) = ST_IDLE;
            next_tick(u) = inf;
            return;
        end
        if nav_until(u) > t_now
            node_state(u) = ST_NAV;
            sense_count(u) = 0;
            sense_start(u) = nav_until(u);
            next_tick(u) = nav_until(u);
            if next_tick(u) <= t_now
                next_tick(u) = t_now + slot_us;
            end
            return;
        end
        if node_state(u) == ST_NAV
            node_state(u) = ST_SENSE;
            sense_start(u) = t_now;
            next_tick(u) = ceil(t_now / slot_us) * slot_us;
            sense_count(u) = 0;
            return;
        end
        if node_state(u) == ST_SENSE
            [busy, busy_end] = sense_busy(u, t_now);
            if busy
                sense_count(u) = 0;
                sense_start(u) = busy_end;
                next_tick(u) = ceil(busy_end / slot_us) * slot_us;
                return;
            end
            if t_now >= sense_start(u) + sifs_us
                difs_ok = ceil((sense_start(u) + sifs_us) / slot_us) * slot_us;
                if t_now >= difs_ok + 2 * slot_us
                    node_state(u) = ST_READY;
                    sense_count(u) = 0;
                else
                    next_tick(u) = difs_ok + 2 * slot_us;
                    return;
                end
            else
                next_tick(u) = t_now + slot_us;
                return;
            end
        end
        if node_state(u) ~= ST_READY
            next_tick(u) = inf;
            return;
        end
        [busy, busy_end] = sense_busy(u, t_now);
        if busy
            node_state(u) = ST_SENSE;
            sense_count(u) = 0;
            sense_start(u) = busy_end;
            next_tick(u) = ceil(busy_end / slot_us) * slot_us;
            return;
        end
        % Slot boundary decision: Bernoulli(q), transmit immediately
        % if drawn, otherwise wait for the next boundary.
        if rand(stream) < q
            flag = true;
        else
            next_tick(u) = t_now + slot_us;
        end
    end

    function start_tx(u, t_now, drawers)
        diagnostics.rts_attempts = diagnostics.rts_attempts + 1;
        diagnostics.rts_start_times_us = [diagnostics.rts_start_times_us; t_now];
        diagnostics.rts_start_nodes = [diagnostics.rts_start_nodes; u];
        if ~is_saturation
            pid = head_packet_id(u);
            attempts(pid) = attempts(pid) + 1;
            if isnan(first_attempt_us(pid))
                first_attempt_us(pid) = t_now;
            end
            attempt_pid(u) = pid;
        else
            attempt_pid(u) = 0;
        end
        attempt_start(u) = t_now;
        node_state(u) = ST_TX;
        tx_end(u) = t_now + tp_us;
        tx_overlap(u) = false;
        ap_idle_at_start(u) = ap_phase == AP_IDLE;
        sense_count(u) = 0;

        others = find(node_state == ST_TX).';
        others = others(others ~= u);
        if ~isempty(others)
            tx_overlap(u) = true;
            tx_overlap(others) = true;
        end
        if ap_phase == AP_DATA && data_tx_active
            eval_data_sinr();
        end
    end

    function process_tx_end(u, t_now)
        tx_end(u) = inf;
        % A DATA frame succeeds when it never overlapped another frame and
        % the AP was idle when it started.
        succeeded = ~tx_overlap(u) && ap_idle_at_start(u);
        if succeeded
            winner_id = u;
            winner_data_start = t_now - tp_us;
            winner_data_end = t_now;
            data_tx_active = true;
            data_failed = false;
            ap_phase = AP_DATA;
            ap_phase_end = t_now;
            % AP judges this frame now (no late interference yet).
            eval_data_sinr();
            diagnostics.data_reservations = diagnostics.data_reservations + 1;
            if data_failed
                diagnostics.data_fail_sinr = diagnostics.data_fail_sinr + 1;
                diagnostics.rts_fail_total = diagnostics.rts_fail_total + 1;
            end
        else
            node_state(u) = ST_SENSE;
            sense_start(u) = t_now;
            next_tick(u) = ceil(t_now / slot_us) * slot_us;
            sense_count(u) = 0;
            diagnostics.rts_fail_total = diagnostics.rts_fail_total + 1;
            if tx_overlap(u)
                diagnostics.rts_fail_collision = ...
                    diagnostics.rts_fail_collision + 1;
                diagnostics.collision_waste_us = ...
                    diagnostics.collision_waste_us + tp_us;
                % The wasted interval is clipped to the hard horizon so a
                % transmission truncated by the end of the simulation does
                % not report airtime beyond it.
                waste_end = min(t_now, hard_end_us);
                diagnostics.collision_waste_measure_us = ...
                    diagnostics.collision_waste_measure_us + ...
                    interval_overlap_us(t_now - tp_us, waste_end, ...
                        left_measure_us, right_measure_us);
                if ~is_saturation && attempt_pid(u) > 0
                    pid = attempt_pid(u);
                    collision_delay_us(pid) = ...
                        collision_delay_us(pid) + tp_us;
                    attempt_pid(u) = 0;
                    attempt_start(u) = nan;
                end
            elseif ~ap_idle_at_start(u)
                diagnostics.rts_fail_ap_busy = ...
                    diagnostics.rts_fail_ap_busy + 1;
            end
        end
    end

    function process_ap_phase_end(t_now)
        switch ap_phase
            case AP_DATA
                transaction_success = ~data_failed && winner_id > 0;
                if transaction_success
                    if is_saturation
                        if t_now >= left_measure_us && ...
                                t_now < right_measure_us
                            saturation_per_node_completions(winner_id) = ...
                                saturation_per_node_completions(winner_id) + 1;
                        end
                    elseif attempt_pid(winner_id) > 0
                        pid = attempt_pid(winner_id);
                        completion_us(pid) = t_now;
                        data_delay_us(pid) = tp_us;
                    end
                    payload_success_overlap_us = ...
                        payload_success_overlap_us + ...
                        interval_overlap_us(winner_data_start, t_now, ...
                            left_measure_us, right_measure_us);
                    diagnostics.data_success = ...
                        diagnostics.data_success + 1;
                    diagnostics.rts_success = diagnostics.rts_success + 1;
                else
                    if winner_id > 0 && data_failed
                        diagnostics.data_fail_sinr = ...
                            diagnostics.data_fail_sinr + 1;
                        if ~is_saturation && attempt_pid(winner_id) > 0
                            pid = attempt_pid(winner_id);
                            collision_delay_us(pid) = ...
                                collision_delay_us(pid) + ...
                                (t_now - attempt_start(winner_id));
                            attempt_pid(winner_id) = 0;
                            attempt_start(winner_id) = nan;
                        end
                    end
                end
                if winner_id > 0
                    if ~is_saturation
                        if attempt_pid(winner_id) > 0
                            if transaction_success && ~isempty( ...
                                    trace.packet_ids_by_node{winner_id}) && ...
                                    queue_count(winner_id) > 0
                                pop_head(winner_id, t_now);
                            end
                            attempt_pid(winner_id) = 0;
                            attempt_start(winner_id) = nan;
                        end
                    end
                    if queue_count(winner_id) > 0
                        node_state(winner_id) = ST_SENSE;
                        sense_start(winner_id) = t_now;
                        sense_count(winner_id) = 0;
                        next_tick(winner_id) = ceil(t_now / slot_us) * slot_us;
                        if next_tick(winner_id) <= t_now
                            next_tick(winner_id) = t_now + slot_us;
                        end
                    else
                        node_state(winner_id) = ST_IDLE;
                        next_tick(winner_id) = inf;
                    end
                    winner_id = 0;
                end
                data_tx_active = false;
                data_failed = false;
                ap_phase = AP_IDLE;
                ap_phase_end = inf;
        end
    end

    function pop_head(u, t_now)
        queue_head(u) = queue_head(u) + 1;
        queue_count(u) = queue_count(u) - 1;
        if queue_head(u) > queue_tail(u)
            queue_count(u) = 0;
        elseif queue_head(u) <= queue_tail(u)
            next_pid = trace.packet_ids_by_node{u}(queue_head(u));
            hol_us(next_pid) = t_now;
        end
    end

    function [busy, busy_end] = sense_busy(u, t_now)
        busy = false;
        busy_end = inf;
        if ~sense_enabled
            return;
        end
        if data_tx_active && winner_id > 0 && winner_id ~= u
            if int_matrix(winner_id, u) > sens_w
                busy = true;
                busy_end = min(busy_end, winner_data_end);
            end
        end
        tx_nodes = find(node_state == ST_TX).';
        for v = tx_nodes
            if v ~= u && int_matrix(v, u) > sens_w
                busy = true;
                busy_end = min(busy_end, tx_end(v));
            end
        end
    end

    function eval_data_sinr()
        if ~(data_tx_active && winner_id > 0)
            return;
        end
        interferers = find(node_state == ST_TX).';
        interferers = interferers(interferers ~= winner_id);
        interf = 0;
        if ~isempty(interferers)
            interf = sum(ap_rx(winner_id, interferers));
        end
        desired = ap_rx(winner_id, winner_id);
        sinr_db = 10*log10(desired / (noise_w + interf + eps));
        if sinr_db < data_sinr_th
            data_failed = true;
        end
    end
end
