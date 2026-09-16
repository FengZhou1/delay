function raw = simulate_unslotted_engine(mode, trace, scenario, cfg, M, q, seed)
%SIMULATE_UNSLOTTED_ENGINE Shared event-driven continuous-time engine.
% mode = 'unslotted' -> non-slotted p-persistent ALOHA with an
%   exponential retry delay: whenever the HOL queue is non-empty the node
%   draws T ~ Exp(lambda) with lambda = -ln(1-q)/9 per us (the continuous
%   equivalent of Bernoulli(q) at 9 us slot boundaries, so the survival
%   probability at k*9 us equals (1-q)^k).  Transmissions use real
%   durations (RTS=14.5 us, SIFS=16 us, CTS sweep=116.0 us,
%   DATA=M*162.5 us) without any 9 us boundary alignment.  No carrier
%   sensing.
% mode = 'sb_cb'     -> sensing-based connection protocol (modified): the
%   HOL station senses at 9 us tick boundaries and, after a continuous
%   idle of DIFS=34 us, immediately draws Bernoulli(q) and transmits a real
%   RTS.  A busy channel resets the DIFS counter.
% RTS reception uses the classic overlap model.  CTS and DATA use the full
% directional SINR model using the configured CTS and DATA thresholds, with
% NAV from decoded CTS, half-duplex CTS loss, late-RTS interference and
% retry after the SIFS+CTS-sweep timeout.

    TR = scenario.MMW_REAL;
    slot_us = double(TR.SLOT_US);
    rts_us = double(TR.RTS_US);
    sifs_us = double(TR.SIFS_US);
    difs_us = double(TR.DIFS_US);
    cts_us = double(TR.CTS_US);
    cts_sweep_us = double(TR.CTS_SWEEP_US);
    conn_slot_us = double(TR.CONN_OVERHEAD_US);
    if isfield(TR,'DATA_SLOT_US') && ~isempty(TR.DATA_SLOT_US)
        data_slot_us = double(TR.DATA_SLOT_US);
    else
        data_slot_us = conn_slot_us;
    end
    cts_timeout_us = double(TR.CTS_TIMEOUT_US);
    difs_ticks = double(TR.DIFS_TICKS);
    exp_rate_us = -log(1 - q) / slot_us;   % per microsecond
    cts_mode = 'sector_sweep';
    if isfield(cfg,'cts_mode') && ~isempty(cfg.cts_mode)
        cts_mode = lower(char(cfg.cts_mode));
    end
    quasi_omni_ideal = strcmp(cts_mode,'quasi_omni_ideal');
    single_cts_mode = ismember(cts_mode,{'quasi_omni_ideal', ...
        'quasi_omni_physical','quasi_omni_isotropic','directional_winner'});
    if single_cts_mode
        active_cts_us = cts_us;
    else
        active_cts_us = cts_sweep_us;
    end
    data_failure_mode = 'txop';
    if isfield(cfg,'data_failure_mode') && ~isempty(cfg.data_failure_mode)
        data_failure_mode = lower(char(cfg.data_failure_mode));
    end
    if ~ismember(data_failure_mode,{'txop','packet'})
        error('simulate_unslotted_engine:BadFailureMode', ...
            'data_failure_mode must be txop or packet.');
    end

    mode = lower(char(mode));
    if ~ismember(mode, {'unslotted','sb_cb'})
        error('simulate_unslotted_engine:BadMode', ...
            'mode must be unslotted or sb_cb.');
    end
    is_saturation = isfield(cfg,'traffic_mode') && ...
        strcmpi(char(cfg.traffic_mode),'saturation');
    batch_requests = is_batch_txop_mode(cfg) && ~is_saturation;
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
    cts_tx_matrix = [];
    if ismember(cts_mode,{'quasi_omni_physical','quasi_omni_isotropic', ...
            'directional_winner'})
        if ~isfield(PHY,'AP_CTS_Tx_Matrix') || isempty(PHY.AP_CTS_Tx_Matrix)
            error('simulate_unslotted_engine:MissingCtsMatrix', ...
                'AP_CTS_Tx_Matrix is required for physical CTS modes.');
        end
        cts_tx_matrix = PHY.AP_CTS_Tx_Matrix;
    end
    noise_w = 10.^((PHY.NOISE_DBM - 30) / 10);
    sens_w = 10.^((cfg.rx_sens_dbm - 30) / 10);
    cts_sinr_th = PHY.CTS_SINR_TH_DB;
    data_sinr_th = PHY.DATA_SINR_TH_DB;

    % Node state machine constants.
    ST_IDLE = 0; ST_SENSE = 1; ST_READY = 2; ST_RTS = 3; ...
        ST_WAIT = 4; ST_LOCKED = 5; ST_NAV = 7;
    % AP phase constants.
    AP_IDLE = 0; AP_SIFS_PRE = 1; AP_CTS = 2; ...
        AP_SIFS_POST = 3; AP_DATA = 4;

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
    backoff_end = inf(n_nodes,1);
    backoff_remaining = zeros(n_nodes,1);
    rts_end = inf(n_nodes,1);
    wait_timeout = inf(n_nodes,1);
    nav_until = zeros(n_nodes,1);
    sense_count = zeros(n_nodes,1);
    sense_start = nan(n_nodes,1);
    rts_overlap = false(n_nodes,1);
    ap_idle_at_start = false(n_nodes,1);
    attempt_start = nan(n_nodes,1);
    attempt_pid = zeros(n_nodes,1);
    tx_in_sector = false(n_nodes,1);
    cts_min_sinr = inf(n_nodes,1);

    queue_head = ones(n_nodes,1);
    queue_tail = zeros(n_nodes,1);
    queue_count = zeros(n_nodes,1);
    packet_delivered = false(n_packets,1);
    txop_packet_ids = zeros(0,1);
    batch_fill = zeros(n_nodes,1);
    request_count = zeros(n_nodes,1);
    next_arrival = 1;

    ap_phase = AP_IDLE;
    ap_phase_start = 0;
    ap_phase_end = inf;
    current_sector = 0;
    cts_sector_start = 0;
    winner_id = 0;
    winner_cts_ok = false;
    winner_data_start = 0;
    winner_data_end = 0;
    data_tx_active = false;
    data_failed = false;
    data_interferer_start = nan(n_nodes,1);
    data_intervals = zeros(0,2);
    txop_n_packets = 0;
    txop_first_fail = 0;

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
    diagnostics.cts_winner_fail_sinr = 0;
    diagnostics.collision_waste_measure_us = 0;
    diagnostics.payload_success_overlap_us = 0;
    diagnostics.data_failure_mode = data_failure_mode;
    diagnostics.packet_mode_partial_success = 0;
    diagnostics.txop_mode = txop_mode(cfg);
    diagnostics.batch_requests = batch_requests;

    t = 0;
    enqueue_until(t);
    while true
        enqueue_until(t);
        backlog_now = sum(queue_count);
        all_arrivals_seen = next_arrival > n_packets;
        radio_idle = ap_phase == AP_IDLE && ~any(node_state == ST_RTS);
        if batch_requests
            no_contention = sum(request_count) == 0;
        else
            no_contention = backlog_now == 0;
        end
        if all_arrivals_seen && no_contention && radio_idle
            % No arrivals pending, no backlog and no radio activity: no
            % future event exists, so the simulation is finished.
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
        cand = min(cand, min(rts_end));
        cand = min(cand, min(wait_timeout));
        if ap_phase ~= AP_IDLE
            cand = min(cand, ap_phase_end);
            if ap_phase == AP_CTS
                cand = min(cand, cts_sector_start + cts_us);
            end
        end
        if ~isfinite(cand)
            error('simulate_unslotted_engine:NoEvent', ...
                'No event is scheduled; simulation cannot advance.');
        end
        if cand < t
            error('simulate_unslotted_engine:PastEvent', ...
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
        fin = find(rts_end == t).';
        for u = fin
            process_rts_end(u, t);
        end
        if ap_phase == AP_CTS && t == cts_sector_start + cts_us
            process_cts_sector_end(t);
        end
        to = find(wait_timeout == t).';
        for u = to
            process_timeout(u, t);
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
            start_rts(u, t, drawers);
        end
    end

    sim_end_us = t;
    enqueue_until(sim_end_us);
    if ~is_saturation && next_arrival <= n_packets
        error('simulate_unslotted_engine:UnseenArrivals', ...
            'Simulation ended before all arrivals were enqueued.');
    end
    final_backlog = sum(queue_count);
    if isempty(backlog_sample_us) || backlog_sample_us(end) ~= sim_end_us
        backlog_sample_us(end+1,1) = sim_end_us; %#ok<AGROW>
        backlog_sample_n(end+1,1) = final_backlog; %#ok<AGROW>
    end

    if ~is_saturation
        if strcmp(mode,'sb_cb')
            difs_wait_us = attempts * difs_us;
        else
            difs_wait_us = zeros(n_packets,1);
        end
        diagnostics.payload_success_overlap_us = payload_success_overlap_us;
    end
    diagnostics.sim_end_us = sim_end_us;
    diagnostics.cca_mode = 'directional';
    diagnostics.rts_reception_model = 'classic_collision';
    diagnostics.cts_mode = cts_mode;
    if single_cts_mode
        diagnostics.cts_reception_model = cts_mode;
    else
        diagnostics.cts_reception_model = 'sector_scan_half_duplex_plus_sinr';
    end
    diagnostics.data_reception_model = 'directional_sinr';
    diagnostics.cts_sinr_th_db = cts_sinr_th;
    diagnostics.data_sinr_th_db = data_sinr_th;
    structural_censored = false(n_packets, 1);
    if ~is_saturation && batch_requests
        for u = 1:n_nodes
            if batch_fill(u) > 0 && queue_tail(u) >= batch_fill(u)
                first = queue_tail(u) - batch_fill(u) + 1;
                ids = trace.packet_ids_by_node{u}(first:queue_tail(u));
                structural_censored(ids) = true;
            end
        end
    end
    diagnostics.structural_censored = sum(structural_censored);

    raw = struct();
    raw.final_backlog = final_backlog;
    raw.sim_end_us = sim_end_us;
    raw.system_area_measure_us = system_area_measure_us;
    raw.service_area_measure_us = service_area_measure_us;
    raw.payload_success_overlap_us = payload_success_overlap_us;
    raw.backlog_sample_us = backlog_sample_us;
    raw.backlog_sample_n = backlog_sample_n;
    raw.diagnostics = diagnostics;
    raw.structural_censored = structural_censored;
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
        packet_log.busy_nav_wait_us(completed_mask) = ...
            packet_log.completion_us(completed_mask) - ...
            packet_log.hol_us(completed_mask) - ...
            comp_others(completed_mask);
        raw.packet_log = packet_log;
    end

    % ---------------- nested helpers ----------------
    function flag = has_contention(u)
        if batch_requests
            flag = request_count(u) > 0;
        else
            flag = queue_count(u) > 0;
        end
    end

    function pid = head_packet_id(u)
        pid = 0;
        if u < 1 || u > n_nodes || queue_head(u) > queue_tail(u) || ...
                isempty(trace.packet_ids_by_node{u}) || ...
                queue_head(u) > numel(trace.packet_ids_by_node{u})
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

    function enqueue_until(limit_us)
        while next_arrival <= n_packets && ...
                arrival_us(next_arrival) <= limit_us
            pid = next_arrival;
            u = node_id(pid);
            queue_tail(u) = queue_tail(u) + 1;
            queue_count(u) = queue_count(u) + 1;
            if ~batch_requests && queue_count(u) == 1
                if ~is_saturation
                    hol_us(pid) = arrival_us(pid);
                end
                enter_hol(u, arrival_us(pid));
            elseif batch_requests
                if queue_count(u) == 1 && ~is_saturation
                    hol_us(pid) = arrival_us(pid);
                end
                batch_fill(u) = batch_fill(u) + 1;
                if batch_fill(u) >= M
                    batch_fill(u) = 0;
                    request_count(u) = request_count(u) + 1;
                    if request_count(u) == 1
                        enter_hol(u, arrival_us(pid));
                    end
                end
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
        elseif strcmp(mode,'sb_cb')
            % Sensing starts at the next 9 us boundary after the HOL
            % instant; DIFS completes at align_up(sense_start + SIFS) +
            % 2*slot, and the RTS is transmitted at a boundary.
            node_state(u) = ST_SENSE;
            sense_count(u) = 0;
            sense_start(u) = t_hol;
            next_tick(u) = ceil(t_hol / slot_us) * slot_us;
        else
            % Unslotted: draw an exponential retry delay, wait, then send.
            T = -log(rand(stream)) / exp_rate_us;
            node_state(u) = ST_READY;
            backoff_remaining(u) = T;
            if ~is_saturation
                pid = head_packet_id(u);
                if pid > 0
                    probability_wait_us(pid) = probability_wait_us(pid) + T;
                end
            end
            next_tick(u) = t_hol + T;
        end
    end

    function flag = process_tick(u, t_now)
        flag = false;
        if node_state(u) == ST_IDLE
            next_tick(u) = inf;
            return;
        end
        if ~has_contention(u)
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
            if strcmp(mode,'sb_cb')
                node_state(u) = ST_SENSE;
                sense_start(u) = t_now;
                next_tick(u) = ceil(t_now / slot_us) * slot_us;
                sense_count(u) = 0;
                return;
            else
                % Unslotted: NAV ended, draw a fresh exponential delay.
                T = -log(rand(stream)) / exp_rate_us;
                node_state(u) = ST_READY;
                backoff_remaining(u) = T;
                if ~is_saturation
                    pid = head_packet_id(u);
                    if pid > 0
                        probability_wait_us(pid) = probability_wait_us(pid) + T;
                    end
                end
                next_tick(u) = t_now + T;
                return;
            end
            sense_count(u) = 0;
        end
        if node_state(u) == ST_SENSE
            [busy, busy_end] = sense_busy(u, t_now);
            if busy
                % The channel is (or stays) busy: DIFS restarts from the
                % instant the channel becomes idle again.
                sense_count(u) = 0;
                sense_start(u) = busy_end;
                next_tick(u) = ceil(busy_end / slot_us) * slot_us;
                return;
            end
            if t_now >= sense_start(u) + sifs_us
                % DIFS complete: align to the next boundary after
                % (sense_start + SIFS), then count 2 full idle slots.
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
        if strcmp(mode,'sb_cb')
            [busy, busy_end] = sense_busy(u, t_now);
            if busy
                % Channel became busy during this slot: go back to sensing
                % from the busy end.
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
        else
            % Unslotted: backoff timer expired -> send RTS.
            flag = true;
        end
    end

    function start_rts(u, t_now, drawers)
        diagnostics.rts_attempts = diagnostics.rts_attempts + 1;
        if ~is_saturation
            pid = head_packet_id(u);
            if pid > 0
                attempts(pid) = attempts(pid) + 1;
                if isnan(first_attempt_us(pid))
                    first_attempt_us(pid) = t_now;
                end
                attempt_pid(u) = pid;
            else
                attempt_pid(u) = 0;
            end
        else
            attempt_pid(u) = 0;
        end
        attempt_start(u) = t_now;
        node_state(u) = ST_RTS;
        rts_end(u) = t_now + rts_us;
        rts_overlap(u) = false;
        ap_idle_at_start(u) = ap_phase == AP_IDLE;
                sense_count(u) = 0;

        others = find(node_state == ST_RTS).';
        others = others(others ~= u);
        if ~isempty(others)
            rts_overlap(u) = true;
            rts_overlap(others) = true;
        end

        if ap_phase == AP_CTS
            diagnostics.rts_during_cts = diagnostics.rts_during_cts + 1;
            update_cts_sinr(t_now);
        end
        if ap_phase == AP_DATA && data_tx_active
            eval_data_sinr(t_now);
            data_interferer_start(u) = t_now;
        end

        if strcmp(mode,'sb_cb')
            hearers = find( (node_state == ST_SENSE | node_state == ST_READY) & ...
                (1:n_nodes).' ~= u & int_matrix(u,:).' > sens_w & ...
                nav_until <= t_now);
            for v = hearers.'
                if drawers(v)
                    continue;
                end
                node_state(v) = ST_SENSE;

                sense_count(v) = 0;
                sense_start(v) = t_now + rts_us;
                nb = ceil(t_now / slot_us) * slot_us;
                if nb <= t_now; nb = t_now + slot_us; end
                if nb < next_tick(v)
                    next_tick(v) = nb;
                end
            end
        end
    end

    function process_rts_end(u, t_now)
        rts_end(u) = inf;
        if isfinite(data_interferer_start(u))
            data_intervals(end+1,:) = [data_interferer_start(u),t_now]; %#ok<AGROW>
            data_interferer_start(u) = nan;
            if ap_phase == AP_DATA && data_tx_active
                eval_data_sinr(t_now);
            end
        end
        succeeded = ~rts_overlap(u) && ap_idle_at_start(u) && ...
            ap_phase == AP_IDLE;
        if succeeded
            winner_id = u;
            winner_cts_ok = false;
            node_state(u) = ST_LOCKED;
            wait_timeout(u) = t_now + cts_timeout_us;
            ap_phase = AP_SIFS_PRE;
            ap_phase_start = t_now;
            ap_phase_end = t_now + sifs_us;
            winner_data_start = t_now + sifs_us + cts_sweep_us + sifs_us;
            if is_saturation
                txop_n_packets = M;
                txop_packet_ids = zeros(0,1);
            else
                [txop_packet_ids,txop_n_packets] = select_txop_packets(u,M);
            end
            winner_data_end = winner_data_start + txop_n_packets * data_slot_us;
            txop_first_fail = 0;
            diagnostics.rts_success = diagnostics.rts_success + 1;
        else
            node_state(u) = ST_WAIT;
            wait_timeout(u) = t_now + cts_timeout_us;
            diagnostics.rts_fail_total = diagnostics.rts_fail_total + 1;
            if rts_overlap(u)
                diagnostics.rts_fail_collision = ...
                    diagnostics.rts_fail_collision + 1;
            elseif ~ap_idle_at_start(u)
                diagnostics.rts_fail_ap_busy = ...
                    diagnostics.rts_fail_ap_busy + 1;
            end
            diagnostics.collision_waste_us = ...
                diagnostics.collision_waste_us + rts_us;
            diagnostics.collision_waste_measure_us = ...
                diagnostics.collision_waste_measure_us + ...
                interval_overlap_us(t_now - rts_us, t_now, ...
                    left_measure_us, right_measure_us);
        end
        if ap_phase == AP_CTS
            diagnostics.rts_during_cts = diagnostics.rts_during_cts + 1;
            update_cts_sinr(t_now);
        end
        if ap_phase == AP_DATA && data_tx_active
            eval_data_sinr(t_now);
        end
    end

    function process_timeout(u, t_now)
        wait_timeout(u) = inf;
        if node_state(u) == ST_LOCKED
            return;   % winner stays locked until the DATA phase ends
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
        if strcmp(mode,'sb_cb')
            % Re-sense from the timeout instant; DIFS completes at
            % align_up(sense_start + SIFS) + 2*slot, RTS at a boundary.
            node_state(u) = ST_SENSE;
            sense_start(u) = t_now;
            next_tick(u) = ceil(t_now / slot_us) * slot_us;
        else
            % Unslotted: draw a fresh exponential delay after timeout.
            T = -log(rand(stream)) / exp_rate_us;
            node_state(u) = ST_READY;
            backoff_remaining(u) = T;
            if ~is_saturation
                pid = head_packet_id(u);
                if pid > 0
                    probability_wait_us(pid) = probability_wait_us(pid) + T;
                end
            end
            next_tick(u) = t_now + T;
        end
        sense_count(u) = 0;
    end

    function process_cts_sector_end(t_now)
        s = current_sector;
        targets = find(node_sectors == s).';
        for u = targets
            if u == winner_id
                if tx_in_sector(u)
                    winner_cts_ok = false;
                    diagnostics.cts_miss_winner = ...
                        diagnostics.cts_miss_winner + 1;
                else
                    winner_cts_ok = cts_min_sinr(u) >= cts_sinr_th;
                    if winner_cts_ok
                        diagnostics.cts_decoded_winner = ...
                            diagnostics.cts_decoded_winner + 1;
                    else
                        diagnostics.cts_miss_winner = ...
                            diagnostics.cts_miss_winner + 1;
                    end
                end
                if winner_cts_ok
                    wait_timeout(u) = inf;
                end
            else
                if ~tx_in_sector(u) && cts_min_sinr(u) >= cts_sinr_th
                    nav_until(u) = max(nav_until(u), winner_data_end);
                    diagnostics.nav_set = diagnostics.nav_set + 1;
                    if ~is_saturation && attempt_pid(u) > 0
                        pid = attempt_pid(u);
                        collision_delay_us(pid) = ...
                            collision_delay_us(pid) + ...
                            (t_now - attempt_start(u));
                        attempt_pid(u) = 0;
                        attempt_start(u) = nan;
                        wait_timeout(u) = inf;
                    end
                    if node_state(u) == ST_WAIT || ...
                            node_state(u) == ST_SENSE || ...
                            node_state(u) == ST_READY || ...
                            node_state(u) == ST_NAV
                        node_state(u) = ST_NAV;
                                                sense_count(u) = 0;
                        next_tick(u) = winner_data_end;
                        if next_tick(u) <= t_now
                            next_tick(u) = t_now + slot_us;
                        end
                    end
                end
            end
        end
        current_sector = current_sector + 1;
        cts_sector_start = t_now;
        cts_min_sinr(:) = inf;
        tx_in_sector(:) = false;
        if current_sector <= n_sectors
            update_cts_sinr(t_now);
            if strcmp(mode,'sb_cb')
                hearers = find( ...
                    (node_state == ST_SENSE | node_state == ST_READY) & ...
                    ap_sector_tx(:, current_sector) > sens_w & ...
                    nav_until <= t_now);
                for v = hearers.'
                    node_state(v) = ST_SENSE;
    
                    sense_count(v) = 0;
                    nb = ceil(t_now / slot_us) * slot_us;
                    if nb <= t_now; nb = t_now + slot_us; end
                    if nb < next_tick(v)
                        next_tick(v) = nb;
                    end
                end
            end
        end
    end

    function process_single_cts_end(t_now)
        if quasi_omni_ideal
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
        for v = 1:n_nodes
            if v == winner_id || node_state(v) == ST_RTS
                continue;
            end
            decoded = quasi_omni_ideal || cts_min_sinr(v) >= cts_sinr_th;
            if decoded
                nav_until(v) = max(nav_until(v),winner_data_end);
                diagnostics.nav_set = diagnostics.nav_set + 1;
                if strcmp(mode,'sb_cb') && ...
                        ismember(node_state(v),[ST_WAIT,ST_SENSE,ST_READY,ST_NAV])
                    node_state(v) = ST_NAV;
                    sense_count(v) = 0;
                    next_tick(v) = winner_data_end;
                    if next_tick(v) <= t_now
                        next_tick(v) = t_now + slot_us;
                    end
                elseif strcmp(mode,'unslotted')
                    node_state(v) = ST_READY;
                    next_tick(v) = winner_data_end;
                end
            end
        end
    end

    function process_ap_phase_end(t_now)
        switch ap_phase
            case AP_SIFS_PRE
                ap_phase = AP_CTS;
                ap_phase_start = t_now;
                ap_phase_end = t_now + active_cts_us;
                current_sector = 1;
                cts_sector_start = t_now;
                cts_min_sinr(:) = inf;
                tx_in_sector(:) = false;
                update_cts_sinr(t_now);
                if strcmp(mode,'sb_cb') && ~single_cts_mode
                    hearers = find( ...
                        (node_state == ST_SENSE | node_state == ST_READY) & ...
                        ap_sector_tx(:, 1) > sens_w & nav_until <= t_now);
                    for v = hearers.'
                        node_state(v) = ST_SENSE;
        
                        sense_count(v) = 0;
                        sense_start(v) = t_now + cts_us;
                        nb = ceil(t_now / slot_us) * slot_us;
                        if nb <= t_now; nb = t_now + slot_us; end
                        if nb < next_tick(v)
                            next_tick(v) = nb;
                        end
                    end
                end
            case AP_CTS
                if single_cts_mode
                    process_single_cts_end(t_now);
                elseif current_sector >= 1 && current_sector <= n_sectors
                    process_cts_sector_end(t_now);
                end
                ap_phase = AP_SIFS_POST;
                ap_phase_end = t_now + sifs_us;
            case AP_SIFS_POST
                ap_phase = AP_DATA;
                ap_phase_start = t_now;
                ap_phase_end = t_now + txop_n_packets * data_slot_us;
                data_failed = false;
                data_intervals = zeros(0,2);
                data_interferer_start = nan(n_nodes,1);
                if winner_cts_ok && winner_id > 0
                    data_tx_active = true;
                    diagnostics.data_reservations = ...
                        diagnostics.data_reservations + 1;
                    eval_data_sinr(t_now);
                    if strcmp(mode,'sb_cb')
                        hearers = find( ...
                            (node_state == ST_SENSE | ...
                             node_state == ST_READY) & ...
                            int_matrix(winner_id,:).' > sens_w & ...
                            nav_until <= t_now);
                        for v = hearers.'
                            node_state(v) = ST_SENSE;
            
                            sense_count(v) = 0;
                            sense_start(v) = winner_data_end;
                            nb = ceil(t_now / slot_us) * slot_us;
                            if nb <= t_now; nb = t_now + slot_us; end
                            if nb < next_tick(v)
                                next_tick(v) = nb;
                            end
                        end
                    end
                else
                    data_tx_active = false;
                    diagnostics.data_no_cts = ...
                        diagnostics.data_no_cts + 1;
                end
            case AP_DATA
                ongoing = find(isfinite(data_interferer_start)).';
                for uu = ongoing
                    data_intervals(end+1,:) = [ ...
                        data_interferer_start(uu),min(rts_end(uu),t_now)]; %#ok<AGROW>
                    data_interferer_start(uu) = nan;
                end
                n_ok = 0;
                success_mask = false;
                if winner_cts_ok
                    if strcmp(data_failure_mode,'packet')
                        [n_ok,mask] = packet_success_mask(winner_data_start, ...
                            data_slot_us,txop_n_packets,data_intervals);
                        success_mask = mask;
                    elseif ~data_failed
                        if is_saturation
                            success_mask = true;
                            n_ok = txop_n_packets;
                        else
                            success_mask = true(1,numel(txop_packet_ids));
                            n_ok = sum(success_mask);
                        end
                    end
                end
                transaction_success = n_ok > 0;
                if transaction_success
                    if is_saturation
                        if t_now >= left_measure_us && ...
                                t_now < right_measure_us
                            saturation_per_node_completions(winner_id) = ...
                                saturation_per_node_completions(winner_id) + ...
                                n_ok / max(txop_n_packets,eps);
                        end
                    end
                    payload_success_overlap_us = payload_success_overlap_us + ...
                        interval_overlap_us(winner_data_start, ...
                        winner_data_start+n_ok*data_slot_us, ...
                        left_measure_us,right_measure_us);
                    diagnostics.data_success = ...
                        diagnostics.data_success + 1;
                    if strcmp(data_failure_mode,'packet') && ...
                            n_ok < txop_n_packets
                        diagnostics.packet_mode_partial_success = ...
                            diagnostics.packet_mode_partial_success + 1;
                    end
                else
                    if winner_cts_ok
                        diagnostics.data_fail_sinr = ...
                            diagnostics.data_fail_sinr + 1;
                        if ~is_saturation && attempt_pid(winner_id) > 0
                            pid = attempt_pid(winner_id);
                            collision_delay_us(pid) = ...
                                collision_delay_us(pid) + ...
                                (t_now - attempt_start(winner_id));
                        end
                    else
                        diagnostics.data_fail_cts = ...
                            diagnostics.data_fail_cts + 1;
                    end
                end
                if winner_id > 0
                    if ~is_saturation
                        if attempt_pid(winner_id) > 0
                            if transaction_success && ~isempty( ...
                                    trace.packet_ids_by_node{winner_id}) && ...
                                    queue_count(winner_id) > 0
                                complete_successful_packets(success_mask,t_now);
                                if batch_requests
                                    request_count(winner_id) = ...
                                        max(0, request_count(winner_id) - 1);
                                end
                            end
                            attempt_pid(winner_id) = 0;
                            attempt_start(winner_id) = nan;
                        end
                    end
                    wait_timeout(winner_id) = inf;
                    if has_contention(winner_id)
                        if strcmp(mode,'sb_cb')
                            node_state(winner_id) = ST_SENSE;
                            sense_start(winner_id) = t_now;
                            sense_count(winner_id) = 0;
                            next_tick(winner_id) = ceil(t_now / slot_us) * slot_us;
                            if next_tick(winner_id) <= t_now
                                next_tick(winner_id) = t_now + slot_us;
                            end
                        else
                            % Unslotted: the next queued packet immediately
                            % draws a fresh exponential delay.
                            node_state(winner_id) = ST_READY;
                            T = -log(rand(stream)) / exp_rate_us;
                            backoff_remaining(winner_id) = T;
                            if ~is_saturation
                                pid = head_packet_id(winner_id);
                                if pid > 0
                                    probability_wait_us(pid) = ...
                                        probability_wait_us(pid) + T;
                                end
                            end
                            next_tick(winner_id) = t_now + T;
                        end
                    else
                        % No complete request is ready.  The node returns
                        % to IDLE; a future Mth arrival re-enables it.
                        node_state(winner_id) = ST_IDLE;
                        next_tick(winner_id) = inf;
                    end
                    winner_id = 0;
                end
                winner_cts_ok = false;
                data_tx_active = false;
                data_failed = false;
                ap_phase = AP_IDLE;
                ap_phase_start = 0;
                ap_phase_end = inf;
                current_sector = 0;
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

    function pop_head(u, t_now)
        % Monotone head/tail pointers; see simulate_slotted_lightload.
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
        if ap_phase == AP_CTS && current_sector >= 1 && ...
                current_sector <= n_sectors
            if quasi_omni_ideal
                cts_power = inf;
            elseif single_cts_mode && winner_id > 0
                cts_power = cts_tx_matrix(winner_id,u);
            else
                cts_power = ap_sector_tx(u,current_sector);
            end
            if cts_power > sens_w
                busy = true;
                busy_end = min(busy_end, cts_sector_start + active_cts_us);
            end
        end
        if data_tx_active && winner_id > 0 && winner_id ~= u
            if int_matrix(winner_id, u) > sens_w
                busy = true;
                busy_end = min(busy_end, winner_data_end);
            end
        end
        rts_nodes = find(node_state == ST_RTS).';
        for v = rts_nodes
            if v ~= u && int_matrix(v, u) > sens_w
                busy = true;
                busy_end = min(busy_end, rts_end(v));
            end
        end
    end

    function update_cts_sinr(t_now)
        if ap_phase ~= AP_CTS
            return;
        end
        interferers = find(node_state == ST_RTS).';
        if single_cts_mode
            if winner_id <= 0
                return;
            end
            for u = 1:n_nodes
                if node_state(u) == ST_RTS
                    cts_min_sinr(u) = -inf;
                    continue;
                end
                if quasi_omni_ideal
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
            return;
        end
        if current_sector < 1 || current_sector > n_sectors
            return;
        end
        s = current_sector;
        targets = find(node_sectors == s).';
        if isempty(targets)
            return;
        end
        for u = targets
            if node_state(u) == ST_RTS
                tx_in_sector(u) = true;
                continue;
            end
            interf = 0;
            if ~isempty(interferers)
                interf = sum(int_matrix(interferers,u));
            end
            desired = ap_sector_tx(u,s);
            sinr_db = 10*log10(desired / (noise_w + interf + eps));
            cts_min_sinr(u) = min(cts_min_sinr(u),sinr_db);
        end
    end

    function eval_data_sinr(t_now)
        if ~(data_tx_active && winner_cts_ok && winner_id > 0)
            return;
        end
        interferers = find(node_state == ST_RTS).';
        interf = 0;
        if ~isempty(interferers)
            interf = sum(ap_rx(winner_id, interferers));
        end
        desired = ap_rx(winner_id, winner_id);
        sinr_db = 10*log10(desired / (noise_w + interf + eps));
        if sinr_db < data_sinr_th
            data_failed = true;
            if strcmp(data_failure_mode,'packet')
                for v = interferers
                    if isnan(data_interferer_start(v))
                        data_interferer_start(v) = t_now;
                    end
                end
            end
            elapsed = t_now - winner_data_start;
            if elapsed >= 0 && txop_n_packets > 0
                pkt_idx = floor(elapsed / data_slot_us) + 1;
                if pkt_idx >= 1 && pkt_idx <= txop_n_packets
                    if txop_first_fail == 0 || pkt_idx < txop_first_fail
                        txop_first_fail = pkt_idx;
                    end
                end
            end
        end
    end
end
