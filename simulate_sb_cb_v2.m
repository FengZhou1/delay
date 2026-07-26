function result = simulate_sb_cb_v2(trace, scenario, cfg, M, q, seed)
%SIMULATE_SB_CB_V2 Sensing-based, connection-based directional access.
%   result = simulate_sb_cb_v2(trace, scenario, cfg, M, q, seed)
%
% The simulator advances on the common mmWave physical grid. A packet that
% becomes HOL must observe a complete DIFS before its first (or retried)
% p-persistent RTS.  The AP captures at most one RTS while idle, then runs
% SIFS, an eight-sector CTS sweep, SIFS, and one directional data transfer.
% Directional CCA, half-duplex CTS loss, NAV, late RTS interference, and
% per-packet delay accounting are all evaluated on the same timeline.

    TICK_US = double(scenario.MMW.SLOT_TIME_US);
    AP_IDLE = uint8(0);
    AP_SIFS_PRE = uint8(1);
    AP_CTS = uint8(2);
    AP_SIFS_POST = uint8(3);
    AP_DATA = uint8(4);

    if cfg.arrival_tick_us ~= TICK_US
        error('simulate_sb_cb_v2:BadTick', ...
              'SB-CB v2 requires arrival_tick_us = mmw_slot_us.');
    end
    if M < 1 || M ~= round(M)
        error('simulate_sb_cb_v2:BadM', 'M must be a positive integer.');
    end
    if ~isscalar(q) || ~isfinite(q) || q <= 0 || q > 1
        error('simulate_sb_cb_v2:BadQ', 'q must lie in (0,1].');
    end

    n_nodes = cfg.n_nodes;
    n_sectors = cfg.n_sectors;
    if scenario.SYS.N_MLO ~= n_nodes || scenario.SYS.N_SECTORS ~= n_sectors
        error('simulate_sb_cb_v2:ScenarioSize', ...
              'Scenario dimensions do not match cfg.');
    end

    PHY = scenario.PHY;
    MMW = scenario.MMW;
    node_sectors = double(scenario.sectors(:));
    int_matrix = PHY.Int_Matrix;
    ap_rx = PHY.AP_Rx_Matrix;
    ap_sector_tx = PHY.AP_Sector_Tx_Matrix;
    noise_w = 10.^((PHY.NOISE_DBM - 30) / 10);
    sens_w = 10.^((cfg.rx_sens_dbm - 30) / 10);
    ctrl_sinr_th = PHY.CTRL_SINR_TH_DB;
    data_sinr_th = PHY.DATA_SINR_TH_DB;
    collect_diagnostics = true;
    if isfield(cfg,'collect_diagnostics')
        collect_diagnostics = logical(cfg.collect_diagnostics);
    end
    cca_mode = lower(char(cfg.cca_mode));
    need_raw_cca = collect_diagnostics || strcmp(cca_mode,'directional');
    need_counterfactual_cca = collect_diagnostics || strcmp(cca_mode,'oracle');

    difs_us = MMW.DIFS_US;
    rts_us = MMW.RTS_US;
    sifs_us = MMW.SIFS_US;
    cts_us = MMW.CTS_US;
    cts_sweep_us = n_sectors * cts_us;
    tp_us = double(MMW.CONN_OVERHEAD_US) * double(M);
    durations = [difs_us, rts_us, sifs_us, cts_us, tp_us];
    if any(mod(durations, TICK_US) ~= 0)
        error('simulate_sb_cb_v2:NonIntegralDuration', ...
              'All protocol durations must be integer mmWave slots.');
    end
    difs_ticks = round(difs_us / TICK_US);
    rts_ticks = round(rts_us / TICK_US);
    cts_ticks = round(cts_us / TICK_US);
    data_ticks_required = round(tp_us / TICK_US);

    stream = RandStream('mt19937ar', 'Seed', double(seed));

    % Packet log uses the common packet IDs supplied by the arrival trace.
    n_packets = trace.n_packets;
    packet_log = struct();
    packet_log.node_id = double(trace.node_id(:));
    packet_log.arrival_us = double(trace.times_us(:));
    packet_log.hol_us = nan(n_packets, 1);
    packet_log.first_attempt_us = nan(n_packets, 1);
    packet_log.completion_us = nan(n_packets, 1);
    packet_log.attempts = zeros(n_packets, 1);
    packet_log.probability_wait_us = zeros(n_packets, 1);
    collision_delay_accum_us = zeros(n_packets,1);

    queues = cell(n_nodes, 1);
    queue_head = ones(n_nodes, 1);
    queue_len = zeros(n_nodes, 1);
    next_arrival = 1;

    nav_until_us = zeros(n_nodes, 1);
    expected_nav_until_us = zeros(n_nodes, 1);
    locked = false(n_nodes, 1);
    difs_count = zeros(n_nodes, 1);
    prev_sensed_busy = false(n_nodes, 1);
    prev_difs_observe = false(n_nodes, 1);

    % Per-node RTS state.  min SINR is accumulated over the whole RTS.
    rts_active = false(n_nodes, 1);
    rts_remaining = zeros(n_nodes, 1);
    rts_packet_id = zeros(n_nodes, 1);
    rts_started_ap_idle = false(n_nodes, 1);
    rts_ap_idle_all = false(n_nodes, 1);
    rts_min_sinr_db = inf(n_nodes, 1);
    rts_had_overlap = false(n_nodes, 1);
    waiting_cts = false(n_nodes, 1);
    cts_timeout_us = inf(n_nodes, 1);
    attempt_start_us = nan(n_nodes,1);
    attempt_packet_id = zeros(n_nodes,1);

    % AP transaction state.
    ap_state = AP_IDLE;
    ap_phase_end_us = inf;
    cts_start_us = NaN;
    transaction_data_start_us = NaN;
    transaction_data_end_us = NaN;
    winner_id = 0;
    winner_packet_id = 0;
    winner_cts_ok = false;

    cts_listen_ticks = zeros(n_nodes, 1);
    cts_min_sinr_db = inf(n_nodes, 1);
    cts_halfduplex = false(n_nodes, 1);

    data_tx_ticks = 0;
    data_bad_ticks = 0;
    data_measure_overlap_us = 0;
    failed_interval_start_us = zeros(0,1);
    failed_interval_end_us = zeros(0,1);

    diagnostics = initialize_diagnostics();
    diagnostics.rts_start_times_us = zeros(0,1);
    diagnostics.rts_start_nodes = zeros(0,1);

    backlog_sample_us = zeros(0,1);
    backlog_sample_n = zeros(0,1);
    next_backlog_sample_us = 0;
    system_area_measure_us = 0;
    service_area_measure_us = 0;
    payload_success_overlap_us = 0;

    left_measure_us = cfg.warmup_us;
    right_measure_us = cfg.arrival_end_us;
    % Extend by less than one slot so a final grid-aligned arrival is not
    % skipped when the requested experimental horizon is off-grid.
    hard_end_us = ceil(cfg.sim_hard_end_us / TICK_US) * TICK_US;
    t = 0;

    while true
        % Complete or advance an AP phase exactly at the current boundary.
        if ap_state ~= AP_IDLE && t >= ap_phase_end_us
            switch ap_state
                case AP_SIFS_PRE
                    ap_state = AP_CTS;
                    cts_start_us = t;
                    ap_phase_end_us = t + cts_sweep_us;
                    cts_listen_ticks(:) = 0;
                    cts_min_sinr_db(:) = inf;
                    cts_halfduplex(:) = false;

                case AP_CTS
                    ap_state = AP_SIFS_POST;
                    ap_phase_end_us = t + sifs_us;

                case AP_SIFS_POST
                    ap_state = AP_DATA;
                    ap_phase_end_us = t + tp_us;
                    data_tx_ticks = 0;
                    data_bad_ticks = 0;
                    data_measure_overlap_us = 0;
                    diagnostics.data_reservations = diagnostics.data_reservations + 1;
                    if winner_cts_ok
                        diagnostics.data_attempts = diagnostics.data_attempts + 1;
                    else
                        diagnostics.data_no_cts = diagnostics.data_no_cts + 1;
                    end

                case AP_DATA
                    success = winner_cts_ok && ...
                              data_tx_ticks == data_ticks_required && ...
                              data_bad_ticks == 0;
                    diagnostics.data_payload_attempted_us = ...
                        diagnostics.data_payload_attempted_us + data_tx_ticks*TICK_US;
                    if data_bad_ticks > 0
                        diagnostics.data_collision_events = ...
                            diagnostics.data_collision_events + 1;
                        if data_bad_ticks < max(1, data_tx_ticks)
                            diagnostics.data_partial_collision_events = ...
                                diagnostics.data_partial_collision_events + 1;
                        else
                            diagnostics.data_full_collision_events = ...
                                diagnostics.data_full_collision_events + 1;
                        end
                    end

                    if success
                        diagnostics.data_success = diagnostics.data_success + 1;
                        payload_success_overlap_us = payload_success_overlap_us + ...
                                                     data_measure_overlap_us;
                        pid = winner_packet_id;
                        if winner_id <= 0 || queue_len(winner_id) <= 0 || ...
                                head_packet_id(queues, queue_head, winner_id) ~= pid
                            error('simulate_sb_cb_v2:WinnerQueueMismatch', ...
                                  'Winner packet is no longer the queue head.');
                        end
                        packet_log.completion_us(pid) = t;
                        [queues, queue_head, queue_len, packet_log] = ...
                            pop_successful_head(queues, queue_head, queue_len, ...
                                                 packet_log, winner_id, t);
                        attempt_start_us(winner_id) = NaN;
                        attempt_packet_id(winner_id) = 0;
                    else
                        diagnostics.data_fail = diagnostics.data_fail + 1;
                        diagnostics.data_wasted_us = diagnostics.data_wasted_us + tp_us;
                        if winner_cts_ok
                            diagnostics.data_fail_sinr = diagnostics.data_fail_sinr + 1;
                            pid = attempt_packet_id(winner_id);
                            if pid <= 0 || ~isfinite(attempt_start_us(winner_id))
                                error('simulate_sb_cb_v2:MissingAttemptTiming', ...
                                      'Failed data has no active attempt timestamp.');
                            end
                            failed_delay = t-attempt_start_us(winner_id);
                            collision_delay_accum_us(pid) = ...
                                collision_delay_accum_us(pid)+failed_delay;
                            diagnostics.data_failure_transaction_delay_us = ...
                                diagnostics.data_failure_transaction_delay_us+failed_delay;
                            attempt_start_us(winner_id) = NaN;
                            attempt_packet_id(winner_id) = 0;
                            failed_interval_start_us(end+1,1) = ...
                                transaction_data_start_us; %#ok<AGROW>
                            failed_interval_end_us(end+1,1) = t; %#ok<AGROW>
                        else
                            diagnostics.data_fail_cts = diagnostics.data_fail_cts + 1;
                        end
                    end

                    if winner_id > 0
                        locked(winner_id) = false;
                        waiting_cts(winner_id) = false;
                        cts_timeout_us(winner_id) = inf;
                        difs_count(winner_id) = 0;
                        prev_difs_observe(winner_id) = false;
                    end
                    winner_id = 0;
                    winner_packet_id = 0;
                    winner_cts_ok = false;
                    ap_state = AP_IDLE;
                    ap_phase_end_us = inf;
                    cts_start_us = NaN;
                    transaction_data_start_us = NaN;
                    transaction_data_end_us = NaN;
            end
        end

        % Arrivals at a boundary are enqueued before protocol decisions.
        while next_arrival <= n_packets && packet_log.arrival_us(next_arrival) <= t
            if packet_log.arrival_us(next_arrival) < t
                error('simulate_sb_cb_v2:SkippedArrival', ...
                      'An arrival boundary was skipped by the simulator.');
            end
            u = packet_log.node_id(next_arrival);
            if queue_len(u) == 0
                queues{u} = next_arrival;
                queue_head(u) = 1;
                packet_log.hol_us(next_arrival) = t;
            else
                queues{u}(end+1) = next_arrival;
            end
            queue_len(u) = queue_len(u) + 1;
            next_arrival = next_arrival + 1;
        end

        % An RTS sender cannot know at the RTS end whether the AP decoded
        % it.  It remains silent until it either decodes a sector CTS/NAV or
        % the complete SIFS+CTS-sweep response window has elapsed.
        timed_out_cts = waiting_cts & cts_timeout_us <= t;
        if any(timed_out_cts)
            timeout_nodes=find(timed_out_cts).';
            for u=timeout_nodes
                pid=attempt_packet_id(u);
                if pid<=0 || ~isfinite(attempt_start_us(u))
                    error('simulate_sb_cb_v2:MissingAttemptTiming', ...
                          'CTS timeout has no active attempt timestamp.');
                end
                failed_delay=t-attempt_start_us(u);
                collision_delay_accum_us(pid)= ...
                    collision_delay_accum_us(pid)+failed_delay;
                diagnostics.rts_failure_detection_delay_us = ...
                    diagnostics.rts_failure_detection_delay_us+failed_delay;
                attempt_start_us(u)=NaN;
                attempt_packet_id(u)=0;
            end
            diagnostics.rts_response_timeouts = ...
                diagnostics.rts_response_timeouts + sum(timed_out_cts);
            waiting_cts(timed_out_cts) = false;
            cts_timeout_us(timed_out_cts) = inf;
            difs_count(timed_out_cts) = 0;
            prev_difs_observe(timed_out_cts) = false;
        end

        current_backlog = sum(queue_len);
        while next_backlog_sample_us <= t
            backlog_sample_us(end+1,1) = next_backlog_sample_us; %#ok<AGROW>
            backlog_sample_n(end+1,1) = current_backlog; %#ok<AGROW>
            next_backlog_sample_us = next_backlog_sample_us + cfg.stats_sample_us;
        end

        all_arrivals_seen = next_arrival > n_packets;
        all_radio_idle = ap_state == AP_IDLE && ~any(rts_active);
        if t >= cfg.arrival_end_us && all_arrivals_seen && ...
                current_backlog == 0 && all_radio_idle
            break;
        end
        if t >= hard_end_us
            break;
        end
        next_t = min(t + TICK_US, hard_end_us);
        dt = next_t - t;
        if dt <= 0
            break;
        end

        % Full DIFS is required after becoming HOL, after NAV, and after a
        % failed/successful radio attempt.  p-persistent retries need not
        % repeat DIFS while the channel remains continuously clear.
        base_eligible = queue_len > 0 & ~rts_active & ~waiting_cts & ...
                        ~locked & nav_until_us <= t;
        for u = 1:n_nodes
            if base_eligible(u) && prev_difs_observe(u)
                pid = head_packet_id(queues, queue_head, u);
                if packet_log.hol_us(pid) >= t || prev_sensed_busy(u)
                    difs_count(u) = 0;
                else
                    difs_count(u) = min(difs_ticks, difs_count(u) + 1);
                end
            else
                difs_count(u) = 0;
            end
        end

        ready = base_eligible & difs_count >= difs_ticks;
        attempt_draw = rand(stream, n_nodes, 1) < q;
        new_rts = ready & attempt_draw;
        deferred_ready = find(ready & ~new_rts);
        for kk = 1:numel(deferred_ready)
            u = deferred_ready(kk);
            pid = head_packet_id(queues,queue_head,u);
            packet_log.probability_wait_us(pid) = ...
                packet_log.probability_wait_us(pid) + TICK_US;
        end
        active_before = rts_active;
        if any(new_rts)
            starters = find(new_rts).';
            if cfg.collect_debug_trace
                diagnostics.rts_start_times_us = [diagnostics.rts_start_times_us; ...
                    repmat(t,numel(starters),1)]; %#ok<AGROW>
                diagnostics.rts_start_nodes = [diagnostics.rts_start_nodes; ...
                    starters(:)]; %#ok<AGROW>
            end
            for u = starters
                pid = head_packet_id(queues, queue_head, u);
                diagnostics.rts_attempts = diagnostics.rts_attempts + 1;
                packet_log.attempts(pid) = packet_log.attempts(pid) + 1;
                if ~isfinite(packet_log.first_attempt_us(pid))
                    packet_log.first_attempt_us(pid) = t;
                end
                rts_active(u) = true;
                attempt_start_us(u) = t;
                attempt_packet_id(u) = pid;
                rts_remaining(u) = rts_ticks;
                rts_packet_id(u) = pid;
                rts_started_ap_idle(u) = ap_state == AP_IDLE;
                rts_ap_idle_all(u) = ap_state == AP_IDLE;
                rts_min_sinr_db(u) = inf;
                rts_had_overlap(u) = false;
                difs_count(u) = 0;

                if ap_state == AP_SIFS_PRE || ap_state == AP_CTS || ...
                        ap_state == AP_SIFS_POST
                    diagnostics.late_start_handshake = ...
                        diagnostics.late_start_handshake + 1;
                elseif ap_state == AP_DATA
                    diagnostics.late_start_data = diagnostics.late_start_data + 1;
                end
                if t < expected_nav_until_us(u) && nav_until_us(u) <= t
                    diagnostics.nav_protected_violations = ...
                        diagnostics.nav_protected_violations + 1;
                end
            end
        end

        active_rts = rts_active;
        if nnz(active_rts) > 1
            rts_had_overlap(active_rts) = true;
            if nnz(active_before) < 2
                diagnostics.rts_simultaneous_events = ...
                    diagnostics.rts_simultaneous_events + 1;
            end
        end

        % Determine the RF activity over [t,next_t).
        ap_cts_active = ap_state == AP_CTS;
        current_sector = 0;
        if ap_cts_active
            current_sector = min(n_sectors, ...
                floor((t - cts_start_us) / cts_us) + 1);
        end
        data_tx_active = ap_state == AP_DATA && winner_cts_ok && winner_id > 0;
        data_tx_mask = false(n_nodes,1);
        if data_tx_active
            data_tx_mask(winner_id) = true;
        end
        sta_tx_mask = active_rts | data_tx_mask;
        listeners = ~sta_tx_mask;

        if need_raw_cca
            rx_power = zeros(n_nodes,1);
            if any(sta_tx_mask)
                rx_power = sum(int_matrix(sta_tx_mask,:), 1).';
            end
            if ap_cts_active
                rx_power = rx_power + ap_sector_tx(:,current_sector);
            end
            raw_sensed_busy = rx_power > sens_w;
        else
            raw_sensed_busy = false(n_nodes,1);
        end
        raw_rf_busy = any(sta_tx_mask) || ap_cts_active;
        if need_counterfactual_cca
            [harmful_start,self_decodable,control_harm,data_harm,rts_harm] = ...
                counterfactual_rts_truth(listeners,active_rts,ap_state==AP_IDLE, ...
                    ap_cts_active,data_tx_active,current_sector,winner_id, ...
                    node_sectors,rts_min_sinr_db,ap_rx,int_matrix, ...
                    ap_sector_tx,noise_w, ...
                    ctrl_sinr_th,data_sinr_th);
        else
            harmful_start = false(n_nodes,1);
            self_decodable = false(n_nodes,1);
            control_harm = false(n_nodes,1);
            data_harm = false(n_nodes,1);
            rts_harm = false(n_nodes,1);
        end
        switch cca_mode
            case 'directional'
                sensed_busy = raw_sensed_busy;
            case 'oracle'
                sensed_busy = harmful_start;
            case 'disabled'
                sensed_busy = false(n_nodes,1);
            otherwise
                error('simulate_sb_cb_v2:BadCCAMode', ...
                      'Unsupported cfg.cca_mode: %s', cfg.cca_mode);
        end
        sensed_busy(~listeners) = true;

        if collect_diagnostics
            diagnostics.cca_raw_listener_samples = ...
                diagnostics.cca_raw_listener_samples + sum(listeners);
            if raw_rf_busy
                diagnostics.cca_raw_busy_samples = ...
                    diagnostics.cca_raw_busy_samples + sum(listeners);
                diagnostics.cca_raw_miss_samples = ...
                    diagnostics.cca_raw_miss_samples + ...
                    sum(listeners & ~raw_sensed_busy);
            end

            eligible_listeners = base_eligible & listeners;
            diagnostics.cca_eligible_tp = diagnostics.cca_eligible_tp + ...
                sum(eligible_listeners & harmful_start & sensed_busy);
            diagnostics.cca_eligible_fn = diagnostics.cca_eligible_fn + ...
                sum(eligible_listeners & harmful_start & ~sensed_busy);
            diagnostics.cca_eligible_fp = diagnostics.cca_eligible_fp + ...
                sum(eligible_listeners & ~harmful_start & self_decodable & sensed_busy);
            diagnostics.cca_eligible_tn = diagnostics.cca_eligible_tn + ...
                sum(eligible_listeners & ~harmful_start & self_decodable & ~sensed_busy);
            diagnostics.cca_eligible_decodable_negative = ...
                diagnostics.cca_eligible_decodable_negative + ...
                sum(eligible_listeners & ~harmful_start & self_decodable);
            diagnostics.cca_eligible_self_undecodable = ...
                diagnostics.cca_eligible_self_undecodable + ...
                sum(eligible_listeners & ~self_decodable);
            diagnostics.cca_eligible_control_harm = ...
                diagnostics.cca_eligible_control_harm + ...
                sum(eligible_listeners & control_harm);
            diagnostics.cca_eligible_data_harm = ...
                diagnostics.cca_eligible_data_harm + ...
                sum(eligible_listeners & data_harm);
            diagnostics.cca_eligible_rts_harm = ...
                diagnostics.cca_eligible_rts_harm + ...
                sum(eligible_listeners & rts_harm);
        end

        % AP reception of RTSs.  Capture is possible only if the AP stayed
        % idle for the complete RTS.  SINR is accumulated per candidate.
        active_ids = find(active_rts).';
        if ap_state == AP_IDLE
            for u = active_ids
                interferers = active_rts;
                interferers(u) = false;
                desired = ap_rx(u,u);
                interference = sum(ap_rx(u,interferers));
                sinr_db = 10*log10(desired / (noise_w + interference + eps));
                rts_min_sinr_db(u) = min(rts_min_sinr_db(u), sinr_db);
            end
        else
            rts_ap_idle_all(active_rts) = false;
        end

        % Directional CTS reception and half-duplex loss.
        if ap_cts_active
            targets = find(node_sectors == current_sector);
            if ~isempty(targets)
                tx_rts = find(active_rts);
                for kk = 1:numel(targets)
                    u = targets(kk);
                    if rts_active(u)
                        cts_halfduplex(u) = true;
                    else
                        cts_listen_ticks(u) = cts_listen_ticks(u) + 1;
                        interference = 0;
                        if ~isempty(tx_rts)
                            interference = sum(int_matrix(tx_rts,u));
                        end
                        desired = ap_sector_tx(u,current_sector);
                        sinr_db = 10*log10(desired / (noise_w + interference + eps));
                        cts_min_sinr_db(u) = min(cts_min_sinr_db(u), sinr_db);
                    end
                end
            end
        end

        % Data SINR is checked in every mmWave slot so a late RTS can spoil
        % only part of a packet while still causing the whole packet to fail.
        if data_tx_active
            data_tx_ticks = data_tx_ticks + 1;
            interferers = active_rts;
            interference = sum(ap_rx(winner_id,interferers));
            desired = ap_rx(winner_id,winner_id);
            sinr_db = 10*log10(desired / (noise_w + interference + eps));
            if sinr_db < data_sinr_th
                data_bad_ticks = data_bad_ticks + 1;
                diagnostics.data_collision_ticks = diagnostics.data_collision_ticks + 1;
                diagnostics.data_collision_us = diagnostics.data_collision_us + dt;
            end
            if any(active_rts)
                diagnostics.data_late_rts_interference_ticks = ...
                    diagnostics.data_late_rts_interference_ticks + 1;
            end
            data_measure_overlap_us = data_measure_overlap_us + ...
                interval_overlap_us(t, next_t, left_measure_us, right_measure_us);
        end

        overlap = interval_overlap_us(t, next_t, left_measure_us, right_measure_us);
        if overlap > 0
            system_area_measure_us = system_area_measure_us + current_backlog*overlap;
            service_area_measure_us = service_area_measure_us + ...
                                      double(data_tx_active)*overlap;
        end

        % Finish a CTS sector at the end of its fourth minislot.
        if ap_cts_active && mod(t - cts_start_us, cts_us) == cts_us - TICK_US
            targets = find(node_sectors == current_sector);
            for kk = 1:numel(targets)
                u = targets(kk);
                diagnostics.icr_expected = diagnostics.icr_expected + 1;
                decoded = false;
                if cts_halfduplex(u)
                    diagnostics.icr_miss_halfduplex = ...
                        diagnostics.icr_miss_halfduplex + 1;
                elseif cts_listen_ticks(u) < cts_ticks
                    diagnostics.icr_miss_timing = diagnostics.icr_miss_timing + 1;
                elseif cts_min_sinr_db(u) < ctrl_sinr_th
                    diagnostics.icr_miss_low_sinr = ...
                        diagnostics.icr_miss_low_sinr + 1;
                else
                    decoded = true;
                    diagnostics.icr_decoded = diagnostics.icr_decoded + 1;
                end

                if u == winner_id
                    winner_cts_ok = decoded;
                    if ~decoded
                        diagnostics.icr_winner_miss = ...
                            diagnostics.icr_winner_miss + 1;
                    elseif waiting_cts(u)
                        waiting_cts(u) = false;
                        cts_timeout_us(u) = inf;
                        diagnostics.rts_response_cts_success = ...
                            diagnostics.rts_response_cts_success + 1;
                    end
                else
                    diagnostics.nav_expected = diagnostics.nav_expected + 1;
                    expected_nav_until_us(u) = max(expected_nav_until_us(u), ...
                                                   transaction_data_end_us);
                    if decoded
                        nav_until_us(u) = max(nav_until_us(u), transaction_data_end_us);
                        diagnostics.nav_set = diagnostics.nav_set + 1;
                        if waiting_cts(u)
                            pid=attempt_packet_id(u);
                            if pid<=0 || ~isfinite(attempt_start_us(u))
                                error('simulate_sb_cb_v2:MissingAttemptTiming', ...
                                      'NAV release has no active attempt timestamp.');
                            end
                            failed_delay=next_t-attempt_start_us(u);
                            collision_delay_accum_us(pid)= ...
                                collision_delay_accum_us(pid)+failed_delay;
                            diagnostics.rts_failure_detection_delay_us = ...
                                diagnostics.rts_failure_detection_delay_us+failed_delay;
                            attempt_start_us(u)=NaN;
                            attempt_packet_id(u)=0;
                            waiting_cts(u) = false;
                            cts_timeout_us(u) = inf;
                            difs_count(u) = 0;
                            prev_difs_observe(u) = false;
                            diagnostics.rts_response_nav_releases = ...
                                diagnostics.rts_response_nav_releases + 1;
                        end
                    else
                        diagnostics.nav_fail = diagnostics.nav_fail + 1;
                    end
                end
            end
        end

        % The current physical interval becomes the previous CCA sample at
        % the next boundary.  Transmitters and NAV-protected nodes cannot
        % accumulate DIFS during this interval.
        prev_sensed_busy = sensed_busy;
        prev_difs_observe = queue_len > 0 & listeners & ~locked & ...
                            nav_until_us <= t;

        % Advance RTS timers and perform strongest-signal SINR capture at
        % the common completion boundary.
        rts_remaining(active_rts) = rts_remaining(active_rts) - 1;
        finishing = rts_active & rts_remaining == 0;
        captured = 0;
        if any(finishing) && ap_state == AP_IDLE
            candidates = find(finishing & rts_started_ap_idle & ...
                              rts_ap_idle_all & ...
                              rts_min_sinr_db >= ctrl_sinr_th);
            if ~isempty(candidates)
                desired = diag(ap_rx);
                [~, strongest_pos] = max(desired(candidates));
                captured = candidates(strongest_pos);
            end
        end

        finishers = find(finishing).';
        for u = finishers
            waiting_cts(u) = true;
            cts_timeout_us(u) = next_t + sifs_us + cts_sweep_us;
            diagnostics.rts_response_wait_entries = ...
                diagnostics.rts_response_wait_entries + 1;
            if rts_had_overlap(u)
                diagnostics.rts_simultaneous_attempts = ...
                    diagnostics.rts_simultaneous_attempts + 1;
            end
            if u == captured
                diagnostics.rts_capture_success = diagnostics.rts_capture_success + 1;
                if rts_had_overlap(u)
                    diagnostics.rts_capture_with_overlap = ...
                        diagnostics.rts_capture_with_overlap + 1;
                end
            else
                diagnostics.rts_fail_total = diagnostics.rts_fail_total + 1;
                failed_interval_start_us(end+1,1) = next_t-rts_us; %#ok<AGROW>
                failed_interval_end_us(end+1,1) = next_t; %#ok<AGROW>
                if ~rts_started_ap_idle(u)
                    diagnostics.rts_fail_ap_busy_start = ...
                        diagnostics.rts_fail_ap_busy_start + 1;
                elseif ~rts_ap_idle_all(u)
                    diagnostics.rts_fail_ap_became_busy = ...
                        diagnostics.rts_fail_ap_became_busy + 1;
                elseif rts_min_sinr_db(u) < ctrl_sinr_th
                    diagnostics.rts_fail_sinr = diagnostics.rts_fail_sinr + 1;
                else
                    diagnostics.rts_fail_capture_lost = ...
                        diagnostics.rts_fail_capture_lost + 1;
                end
            end
            rts_active(u) = false;
            rts_remaining(u) = 0;
            rts_packet_id(u) = 0;
            rts_started_ap_idle(u) = false;
            rts_ap_idle_all(u) = false;
            rts_min_sinr_db(u) = inf;
            rts_had_overlap(u) = false;
            difs_count(u) = 0;
            prev_difs_observe(u) = false;
        end

        if captured > 0
            if ap_state ~= AP_IDLE
                error('simulate_sb_cb_v2:ConcurrentAPTransaction', ...
                      'An RTS was captured while the AP was not idle.');
            end
            winner_id = captured;
            winner_packet_id = head_packet_id(queues, queue_head, captured);
            if winner_packet_id <= 0
                error('simulate_sb_cb_v2:CapturedEmptyQueue', ...
                      'Captured RTS has no HOL packet.');
            end
            locked(captured) = true;
            winner_cts_ok = false;
            ap_state = AP_SIFS_PRE;
            ap_phase_end_us = next_t + sifs_us;
            transaction_data_start_us = next_t + sifs_us + cts_sweep_us + sifs_us;
            transaction_data_end_us = transaction_data_start_us + tp_us;
        end

        t = next_t;
    end

    sim_end_us = t;
    final_backlog = sum(queue_len);
    if isempty(backlog_sample_us) || backlog_sample_us(end) ~= sim_end_us
        backlog_sample_us(end+1,1) = sim_end_us;
        backlog_sample_n(end+1,1) = final_backlog;
    end

    diagnostics.cca_raw_miss_rate = safe_ratio( ...
        diagnostics.cca_raw_miss_samples, diagnostics.cca_raw_busy_samples);
    diagnostics.cca_eligible_tpr = safe_ratio( ...
        diagnostics.cca_eligible_tp, ...
        diagnostics.cca_eligible_tp + diagnostics.cca_eligible_fn);
    diagnostics.cca_eligible_fnr = safe_ratio( ...
        diagnostics.cca_eligible_fn, ...
        diagnostics.cca_eligible_tp + diagnostics.cca_eligible_fn);
    diagnostics.cca_eligible_fpr = safe_ratio( ...
        diagnostics.cca_eligible_fp, ...
        diagnostics.cca_eligible_fp + diagnostics.cca_eligible_tn);
    diagnostics.cca_eligible_tnr = safe_ratio( ...
        diagnostics.cca_eligible_tn, ...
        diagnostics.cca_eligible_fp + diagnostics.cca_eligible_tn);
    diagnostics.harmful_missed_opportunities = diagnostics.cca_eligible_fn;
    diagnostics.false_alarm_opportunities = diagnostics.cca_eligible_fp;
    diagnostics.rts_capture_rate = safe_ratio( ...
        diagnostics.rts_capture_success, diagnostics.rts_attempts);
    diagnostics.icr_miss_rate = safe_ratio( ...
        diagnostics.icr_expected - diagnostics.icr_decoded, ...
        diagnostics.icr_expected);
    diagnostics.nav_set_rate = safe_ratio( ...
        diagnostics.nav_set, diagnostics.nav_expected);
    diagnostics.seed = double(seed);
    diagnostics.cca_mode = char(cfg.cca_mode);
    diagnostics.tp_us = tp_us;
    diagnostics.rts_wasted_us = diagnostics.rts_fail_total * rts_us;
    diagnostics.collision_tx_airtime_us = sum(max(0, ...
        failed_interval_end_us-failed_interval_start_us));
    diagnostics.collision_channel_time_us = interval_union_length( ...
        failed_interval_start_us,failed_interval_end_us,-Inf,Inf);
    diagnostics.collision_tx_airtime_measure_us = sum(max(0, ...
        min(failed_interval_end_us,right_measure_us) - ...
        max(failed_interval_start_us,left_measure_us)));
    diagnostics.collision_channel_time_measure_us = interval_union_length( ...
        failed_interval_start_us,failed_interval_end_us, ...
        left_measure_us,right_measure_us);
    diagnostics.collision_waste_us = diagnostics.collision_tx_airtime_us;
    diagnostics.reservation_waste_us = diagnostics.data_wasted_us;
    diagnostics.service_area_definition = ...
        'active reserved payload transmitter area';

    completed_mask = isfinite(packet_log.completion_us);
    packet_log.boundary_wait_us = zeros(n_packets,1);
    packet_log.difs_wait_us = packet_log.attempts * difs_us;
    packet_log.collision_delay_us = collision_delay_accum_us;
    packet_log.control_delay_us = zeros(n_packets,1);
    packet_log.control_delay_us(completed_mask) = ...
        rts_us + sifs_us + cts_sweep_us + sifs_us;
    packet_log.data_delay_us = zeros(n_packets,1);
    packet_log.data_delay_us(completed_mask) = tp_us;
    component_sum = packet_log.difs_wait_us + ...
        packet_log.probability_wait_us + packet_log.collision_delay_us + ...
        packet_log.control_delay_us + packet_log.data_delay_us;
    packet_log.busy_nav_wait_us = zeros(n_packets,1);
    packet_log.busy_nav_wait_us(completed_mask) = max(0, ...
        packet_log.completion_us(completed_mask) - ...
        packet_log.hol_us(completed_mask) - component_sum(completed_mask));
    packet_log.other_access_delay_us = zeros(n_packets,1);

    raw = struct();
    raw.packet_log = packet_log;
    raw.final_backlog = final_backlog;
    raw.sim_end_us = sim_end_us;
    raw.system_area_measure_us = system_area_measure_us;
    raw.service_area_measure_us = service_area_measure_us;
    raw.payload_success_overlap_us = payload_success_overlap_us;
    raw.backlog_sample_us = backlog_sample_us;
    raw.backlog_sample_n = backlog_sample_n;
    raw.diagnostics = diagnostics;

    result = finalize_sim_result(raw, trace, cfg, 'sb_cb', M, q);
end

function [harmful,self_decodable,control_harm,data_harm,rts_harm] = ...
        counterfactual_rts_truth(listeners,active_rts,ap_idle,ap_cts_active, ...
        data_tx_active,current_sector,winner_id,node_sectors,rts_min_sinr_db, ...
        ap_rx,int_matrix,ap_sector_tx,noise_w,ctrl_th_db,data_th_db)
% Per-listener counterfactual truth for an RTS starting in this interval.
% A start is harmful only when it changes an existing decodable RTS, CTS,
% or data reception into an undecodable one.  Own-link decodability is kept
% separate so an ordinary, harmless carrier-sense indication can be counted
% as a false positive only when the hypothetical RTS itself could succeed.
    n_nodes = numel(listeners);
    harmful = false(n_nodes,1);
    self_decodable = false(n_nodes,1);
    control_harm = false(n_nodes,1);
    data_harm = false(n_nodes,1);
    rts_harm = false(n_nodes,1);
    candidates = find(listeners);
    active_ids = find(active_rts).';

    if ap_idle
        if ~isempty(candidates)
            own_interference = sum(ap_rx(candidates,active_ids),2);
            own_desired = ap_rx(sub2ind(size(ap_rx),candidates,candidates));
            own_sinr_db = 10*log10(own_desired ./ ...
                (noise_w+own_interference+eps));
            self_decodable(candidates) = own_sinr_db >= ctrl_th_db;
        end
        for u = active_ids
            if rts_min_sinr_db(u) < ctrl_th_db
                continue;
            end
            other = active_rts;
            other(u) = false;
            base_interference = sum(ap_rx(u,other));
            before_db = 10*log10(ap_rx(u,u) / ...
                (noise_w+base_interference+eps));
            if before_db < ctrl_th_db
                continue;
            end
            if ~isempty(candidates)
                after_db = 10*log10(ap_rx(u,u) ./ ...
                    (noise_w+base_interference+ap_rx(u,candidates).'+eps));
                rts_harm(candidates) = rts_harm(candidates) | ...
                    (after_db < ctrl_th_db);
            end
        end
    end

    if data_tx_active && winner_id > 0
        base_interference = sum(ap_rx(winner_id,active_rts));
        before_db = 10*log10(ap_rx(winner_id,winner_id) / ...
            (noise_w+base_interference+eps));
        if before_db >= data_th_db && ~isempty(candidates)
            after_db = 10*log10(ap_rx(winner_id,winner_id) ./ ...
                (noise_w+base_interference+ap_rx(winner_id,candidates).'+eps));
            data_harm(candidates) = after_db < data_th_db;
        end
    end

    if ap_cts_active && current_sector > 0
        targets = find(node_sectors==current_sector & ~active_rts).';
        for u = targets
            base_interference = sum(int_matrix(active_rts,u));
            desired = ap_sector_tx(u,current_sector);
            before_db = 10*log10(desired/(noise_w+base_interference+eps));
            if before_db < ctrl_th_db
                continue;
            end
            if ~isempty(candidates)
                after_db = 10*log10(desired ./ ...
                    (noise_w+base_interference+int_matrix(candidates,u)+eps));
                harmed = after_db < ctrl_th_db;
                harmed(candidates==u) = true; % half-duplex CTS loss
                control_harm(candidates) = control_harm(candidates) | harmed;
            end
        end
    end

    harmful = rts_harm | control_harm | data_harm;
end

function diagnostics = initialize_diagnostics()
    names = { ...
        'cca_raw_listener_samples','cca_raw_busy_samples','cca_raw_miss_samples', ...
        'cca_eligible_tp','cca_eligible_fn','cca_eligible_fp','cca_eligible_tn', ...
        'cca_eligible_self_undecodable','cca_eligible_control_harm', ...
        'cca_eligible_data_harm','cca_eligible_rts_harm', ...
        'cca_eligible_decodable_negative', ...
        'rts_attempts','rts_simultaneous_attempts','rts_simultaneous_events', ...
        'rts_capture_success','rts_capture_with_overlap','rts_fail_total', ...
        'rts_fail_ap_busy_start','rts_fail_ap_became_busy','rts_fail_sinr', ...
        'rts_fail_capture_lost','rts_response_wait_entries', ...
        'rts_response_timeouts','rts_response_nav_releases', ...
        'rts_response_cts_success','rts_failure_detection_delay_us', ...
        'late_start_handshake','late_start_data', ...
        'icr_expected','icr_decoded','icr_miss_halfduplex', ...
        'icr_miss_low_sinr','icr_miss_timing','icr_winner_miss', ...
        'nav_expected','nav_set','nav_fail','nav_protected_violations', ...
        'data_reservations','data_attempts','data_no_cts','data_success', ...
        'data_fail','data_fail_sinr','data_fail_cts', ...
        'data_failure_transaction_delay_us', ...
        'data_collision_events','data_partial_collision_events', ...
        'data_full_collision_events','data_collision_ticks','data_collision_us', ...
        'data_late_rts_interference_ticks','data_payload_attempted_us', ...
        'data_wasted_us'};
    diagnostics = struct();
    for i = 1:numel(names)
        diagnostics.(names{i}) = 0;
    end
end

function pid = head_packet_id(queues, queue_head, u)
    if isempty(queues{u}) || queue_head(u) > numel(queues{u})
        pid = 0;
    else
        pid = queues{u}(queue_head(u));
    end
end

function [queues, queue_head, queue_len, packet_log] = pop_successful_head( ...
        queues, queue_head, queue_len, packet_log, u, completion_us)
    queue_len(u) = queue_len(u) - 1;
    if queue_len(u) == 0
        queues{u} = [];
        queue_head(u) = 1;
    else
        queue_head(u) = queue_head(u) + 1;
        next_pid = queues{u}(queue_head(u));
        packet_log.hol_us(next_pid) = completion_us;
    end
end

function value = safe_ratio(num, den)
    if den > 0
        value = num / den;
    else
        value = NaN;
    end
end

function total=interval_union_length(starts,ends,left,right)
    starts=starts(:);
    ends=ends(:);
    if isempty(starts) || isempty(ends)
        total=0;
        return;
    end
    if numel(starts)~=numel(ends)
        error('simulate_sb_cb_v2:IntervalLengthMismatch', ...
            'Failed-interval start/end vectors must have equal length.');
    end
    starts=max(starts,left);
    ends=min(ends,right);
    keep=ends>starts;
    if ~any(keep)
        total=0;
        return;
    end
    intervals=sortrows([starts(keep),ends(keep)],1);
    total=0;
    current_start=intervals(1,1);
    current_end=intervals(1,2);
    for i=2:size(intervals,1)
        if intervals(i,1)<=current_end
            current_end=max(current_end,intervals(i,2));
        else
            total=total+current_end-current_start;
            current_start=intervals(i,1);
            current_end=intervals(i,2);
        end
    end
    total=total+current_end-current_start;
end
