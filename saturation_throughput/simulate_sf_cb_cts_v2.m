function result = simulate_sf_cb_cts_v2(trace, scenario, cfg, M, q, seed)
%SIMULATE_SF_CB_CTS_V2 Slotted connection-based access with configurable CTS.
%   This engine is used when sf_cb runs with quasi-omni or winner-directed
%   CTS.  Contention occurs on 61-us slot boundaries and has no CCA/DIFS.
%   CTS reception and DATA success are evaluated with the configured SINR
%   thresholds unless the CTS mode is the ideal all-hear upper bound.

    TR = scenario.MMW_REAL;
    slot_us = double(TR.SLOT_US);
    rts_us = double(TR.RTS_US);
    sifs_us = double(TR.SIFS_US);
    cts_us = double(TR.CTS_US);
    conn_slot_us = double(TR.CONN_OVERHEAD_US);
    if isfield(TR,'DATA_SLOT_US') && ~isempty(TR.DATA_SLOT_US)
        data_slot_us = double(TR.DATA_SLOT_US);
    else
        data_slot_us = conn_slot_us;
    end

    cts_mode = lower(char(cfg.cts_mode));
    if ~ismember(cts_mode,{'quasi_omni_ideal','quasi_omni_physical', ...
            'quasi_omni_isotropic','directional_winner'})
        error('simulate_sf_cb_cts_v2:BadCtsMode', ...
            'Unsupported non-sector CTS mode: %s.',cts_mode);
    end
    data_failure_mode = 'txop';
    if isfield(cfg,'data_failure_mode') && ~isempty(cfg.data_failure_mode)
        data_failure_mode = lower(char(cfg.data_failure_mode));
    end
    if ~ismember(data_failure_mode,{'txop','packet'})
        error('simulate_sf_cb_cts_v2:BadFailureMode', ...
            'data_failure_mode must be txop or packet.');
    end

    is_saturation = isfield(cfg,'traffic_mode') && ...
        strcmpi(char(cfg.traffic_mode),'saturation');
    n_nodes = double(cfg.n_nodes);
    n_packets = double(trace.n_packets);
    arrival_us = double(trace.times_us(:));
    node_id = double(trace.node_id(:));
    arrival_end_us = double(trace.arrival_end_us);
    hard_end_us = double(trace.hard_end_us);
    left_measure_us = double(cfg.warmup_us);
    right_measure_us = arrival_end_us;
    stream = RandStream('mt19937ar','Seed',double(seed));

    PHY = scenario.PHY;
    int_matrix = PHY.Int_Matrix;
    ap_rx = PHY.AP_Rx_Matrix;
    noise_w = 10.^((PHY.NOISE_DBM - 30) / 10);
    cts_sinr_th = PHY.CTS_SINR_TH_DB;
    data_sinr_th = PHY.DATA_SINR_TH_DB;
    if strcmp(cts_mode,'quasi_omni_ideal')
        cts_tx_matrix = [];
    else
        if ~isfield(PHY,'AP_CTS_Tx_Matrix') || isempty(PHY.AP_CTS_Tx_Matrix)
            error('simulate_sf_cb_cts_v2:MissingCtsMatrix', ...
                'AP_CTS_Tx_Matrix is required for physical CTS modes.');
        end
        cts_tx_matrix = PHY.AP_CTS_Tx_Matrix;
    end

    ST_IDLE = 0; ST_READY = 1; ST_RTS = 2; ST_WAIT = 3;
    ST_LOCKED = 4; ST_NAV = 5;
    AP_IDLE = 0; AP_SIFS_PRE = 1; AP_CTS = 2;
    AP_SIFS_POST = 3; AP_DATA = 4;

    if is_saturation
        hol_us = zeros(0,1); first_attempt_us = zeros(0,1);
        completion_us = zeros(0,1); attempts = zeros(0,1);
        probability_wait_us = zeros(0,1); collision_delay_us = zeros(0,1);
        control_delay_us = zeros(0,1); data_delay_us = zeros(0,1);
    else
        hol_us = nan(n_packets,1);
        first_attempt_us = nan(n_packets,1);
        completion_us = nan(n_packets,1);
        attempts = zeros(n_packets,1);
        probability_wait_us = zeros(n_packets,1);
        collision_delay_us = zeros(n_packets,1);
        control_delay_us = zeros(n_packets,1);
        data_delay_us = zeros(n_packets,1);
    end

    node_state = zeros(n_nodes,1);
    next_tick = inf(n_nodes,1);
    rts_end = inf(n_nodes,1);
    wait_timeout = inf(n_nodes,1);
    nav_until = zeros(n_nodes,1);
    slot_start = nan(n_nodes,1);
    rts_overlap = false(n_nodes,1);
    ap_idle_at_start = false(n_nodes,1);
    attempt_start = nan(n_nodes,1);
    attempt_pid = zeros(n_nodes,1);
    cts_min_sinr = inf(n_nodes,1);
    data_interferer_start = nan(n_nodes,1);
    data_intervals = zeros(0,2);

    queue_head = ones(n_nodes,1);
    queue_tail = zeros(n_nodes,1);
    queue_count = zeros(n_nodes,1);
    packet_delivered = false(n_packets,1);
    txop_packet_ids = zeros(0,1);
    next_arrival = 1;

    ap_phase = AP_IDLE;
    ap_phase_end = inf;
    current_sector = 0;
    winner_id = 0;
    winner_cts_ok = false;
    winner_data_start = 0;
    winner_data_end = 0;
    txop_n_packets = 0;
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
    diagnostics.rts_attempts = 0;
    diagnostics.rts_success = 0;
    diagnostics.rts_fail_total = 0;
    diagnostics.rts_fail_collision = 0;
    diagnostics.rts_fail_ap_busy = 0;
    diagnostics.rts_response_timeouts = 0;
    diagnostics.cts_decoded_winner = 0;
    diagnostics.cts_miss_winner = 0;
    diagnostics.nav_set = 0;
    diagnostics.data_reservations = 0;
    diagnostics.data_no_cts = 0;
    diagnostics.data_success = 0;
    diagnostics.data_fail_sinr = 0;
    diagnostics.data_fail_cts = 0;
    diagnostics.collision_waste_us = 0;
    diagnostics.rts_during_cts = 0;
    diagnostics.rts_during_data = 0;
    diagnostics.packet_mode_partial_success = 0;
    diagnostics.cts_mode = cts_mode;
    diagnostics.data_failure_mode = data_failure_mode;
    diagnostics.txop_mode = 'ready_queue';
    if isfield(cfg,'txop_mode') && ~isempty(cfg.txop_mode)
        diagnostics.txop_mode = char(cfg.txop_mode);
    end
    diagnostics.batch_requests = false;

    t = 0;
    event_count = 0;
    enqueue_until(t);
    while true
        event_count = event_count + 1;
        if event_count > 1e6
            error('simulate_sf_cb_cts_v2:EventLimit', ...
                'Event limit exceeded at t=%.6f us.',t);
        end
        enqueue_until(t);
        backlog_now = sum(queue_count);
        all_arrivals_seen = next_arrival > n_packets;
        radio_idle = ap_phase == AP_IDLE && ~any(node_state == ST_RTS);
        if all_arrivals_seen && backlog_now == 0 && radio_idle
            break;
        end
        if t >= hard_end_us
            t = hard_end_us;
            break;
        end

        cand = inf;
        if next_arrival <= n_packets
            cand = min(cand,arrival_us(next_arrival));
        end
        cand = min(cand,min(next_tick));
        cand = min(cand,min(rts_end));
        cand = min(cand,min(wait_timeout));
        if ap_phase ~= AP_IDLE
            cand = min(cand,ap_phase_end);
        end
        if ~isfinite(cand)
            error('simulate_sf_cb_cts_v2:NoEvent', ...
                'No event is scheduled; simulation cannot advance.');
        end
        if cand < t
            error('simulate_sf_cb_cts_v2:PastEvent', ...
                ['Event time moved backwards from %.6f to %.6f us ' ...
                 '(tick=%.6f rts=%.6f wait=%.6f ap=%.6f).'], ...
                t,cand,min(next_tick),min(rts_end),min(wait_timeout), ...
                ap_phase_end);
        end
        next_t = cand;
        if next_t > t
            overlap = interval_overlap_us(t,next_t, ...
                left_measure_us,right_measure_us);
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
                    next_backlog_sample_us + cfg.stats_sample_us;
            end
        end
        t = next_t;
        late_ticks = find(next_tick < t - 1e-9).';
        if ~isempty(late_ticks)
            next_tick(late_ticks) = t;
        end

        enqueue_until(t);
        finishing = find(rts_end == t).';
        for u = finishing
            process_rts_end(u,t);
        end
        timeouts = find(wait_timeout == t).';
        for u = timeouts
            process_timeout(u,t);
        end
        if ap_phase ~= AP_IDLE && t == ap_phase_end
            process_ap_phase_end(t);
        end
        tick_nodes = find(next_tick == t).';
        drawers = false(n_nodes,1);
        for u = tick_nodes
            if process_tick(u,t)
                drawers(u) = true;
            end
        end
        for u = find(drawers).'
            start_rts(u,t,drawers);
        end
        stale_ticks = find(next_tick < t - 1e-9).';
        if ~isempty(stale_ticks)
            next_tick(stale_ticks) = t;
        end
    end

    sim_end_us = t;
    enqueue_until(sim_end_us);
    if ~is_saturation && next_arrival <= n_packets
        error('simulate_sf_cb_cts_v2:UnseenArrivals', ...
            'Simulation ended before all arrivals were enqueued.');
    end
    final_backlog = sum(queue_count);
    if isempty(backlog_sample_us) || backlog_sample_us(end) ~= sim_end_us
        backlog_sample_us(end+1,1) = sim_end_us; %#ok<AGROW>
        backlog_sample_n(end+1,1) = final_backlog; %#ok<AGROW>
    end

    diagnostics.sim_end_us = sim_end_us;
    diagnostics.cts_reception_model = cts_mode;
    diagnostics.data_reception_model = 'directional_sinr';
    diagnostics.cts_sinr_th_db = cts_sinr_th;
    diagnostics.data_sinr_th_db = data_sinr_th;
    diagnostics.cca_mode = 'disabled';

    raw = struct();
    raw.final_backlog = final_backlog;
    raw.sim_end_us = sim_end_us;
    raw.system_area_measure_us = system_area_measure_us;
    raw.service_area_measure_us = service_area_measure_us;
    raw.payload_success_overlap_us = payload_success_overlap_us;
    raw.backlog_sample_us = backlog_sample_us;
    raw.backlog_sample_n = backlog_sample_n;
    raw.diagnostics = diagnostics;
    raw.structural_censored = false(n_packets,1);

    if is_saturation
        raw.packet_log = struct();
        raw.saturation_per_node_completions = saturation_per_node_completions;
        result = finalize_saturation_result(raw,cfg,'sf_cb',M,q);
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
        packet_log.difs_wait_us = zeros(n_packets,1);
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
        packet_log.busy_nav_wait_us(completed_mask) = ...
            packet_log.completion_us(completed_mask) - ...
            packet_log.hol_us(completed_mask) - comp_others(completed_mask);
        raw.packet_log = packet_log;
        result = finalize_sim_result(raw,trace,cfg,'sf_cb',M,q);
    end

% -------------------------------------------------------------------------
    function enqueue_until(limit_us)
        while next_arrival <= n_packets && arrival_us(next_arrival) <= limit_us
            pid = next_arrival;
            u = node_id(pid);
            queue_tail(u) = queue_tail(u) + 1;
            queue_count(u) = queue_count(u) + 1;
            if queue_count(u) == 1 && ~is_saturation
                hol_us(pid) = arrival_us(pid);
                enter_hol(u,arrival_us(pid));
            elseif queue_count(u) == 1 && is_saturation
                enter_hol(u,arrival_us(pid));
            end
            next_arrival = next_arrival + 1;
        end
    end

    function enter_hol(u,t_hol)
        if nav_until(u) > t_hol
            node_state(u) = ST_NAV;
            next_tick(u) = boundary_at_or_after(nav_until(u));
        else
            node_state(u) = ST_READY;
            next_tick(u) = boundary_at_or_after(t_hol);
        end
    end

    function b = boundary_at_or_after(t_in)
        b = ceil(t_in / conn_slot_us - 1e-12) * conn_slot_us;
        if b < t_in - 1e-9
            b = b + conn_slot_us;
        end
    end

    function pid = head_packet_id(u)
        pid = 0;
        if u < 1 || u > n_nodes || queue_head(u) > queue_tail(u)
            return;
        end
        ids = trace.packet_ids_by_node{u};
        for idx = queue_head(u):queue_tail(u)
            candidate = ids(idx);
            if ~packet_delivered(candidate)
                pid = candidate;
                return;
            end
        end
    end

    function [ids,n] = select_txop_packets(u,max_packets)
        ids = zeros(0,1);
        if u < 1 || u > n_nodes || queue_head(u) > queue_tail(u)
            n = 0;
            return;
        end
        all_ids = trace.packet_ids_by_node{u};
        for idx = queue_head(u):queue_tail(u)
            pid = all_ids(idx);
            if ~packet_delivered(pid)
                ids(end+1,1) = pid; %#ok<AGROW>
                if numel(ids) >= max_packets
                    break;
                end
            end
        end
        n = numel(ids);
    end

    function flag = process_tick(u,t_now)
        flag = false;
        if queue_count(u) <= 0
            node_state(u) = ST_IDLE;
            next_tick(u) = inf;
            return;
        end
        if nav_until(u) > t_now
            node_state(u) = ST_NAV;
            next_tick(u) = boundary_at_or_after(nav_until(u));
            return;
        end
        if node_state(u) == ST_NAV
            node_state(u) = ST_READY;
            next_tick(u) = boundary_at_or_after(t_now);
            return;
        end
        if node_state(u) ~= ST_READY
            return;
        end
        if abs(t_now - round(t_now/conn_slot_us)*conn_slot_us) > 1e-8
            next_tick(u) = boundary_at_or_after(t_now);
            return;
        end
        if rand(stream) < q
            flag = true;
        else
            next_tick(u) = t_now + conn_slot_us;
        end
    end

    function start_rts(u,t_now,drawers)
        diagnostics.rts_attempts = diagnostics.rts_attempts + 1;
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
        slot_start(u) = t_now;
        node_state(u) = ST_RTS;
        next_tick(u) = inf;
        rts_end(u) = t_now + rts_us;
        rts_overlap(u) = false;
        ap_idle_at_start(u) = ap_phase == AP_IDLE;

        others = find(node_state == ST_RTS).';
        others = others(others ~= u);
        if ~isempty(others)
            rts_overlap(u) = true;
            rts_overlap(others) = true;
        end
        if ap_phase == AP_CTS
            diagnostics.rts_during_cts = diagnostics.rts_during_cts + 1;
            update_cts_sinr();
        end
        if ap_phase == AP_DATA && data_tx_active
            diagnostics.rts_during_data = diagnostics.rts_during_data + 1;
            data_interferer_start(u) = t_now;
            eval_data_sinr();
        end
    end

    function process_rts_end(u,t_now)
        rts_end(u) = inf;
        if isfinite(data_interferer_start(u))
            interval = [data_interferer_start(u),t_now];
            if interval(2) > interval(1)
                data_intervals(end+1,:) = interval; %#ok<AGROW>
            end
            data_interferer_start(u) = nan;
            if ap_phase == AP_DATA && data_tx_active
                eval_data_sinr();
            end
        end

        succeeded = ~rts_overlap(u) && ap_idle_at_start(u) && ap_phase == AP_IDLE;
        if succeeded
            winner_id = u;
            winner_cts_ok = false;
            node_state(u) = ST_LOCKED;
            ap_phase = AP_SIFS_PRE;
            ap_phase_end = t_now + sifs_us;
            if is_saturation
                txop_n_packets = M;
                txop_packet_ids = zeros(0,1);
            else
                [txop_packet_ids,txop_n_packets] = select_txop_packets(u,M);
            end
            winner_data_start = ap_phase_end + cts_us + sifs_us;
            winner_data_end = winner_data_start + txop_n_packets*data_slot_us;
            diagnostics.rts_success = diagnostics.rts_success + 1;
            return;
        end

        node_state(u) = ST_WAIT;
        wait_timeout(u) = boundary_at_or_after(t_now);
        diagnostics.rts_fail_total = diagnostics.rts_fail_total + 1;
        if rts_overlap(u)
            diagnostics.rts_fail_collision = diagnostics.rts_fail_collision + 1;
        elseif ~ap_idle_at_start(u) || ap_phase ~= AP_IDLE
            diagnostics.rts_fail_ap_busy = diagnostics.rts_fail_ap_busy + 1;
        end
        diagnostics.collision_waste_us = diagnostics.collision_waste_us + rts_us;
    end

    function process_timeout(u,t_now)
        wait_timeout(u) = inf;
        if node_state(u) == ST_LOCKED
            return;
        end
        if ~is_saturation && attempt_pid(u) > 0
            pid = attempt_pid(u);
            collision_delay_us(pid) = collision_delay_us(pid) + ...
                (t_now - attempt_start(u));
            attempt_pid(u) = 0;
            attempt_start(u) = nan;
            diagnostics.rts_response_timeouts = ...
                diagnostics.rts_response_timeouts + 1;
        end
        node_state(u) = ST_READY;
        next_tick(u) = boundary_at_or_after(t_now);
    end

    function process_single_cts_end(t_now)
        if strcmp(cts_mode,'quasi_omni_ideal')
            winner_cts_ok = winner_id > 0;
        else
            winner_cts_ok = winner_id > 0 && ...
                cts_min_sinr(winner_id) >= cts_sinr_th;
        end
        if winner_cts_ok
            diagnostics.cts_decoded_winner = ...
                diagnostics.cts_decoded_winner + 1;
        else
            diagnostics.cts_miss_winner = ...
                diagnostics.cts_miss_winner + 1;
        end

        for u = 1:n_nodes
            if u == winner_id || node_state(u) == ST_RTS
                continue;
            end
            decoded = strcmp(cts_mode,'quasi_omni_ideal') || ...
                cts_min_sinr(u) >= cts_sinr_th;
            if decoded
                nav_until(u) = max(nav_until(u),winner_data_end);
                diagnostics.nav_set = diagnostics.nav_set + 1;
                if ~is_saturation && attempt_pid(u) > 0
                    pid = attempt_pid(u);
                    collision_delay_us(pid) = collision_delay_us(pid) + ...
                        (t_now - attempt_start(u));
                    attempt_pid(u) = 0;
                    attempt_start(u) = nan;
                    wait_timeout(u) = inf;
                end
                if ismember(node_state(u),[ST_WAIT,ST_READY,ST_NAV])
                    node_state(u) = ST_NAV;
                    next_tick(u) = boundary_at_or_after(winner_data_end);
                end
            end
        end
    end

    function process_ap_phase_end(t_now)
        switch ap_phase
            case AP_SIFS_PRE
                ap_phase = AP_CTS;
                ap_phase_end = t_now + cts_us;
                cts_min_sinr(:) = inf;
                update_cts_sinr();
            case AP_CTS
                process_single_cts_end(t_now);
                ap_phase = AP_SIFS_POST;
                ap_phase_end = t_now + sifs_us;
            case AP_SIFS_POST
                if winner_cts_ok && winner_id > 0
                    ap_phase = AP_DATA;
                    ap_phase_end = winner_data_end;
                    data_tx_active = true;
                    data_failed = false;
                    diagnostics.data_reservations = ...
                        diagnostics.data_reservations + 1;
                    eval_data_sinr();
                else
                    diagnostics.data_no_cts = diagnostics.data_no_cts + 1;
                    if winner_id > 0
                        node_state(winner_id) = ST_READY;
                        next_tick(winner_id) = boundary_at_or_after(t_now);
                        wait_timeout(winner_id) = inf;
                    end
                    winner_id = 0;
                    winner_cts_ok = false;
                    data_tx_active = false;
                    ap_phase = AP_IDLE;
                    ap_phase_end = inf;
                end
            case AP_DATA
                finish_data_phase(t_now);
                ap_phase = AP_IDLE;
                ap_phase_end = inf;
                data_tx_active = false;
        end
    end

    function finish_data_phase(t_now)
        ongoing = find(isfinite(data_interferer_start)).';
        for u = ongoing
            interval = [data_interferer_start(u),min(rts_end(u),t_now)];
            if interval(2) > interval(1)
                data_intervals(end+1,:) = interval; %#ok<AGROW>
            end
            data_interferer_start(u) = nan;
        end

        n_ok = 0;
        success_mask = false;
        if winner_cts_ok && winner_id > 0
            if strcmp(data_failure_mode,'txop')
                if is_saturation
                    success_mask = logical(~data_failed);
                    n_ok = txop_n_packets * double(success_mask);
                else
                    success_mask = true(1,numel(txop_packet_ids));
                    if data_failed
                        success_mask(:) = false;
                    end
                    n_ok = sum(success_mask);
                end
            else
                [n_ok,mask] = packet_success_mask(winner_data_start, ...
                    data_slot_us,txop_n_packets,data_intervals);
                success_mask = mask;
            end
        end
        if n_ok > 0
            if is_saturation
                complete_saturation_packets(n_ok,t_now);
            else
                complete_successful_packets(success_mask,t_now);
            end
            diagnostics.data_success = diagnostics.data_success + 1;
            if strcmp(data_failure_mode,'packet') && n_ok < txop_n_packets
                diagnostics.packet_mode_partial_success = ...
                    diagnostics.packet_mode_partial_success + 1;
            end
        elseif winner_cts_ok
            diagnostics.data_fail_sinr = diagnostics.data_fail_sinr + 1;
            if ~is_saturation && winner_id > 0 && attempt_pid(winner_id) > 0
                pid = attempt_pid(winner_id);
                collision_delay_us(pid) = collision_delay_us(pid) + ...
                    (t_now - attempt_start(winner_id));
            end
        else
            diagnostics.data_fail_cts = diagnostics.data_fail_cts + 1;
        end

        if winner_id > 0
            if attempt_pid(winner_id) > 0
                attempt_pid(winner_id) = 0;
                attempt_start(winner_id) = nan;
            end
            if queue_count(winner_id) > 0
                node_state(winner_id) = ST_READY;
                next_tick(winner_id) = boundary_at_or_after(t_now);
            else
                node_state(winner_id) = ST_IDLE;
                next_tick(winner_id) = inf;
            end
        end
        winner_id = 0;
        winner_cts_ok = false;
        data_failed = false;
        data_intervals = zeros(0,2);
    end

    function complete_saturation_packets(n_ok,t_now)
        payload_duration_us = n_ok * data_slot_us;
        payload_success_overlap_us = payload_success_overlap_us + ...
            interval_overlap_us(winner_data_start, ...
                winner_data_start + payload_duration_us, ...
                left_measure_us,right_measure_us);
        if t_now >= left_measure_us && t_now < right_measure_us
            saturation_per_node_completions(winner_id) = ...
                saturation_per_node_completions(winner_id) + ...
                n_ok / max(txop_n_packets,eps);
        end
    end

    function complete_successful_packets(success_mask,t_now)
        if isscalar(success_mask) && numel(txop_packet_ids) > 1
            success_mask = repmat(logical(success_mask),1,numel(txop_packet_ids));
        end
        for pp = 1:numel(txop_packet_ids)
            if ~success_mask(pp)
                continue;
            end
            pid = txop_packet_ids(pp);
            packet_delivered(pid) = true;
            completion_us(pid) = winner_data_start + pp*data_slot_us;
            data_delay_us(pid) = data_slot_us;
            if pp == 1
                control_delay_us(pid) = conn_slot_us;
            else
                hol_us(pid) = winner_data_start + (pp-1)*data_slot_us;
            end
            queue_count(winner_id) = max(0,queue_count(winner_id)-1);
        end
        advance_head(winner_id);
    end

    function advance_head(u)
        ids = trace.packet_ids_by_node{u};
        while queue_head(u) <= queue_tail(u)
            pid = ids(queue_head(u));
            if ~packet_delivered(pid)
                break;
            end
            queue_head(u) = queue_head(u) + 1;
        end
        if queue_head(u) <= queue_tail(u)
            next_pid = ids(queue_head(u));
            if isnan(hol_us(next_pid))
                hol_us(next_pid) = max(t,arrival_us(next_pid));
            end
        end
    end

    function update_cts_sinr()
        if ap_phase ~= AP_CTS || winner_id <= 0
            return;
        end
        interferers = find(node_state == ST_RTS).';
        for u = 1:n_nodes
            if node_state(u) == ST_RTS
                cts_min_sinr(u) = -inf;
                continue;
            end
            if strcmp(cts_mode,'quasi_omni_ideal')
                sinr_db = inf;
            else
                desired = cts_tx_matrix(winner_id,u);
                interf = 0;
                if ~isempty(interferers)
                    interf = sum(int_matrix(interferers,u));
                end
                sinr_db = 10*log10(desired / (noise_w + interf + eps));
            end
            cts_min_sinr(u) = min(cts_min_sinr(u),sinr_db);
        end
    end

    function eval_data_sinr()
        if ~(data_tx_active && winner_cts_ok && winner_id > 0)
            return;
        end
        interferers = find(node_state == ST_RTS).';
        interf = 0;
        if ~isempty(interferers)
            interf = sum(ap_rx(winner_id,interferers));
        end
        sinr_db = 10*log10(ap_rx(winner_id,winner_id) / ...
            (noise_w + interf + eps));
        if sinr_db < data_sinr_th
            data_failed = true;
            if strcmp(data_failure_mode,'packet')
                for v = interferers
                    if isnan(data_interferer_start(v))
                        data_interferer_start(v) = t;
                    end
                end
            end
        end
    end
end
