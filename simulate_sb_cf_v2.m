function result = simulate_sb_cf_v2(trace, scenario, cfg, M, q, seed)
%SIMULATE_SB_CF_V2 Connection-free directional CSMA on a 5-us state machine.
%   result = simulate_sb_cf_v2(trace, scenario, cfg, M, q, seed)
%
% Timing rules used here are intentionally explicit:
%   * a new HOL packet starts with zero DIFS credit;
%   * the next HOL after a success starts with zero DIFS credit;
%   * a failed transmission retries only after a fresh full DIFS;
%   * arrivals at a 5-us boundary are enqueued before that boundary's
%     access decision;
%   * a successful data frame completes at the end of its last 5-us slot;
%   * there is no ACK airtime.
%
% CCA modes:
%   directional - local received energy is compared with the CCA threshold;
%   oracle      - CCA exactly follows the harmful-transmission ground truth;
%   disabled    - CCA always reports idle.
%
% The AP locks to at most one frame.  When several stations start at the
% same boundary, the station with the strongest expected AP power is the
% only capture candidate.  It is accepted only if its first-slot SINR meets
% the data threshold.  Its SINR is checked again in every occupied slot.

    validate_inputs(trace, scenario, cfg, M, q);

    protocol = 'sb_cf';
    dt_us = 5;
    n_nodes = cfg.n_nodes;
    Tp_us = 190 * double(M);
    n_data_slots = round(Tp_us / dt_us);
    if abs(n_data_slots * dt_us - Tp_us) > 1e-9
        error('simulate_sb_cf_v2:NonIntegralPayload', ...
              'Tp must be an integer number of 5-us state-machine slots.');
    end

    difs_us = double(scenario.MMW.DIFS_US);
    if abs(difs_us / dt_us - round(difs_us / dt_us)) > 1e-9
        error('simulate_sb_cf_v2:NonIntegralDIFS', ...
              'DIFS must be an integer number of 5-us slots.');
    end

    phy = scenario.PHY;
    int_matrix = phy.Int_Matrix;       % (transmitter, listener)
    ap_rx = phy.AP_Rx_Matrix;          % (desired STA, transmitting STA)
    desired_ap_power = diag(ap_rx);
    noise_w = 10.^((double(phy.NOISE_DBM) - 30) / 10);
    data_sinr_linear = 10.^(double(phy.DATA_SINR_TH_DB) / 10);
    cca_threshold_w = 10.^((double(cfg.rx_sens_dbm) - 30) / 10);
    cca_mode = lower(char(cfg.cca_mode));

    stream = RandStream('mt19937ar', 'Seed', double(seed));

    % Unified packet log.  Non-HOL and unfinished packets retain NaN for
    % timestamps that have not occurred by the hard stop.
    n_packets = trace.n_packets;
    pkt = struct();
    pkt.node_id = double(trace.node_id(:));
    pkt.arrival_us = double(trace.times_us(:));
    pkt.hol_us = nan(n_packets, 1);
    pkt.first_attempt_us = nan(n_packets, 1);
    pkt.completion_us = nan(n_packets, 1);
    pkt.attempts = zeros(n_packets, 1);
    pkt.probability_wait_us = zeros(n_packets, 1);

    % Intrusive per-node FIFO.  Packet ids are already stable indices into
    % the unified log, so linking them avoids the O(queue length) copy made
    % by queues{u}(1)=[] after every successful transmission.
    queue_head = zeros(n_nodes, 1);
    queue_tail = zeros(n_nodes, 1);
    queue_next = zeros(n_packets, 1);
    has_packet = false(n_nodes, 1);
    difs_elapsed_us = zeros(n_nodes, 1);

    tx_active = false(n_nodes, 1);
    tx_remaining_slots = zeros(n_nodes, 1);
    tx_packet_id = zeros(n_nodes, 1);
    tx_start_us = nan(n_nodes, 1);
    tx_failed = false(n_nodes, 1);

    ap_lock = 0;
    ap_lock_was_capture = false;

    % CCA and harmful-start truth depend only on the set/state of active
    % transmitters.  A frame occupies tens to hundreds of 5-us slots, so
    % cache these vectors until a start, finish, or lock failure changes
    % that state.  Per-slot counters are still accumulated below.
    cca_cache_valid = false;
    cached_active_before = zeros(0,1);
    cached_listeners = true(n_nodes,1);
    cached_raw_directional_busy = false(n_nodes,1);
    cached_harmful = false(n_nodes,1);
    cached_sinr_harmful = false(n_nodes,1);
    cached_self_undecodable = false(n_nodes,1);
    cached_single_user_only = false(n_nodes,1);

    diagnostics = initialise_diagnostics(cca_mode, seed, Tp_us, difs_us);
    % These counters are touched on almost every 5-us boundary.  Keep them
    % as local scalars in the hot loop and publish them to diagnostics once.
    d_raw_busy_opp = 0;
    d_raw_misses = 0;
    d_eligible_tp = 0;
    d_eligible_fn = 0;
    d_eligible_fp = 0;
    d_eligible_tn = 0;
    d_ready_tp = 0;
    d_ready_fn = 0;
    d_ready_fp = 0;
    d_ready_tn = 0;
    d_eligible_sinr_harmful = 0;
    d_eligible_self_undecodable = 0;
    d_eligible_single_user_only = 0;
    d_ready_sinr_harmful = 0;
    d_ready_self_undecodable = 0;
    d_ready_single_user_only = 0;
    d_overlap_time_us = 0;
    d_excess_airtime_us = 0;

    arrival_index = 1;
    backlog_n = 0;
    completed_n = 0;
    system_area_measure_us = 0;
    service_area_measure_us = 0;
    payload_success_overlap_us = 0;
    failed_capacity = max(1024, 4 * n_packets);
    failed_interval_start_us = zeros(failed_capacity,1);
    failed_interval_end_us = zeros(failed_capacity,1);
    failed_interval_count = 0;

    sample_period_us = double(cfg.stats_sample_us);
    if ~isfinite(sample_period_us) || sample_period_us <= 0
        sample_period_us = dt_us;
    end
    next_sample_us = 0;

    measurement_left_us = double(cfg.warmup_us);
    measurement_right_us = double(cfg.arrival_end_us);
    hard_end_us = double(cfg.sim_hard_end_us);
    if isfield(trace, 'hard_end_us')
        hard_end_us = min(hard_end_us, double(trace.hard_end_us));
    end
    if abs(hard_end_us / dt_us - round(hard_end_us / dt_us)) > 1e-9
        error('simulate_sb_cf_v2:NonIntegralHorizon', ...
              'The hard horizon must be an integer number of 5-us slots.');
    end
    sample_capacity = max(1, ceil(hard_end_us / sample_period_us) + 2);
    backlog_sample_us = zeros(sample_capacity,1);
    backlog_sample_n = zeros(sample_capacity,1);
    backlog_sample_count = 0;

    t_us = 0;
    while t_us < hard_end_us
        % Arrivals at this boundary are visible to this boundary's decision.
        while arrival_index <= n_packets && ...
                pkt.arrival_us(arrival_index) <= t_us + 1e-9
            if pkt.arrival_us(arrival_index) < t_us - 1e-9
                error('simulate_sb_cf_v2:ArrivalOffGrid', ...
                      'An arrival was skipped by the 5-us state machine.');
            end
            u = pkt.node_id(arrival_index);
            if u < 1 || u > n_nodes || u ~= round(u)
                error('simulate_sb_cf_v2:BadNodeId', ...
                      'Arrival trace contains an invalid node id.');
            end
            was_empty = ~has_packet(u);
            if was_empty
                queue_head(u) = arrival_index;
            else
                queue_next(queue_tail(u)) = arrival_index;
            end
            queue_tail(u) = arrival_index;
            has_packet(u) = true;
            backlog_n = backlog_n + 1;
            if was_empty
                pkt.hol_us(arrival_index) = t_us;
                difs_elapsed_us(u) = 0;
            end
            arrival_index = arrival_index + 1;
        end

        while next_sample_us <= t_us + 1e-9
            backlog_sample_count = backlog_sample_count + 1;
            backlog_sample_us(backlog_sample_count) = t_us;
            backlog_sample_n(backlog_sample_count) = backlog_n;
            next_sample_us = next_sample_us + sample_period_us;
        end

        if t_us >= measurement_right_us && backlog_n == 0 && ...
                arrival_index > n_packets
            break;
        end

        % No protocol state can change before the next arrival when the
        % system is empty.  Jump across that interval, but advance the
        % private stream by exactly the same 40 random variates per skipped
        % slot as the ordinary loop.  This preserves every later attempt.
        if backlog_n == 0 && arrival_index <= n_packets
            next_arrival_us = pkt.arrival_us(arrival_index);
            skip_slots = round((next_arrival_us - t_us) / dt_us);
            if skip_slots > 0
                remaining_skip = skip_slots;
                while remaining_skip > 0
                    draw_slots = min(remaining_skip, 10000);
                    rand(stream, n_nodes, draw_slots);
                    remaining_skip = remaining_skip - draw_slots;
                end
                while next_sample_us < next_arrival_us - 1e-9
                    recorded_sample_us = ...
                        ceil((next_sample_us - 1e-9) / dt_us) * dt_us;
                    if recorded_sample_us >= next_arrival_us - 1e-9
                        break;
                    end
                    backlog_sample_count = backlog_sample_count + 1;
                    backlog_sample_us(backlog_sample_count) = recorded_sample_us;
                    backlog_sample_n(backlog_sample_count) = 0;
                    next_sample_us = next_sample_us + sample_period_us;
                end
                t_us = next_arrival_us;
                continue;
            end
        end

        % CCA is evaluated from transmissions already in progress at the
        % boundary.  A newly starting simultaneous transmission is handled
        % by the AP capture rule below.
        if cca_cache_valid
            active_before = cached_active_before;
            listeners = cached_listeners;
            raw_directional_busy = cached_raw_directional_busy;
            harmful = cached_harmful;
            sinr_harmful = cached_sinr_harmful;
            self_undecodable = cached_self_undecodable;
            single_user_only = cached_single_user_only;
        else
            active_before = find(tx_active);
            listeners = ~tx_active;
            if isempty(active_before)
                raw_directional_busy = false(n_nodes, 1);
            else
                listener_power = sum(int_matrix(active_before, :), 1).';
                raw_directional_busy = listener_power > cca_threshold_w;
            end
            [harmful, sinr_harmful, self_undecodable, single_user_only] = ...
                harmful_if_started(n_nodes, active_before, ap_lock, ...
                    tx_failed, ap_rx, desired_ap_power, noise_w, data_sinr_linear);
            cached_active_before = active_before;
            cached_listeners = listeners;
            cached_raw_directional_busy = raw_directional_busy;
            cached_harmful = harmful;
            cached_sinr_harmful = sinr_harmful;
            cached_self_undecodable = self_undecodable;
            cached_single_user_only = single_user_only;
            cca_cache_valid = true;
        end
        if ~isempty(active_before)
            d_raw_busy_opp = d_raw_busy_opp + sum(listeners);
            d_raw_misses = d_raw_misses + ...
                sum(listeners & ~raw_directional_busy);
        end

        switch cca_mode
            case 'directional'
                cca_busy = raw_directional_busy;
            case 'oracle'
                cca_busy = harmful;
            case 'disabled'
                cca_busy = false(n_nodes, 1);
            otherwise
                error('simulate_sb_cf_v2:BadCcaMode', ...
                      'Unknown CCA mode: %s', cca_mode);
        end
        cca_busy(tx_active) = true;

        % "Eligible CCA" means a non-transmitting node with a HOL packet.
        % A second ready-only confusion matrix is retained so analyses can
        % distinguish DIFS accumulation from an actual transmission choice.
        eligible_cca = listeners & has_packet;
        d_eligible_sinr_harmful = d_eligible_sinr_harmful + ...
            sum(eligible_cca & sinr_harmful);
        d_eligible_self_undecodable = d_eligible_self_undecodable + ...
            sum(eligible_cca & self_undecodable);
        d_eligible_single_user_only = d_eligible_single_user_only + ...
            sum(eligible_cca & single_user_only);
        d_eligible_tp = d_eligible_tp + sum(eligible_cca & harmful & cca_busy);
        d_eligible_fn = d_eligible_fn + sum(eligible_cca & harmful & ~cca_busy);
        d_eligible_fp = d_eligible_fp + sum(eligible_cca & ~harmful & cca_busy);
        d_eligible_tn = d_eligible_tn + sum(eligible_cca & ~harmful & ~cca_busy);
        ready_cca = eligible_cca & (difs_elapsed_us >= difs_us);
        d_ready_sinr_harmful = d_ready_sinr_harmful + ...
            sum(ready_cca & sinr_harmful);
        d_ready_self_undecodable = d_ready_self_undecodable + ...
            sum(ready_cca & self_undecodable);
        d_ready_single_user_only = d_ready_single_user_only + ...
            sum(ready_cca & single_user_only);
        d_ready_tp = d_ready_tp + sum(ready_cca & harmful & cca_busy);
        d_ready_fn = d_ready_fn + sum(ready_cca & harmful & ~cca_busy);
        d_ready_fp = d_ready_fp + sum(ready_cca & ~harmful & cca_busy);
        d_ready_tn = d_ready_tn + sum(ready_cca & ~harmful & ~cca_busy);

        ready = ready_cca & ~cca_busy;
        starts = ready & (rand(stream, n_nodes, 1) < q);
        deferred_ready = ready & ~starts;
        if any(deferred_ready)
            deferred_pids = queue_head(deferred_ready);
            pkt.probability_wait_us(deferred_pids) = ...
                pkt.probability_wait_us(deferred_pids) + dt_us;
        end
        start_ids = find(starts);
        n_starts = numel(start_ids);
        active_was_present = ~isempty(active_before);
        lock_was_present = ap_lock > 0;

        if n_starts > 0
            cca_cache_valid = false;
            diagnostics.attempts = diagnostics.attempts + n_starts;
            if n_starts > 1
                diagnostics.simultaneous_start_events = ...
                    diagnostics.simultaneous_start_events + 1;
                diagnostics.simultaneous_start_attempts = ...
                    diagnostics.simultaneous_start_attempts + n_starts;
            end
            if active_was_present || lock_was_present
                diagnostics.late_start_events = diagnostics.late_start_events + 1;
                diagnostics.late_start_attempts = ...
                    diagnostics.late_start_attempts + n_starts;
            end
            diagnostics.sinr_harmful_start_attempts = ...
                diagnostics.sinr_harmful_start_attempts + ...
                sum(starts & sinr_harmful);
            diagnostics.self_undecodable_start_attempts = ...
                diagnostics.self_undecodable_start_attempts + ...
                sum(starts & self_undecodable);
            diagnostics.single_user_only_harmful_start_attempts = ...
                diagnostics.single_user_only_harmful_start_attempts + ...
                sum(starts & single_user_only);

            for k = 1:n_starts
                u = start_ids(k);
                pid = queue_head(u);
                tx_active(u) = true;
                tx_remaining_slots(u) = n_data_slots;
                tx_packet_id(u) = pid;
                tx_start_us(u) = t_us;
                tx_failed(u) = false;
                difs_elapsed_us(u) = 0;
                pkt.attempts(pid) = pkt.attempts(pid) + 1;
                if ~isfinite(pkt.first_attempt_us(pid))
                    pkt.first_attempt_us(pid) = t_us;
                end
            end

            if lock_was_present
                % The AP cannot acquire another user during a locked frame.
                tx_failed(start_ids) = true;
                diagnostics.late_start_rejections = ...
                    diagnostics.late_start_rejections + n_starts;
            else
                % The strongest newly starting station is the sole capture
                % candidate.  Existing failed transmissions remain interferers.
                [~, strongest_local] = max(desired_ap_power(start_ids));
                candidate = start_ids(strongest_local);
                all_active = find(tx_active);
                initial_sinr = ap_sinr(candidate, all_active, ap_rx, noise_w);
                initial_sinr = initial_sinr(1);

                losers = start_ids(start_ids ~= candidate);
                if ~isempty(losers)
                    tx_failed(losers) = true;
                    diagnostics.simultaneous_loser_attempts = ...
                        diagnostics.simultaneous_loser_attempts + numel(losers);
                    diagnostics.capture_opportunities = ...
                        diagnostics.capture_opportunities + 1;
                end

                if all(initial_sinr >= data_sinr_linear)
                    ap_lock = candidate;
                    ap_lock_was_capture = n_starts > 1;
                    if ap_lock_was_capture
                        diagnostics.capture_candidates = ...
                            diagnostics.capture_candidates + 1;
                    end
                else
                    tx_failed(candidate) = true;
                    diagnostics.initial_sinr_rejections = ...
                        diagnostics.initial_sinr_rejections + 1;
                    if n_starts > 1
                        diagnostics.capture_initial_failures = ...
                            diagnostics.capture_initial_failures + 1;
                    end
                    ap_lock = 0;
                    ap_lock_was_capture = false;
                end
            end
        end

        % The locked frame is checked in every occupied slot, including its
        % first slot.  A transition from decodable to undecodable is a partial
        % collision; the AP remains locked until that frame ends.
        if ap_lock > 0 && tx_active(ap_lock) && ~tx_failed(ap_lock)
            current_sinr = ap_sinr(ap_lock, find(tx_active), ap_rx, noise_w);
            current_sinr = current_sinr(1);
            if all(current_sinr < data_sinr_linear)
                tx_failed(ap_lock) = true;
                cca_cache_valid = false;
                diagnostics.partial_collisions = diagnostics.partial_collisions + 1;
                if ap_lock_was_capture
                    diagnostics.capture_partial_failures = ...
                        diagnostics.capture_partial_failures + 1;
                end
            end
        end

        t_next_us = min(t_us + dt_us, hard_end_us);
        interval_us = t_next_us - t_us;
        overlap_measure_us = interval_overlap_us(t_us, t_next_us, ...
            measurement_left_us, measurement_right_us);
        system_area_measure_us = system_area_measure_us + ...
            backlog_n * overlap_measure_us;
        active_now = find(tx_active);
        n_active = numel(active_now);
        service_area_measure_us = service_area_measure_us + ...
            n_active * overlap_measure_us;
        if n_active > 1
            d_overlap_time_us = d_overlap_time_us + interval_us;
            d_excess_airtime_us = d_excess_airtime_us + ...
                (n_active - 1) * interval_us;
        end

        % DIFS accrues only for a current HOL while the selected CCA mode
        % reports idle.  Empty queues never accumulate credit.
        idle_hol = has_packet & ~tx_active;
        difs_elapsed_us(~has_packet) = 0;
        difs_elapsed_us(idle_hol & cca_busy) = 0;
        count_difs = idle_hol & ~cca_busy;
        difs_elapsed_us(count_difs) = min(difs_us, ...
            difs_elapsed_us(count_difs) + interval_us);

        % Advance transmissions and resolve outcomes at the end boundary.
        tx_remaining_slots(active_now) = tx_remaining_slots(active_now) - 1;
        finished_ids = active_now(tx_remaining_slots(active_now) <= 0);
        if ~isempty(finished_ids)
            cca_cache_valid = false;
        end
        for k = 1:numel(finished_ids)
            u = finished_ids(k);
            pid = tx_packet_id(u);
            was_ap_lock = (ap_lock == u);
            was_capture = was_ap_lock && ap_lock_was_capture;
            succeeded = was_ap_lock && ~tx_failed(u);

            if succeeded
                pkt.completion_us(pid) = t_next_us;
                completed_n = completed_n + 1;
                backlog_n = backlog_n - 1;
                diagnostics.successful_attempts = ...
                    diagnostics.successful_attempts + 1;
                payload_success_overlap_us = payload_success_overlap_us + ...
                    interval_overlap_us(tx_start_us(u), t_next_us, ...
                        measurement_left_us, measurement_right_us);
                if was_capture
                    diagnostics.capture_successes = ...
                        diagnostics.capture_successes + 1;
                end

                if queue_head(u) ~= pid
                    error('simulate_sb_cf_v2:QueueCorruption', ...
                          'Successful packet is not the node HOL packet.');
                end
                next_pid = queue_next(pid);
                queue_head(u) = next_pid;
                if next_pid == 0
                    queue_tail(u) = 0;
                    has_packet(u) = false;
                else
                    pkt.hol_us(next_pid) = t_next_us;
                end
            else
                diagnostics.failed_attempts = diagnostics.failed_attempts + 1;
                diagnostics.collision_waste_us = ...
                    diagnostics.collision_waste_us + ...
                    (t_next_us - tx_start_us(u));
                failed_interval_count = failed_interval_count + 1;
                if failed_interval_count > failed_capacity
                    failed_interval_start_us(end+failed_capacity,1) = 0;
                    failed_interval_end_us(end+failed_capacity,1) = 0;
                    failed_capacity = 2 * failed_capacity;
                end
                failed_interval_start_us(failed_interval_count) = tx_start_us(u);
                failed_interval_end_us(failed_interval_count) = t_next_us;
                if was_capture
                    diagnostics.capture_failures = ...
                        diagnostics.capture_failures + 1;
                end
            end

            % Both a new HOL and a failed retry must earn a fresh DIFS.
            difs_elapsed_us(u) = 0;
            tx_active(u) = false;
            tx_remaining_slots(u) = 0;
            tx_packet_id(u) = 0;
            tx_start_us(u) = NaN;
            tx_failed(u) = false;
            if was_ap_lock
                ap_lock = 0;
                ap_lock_was_capture = false;
            end
        end

        t_us = t_next_us;
    end

    sim_end_us = t_us;
    % Include already-spent airtime of known failed frames cut by hard stop.
    unfinished_failed = find(tx_active & tx_failed);
    for k = 1:numel(unfinished_failed)
        u = unfinished_failed(k);
        diagnostics.collision_waste_us = diagnostics.collision_waste_us + ...
            max(0, sim_end_us - tx_start_us(u));
        failed_interval_count = failed_interval_count + 1;
        if failed_interval_count > failed_capacity
            failed_interval_start_us(end+failed_capacity,1) = 0;
            failed_interval_end_us(end+failed_capacity,1) = 0;
            failed_capacity = 2 * failed_capacity;
        end
        failed_interval_start_us(failed_interval_count) = tx_start_us(u);
        failed_interval_end_us(failed_interval_count) = sim_end_us;
    end

    failed_interval_start_us = ...
        failed_interval_start_us(1:failed_interval_count);
    failed_interval_end_us = ...
        failed_interval_end_us(1:failed_interval_count);
    backlog_sample_us = backlog_sample_us(1:backlog_sample_count);
    backlog_sample_n = backlog_sample_n(1:backlog_sample_count);

    diagnostics.collision_tx_airtime_us = ...
        sum(max(0,failed_interval_end_us-failed_interval_start_us));
    diagnostics.collision_channel_time_us = interval_union_length( ...
        failed_interval_start_us,failed_interval_end_us,-Inf,Inf);
    diagnostics.collision_tx_airtime_measure_us = sum(max(0, ...
        min(failed_interval_end_us,measurement_right_us) - ...
        max(failed_interval_start_us,measurement_left_us)));
    diagnostics.collision_channel_time_measure_us = interval_union_length( ...
        failed_interval_start_us,failed_interval_end_us, ...
        measurement_left_us,measurement_right_us);

    diagnostics.completed_packets = completed_n;
    diagnostics.raw_listening_busy_opportunities = d_raw_busy_opp;
    diagnostics.raw_listening_misses = d_raw_misses;
    diagnostics.eligible_cca_tp = d_eligible_tp;
    diagnostics.eligible_cca_fn = d_eligible_fn;
    diagnostics.eligible_cca_fp = d_eligible_fp;
    diagnostics.eligible_cca_tn = d_eligible_tn;
    diagnostics.ready_cca_tp = d_ready_tp;
    diagnostics.ready_cca_fn = d_ready_fn;
    diagnostics.ready_cca_fp = d_ready_fp;
    diagnostics.ready_cca_tn = d_ready_tn;
    diagnostics.eligible_sinr_harmful_opportunities = ...
        d_eligible_sinr_harmful;
    diagnostics.eligible_self_undecodable_opportunities = ...
        d_eligible_self_undecodable;
    diagnostics.eligible_single_user_only_harmful_opportunities = ...
        d_eligible_single_user_only;
    diagnostics.ready_sinr_harmful_opportunities = d_ready_sinr_harmful;
    diagnostics.ready_self_undecodable_opportunities = ...
        d_ready_self_undecodable;
    diagnostics.ready_single_user_only_harmful_opportunities = ...
        d_ready_single_user_only;
    diagnostics.overlapping_transmission_time_us = d_overlap_time_us;
    diagnostics.excess_transmitter_airtime_us = d_excess_airtime_us;
    diagnostics.raw_listening_miss_rate = safe_ratio( ...
        diagnostics.raw_listening_misses, ...
        diagnostics.raw_listening_busy_opportunities);
    diagnostics.eligible_cca_fn_rate = safe_ratio( ...
        diagnostics.eligible_cca_fn, ...
        diagnostics.eligible_cca_tp + diagnostics.eligible_cca_fn);
    diagnostics.eligible_cca_fp_rate = safe_ratio( ...
        diagnostics.eligible_cca_fp, ...
        diagnostics.eligible_cca_fp + diagnostics.eligible_cca_tn);
    diagnostics.ready_cca_fn_rate = safe_ratio( ...
        diagnostics.ready_cca_fn, ...
        diagnostics.ready_cca_tp + diagnostics.ready_cca_fn);
    diagnostics.ready_cca_fp_rate = safe_ratio( ...
        diagnostics.ready_cca_fp, ...
        diagnostics.ready_cca_fp + diagnostics.ready_cca_tn);

    completed_mask = isfinite(pkt.completion_us);
    pkt.boundary_wait_us = zeros(n_packets,1);
    pkt.difs_wait_us = pkt.attempts * difs_us;
    pkt.collision_delay_us = zeros(n_packets,1);
    pkt.collision_delay_us(completed_mask) = ...
        max(0,pkt.attempts(completed_mask)-1) * Tp_us;
    pkt.control_delay_us = zeros(n_packets,1);
    pkt.data_delay_us = zeros(n_packets,1);
    pkt.data_delay_us(completed_mask) = Tp_us;
    component_sum = pkt.difs_wait_us + pkt.probability_wait_us + ...
        pkt.collision_delay_us + pkt.data_delay_us;
    pkt.busy_nav_wait_us = zeros(n_packets,1);
    pkt.busy_nav_wait_us(completed_mask) = max(0, ...
        pkt.completion_us(completed_mask) - pkt.hol_us(completed_mask) - ...
        component_sum(completed_mask));
    pkt.other_access_delay_us = zeros(n_packets,1);

    raw = struct();
    raw.packet_log = pkt;
    raw.final_backlog = backlog_n;
    raw.sim_end_us = sim_end_us;
    raw.system_area_measure_us = system_area_measure_us;
    raw.service_area_measure_us = service_area_measure_us;
    raw.payload_success_overlap_us = payload_success_overlap_us;
    raw.backlog_sample_us = backlog_sample_us;
    raw.backlog_sample_n = backlog_sample_n;
    raw.diagnostics = diagnostics;

    result = finalize_sim_result(raw, trace, cfg, protocol, M, q);
end

function validate_inputs(trace, scenario, cfg, M, q)
    needed_trace = {'times_us','node_id','n_packets','lambda_per_node'};
    needed_cfg = {'n_nodes','arrival_tick_us','warmup_us','measure_us', ...
                  'arrival_end_us','sim_hard_end_us','stats_sample_us', ...
                  'rx_sens_dbm','cca_mode'};
    for k = 1:numel(needed_trace)
        if ~isfield(trace, needed_trace{k})
            error('simulate_sb_cf_v2:MissingTraceField', ...
                  'Missing trace field: %s', needed_trace{k});
        end
    end
    for k = 1:numel(needed_cfg)
        if ~isfield(cfg, needed_cfg{k})
            error('simulate_sb_cf_v2:MissingConfigField', ...
                  'Missing cfg field: %s', needed_cfg{k});
        end
    end
    if ~isfield(scenario, 'MMW') || ~isfield(scenario, 'PHY')
        error('simulate_sb_cf_v2:BadScenario', ...
              'scenario must contain MMW and PHY structures.');
    end
    if cfg.arrival_tick_us ~= 5
        error('simulate_sb_cf_v2:BadArrivalGrid', ...
              'SB-CF v2 requires the common 5-us arrival grid.');
    end
    if M < 1 || M ~= round(M)
        error('simulate_sb_cf_v2:BadM', 'M must be a positive integer.');
    end
    if q <= 0 || q > 1
        error('simulate_sb_cf_v2:BadQ', 'q must lie in (0,1].');
    end
    if trace.n_packets ~= numel(trace.times_us) || ...
            trace.n_packets ~= numel(trace.node_id)
        error('simulate_sb_cf_v2:BadTraceLength', ...
              'Trace packet count does not match its event vectors.');
    end
    if size(scenario.PHY.Int_Matrix,1) ~= cfg.n_nodes || ...
            size(scenario.PHY.Int_Matrix,2) ~= cfg.n_nodes || ...
            size(scenario.PHY.AP_Rx_Matrix,1) ~= cfg.n_nodes || ...
            size(scenario.PHY.AP_Rx_Matrix,2) ~= cfg.n_nodes
        error('simulate_sb_cf_v2:BadPowerMatrix', ...
              'Scenario power matrices do not match cfg.n_nodes.');
    end
end

function [harmful, sinr_harmful, self_undecodable, single_user_only] = ...
        harmful_if_started(n_nodes, active_ids, ap_lock, ...
        tx_failed, ap_rx, desired_power, noise_w, sinr_threshold)
% Under the locked single-user receiver model every hypothetical start while
% ap_lock is present is harmful, even when both links would satisfy an SINR
% test.  Separate subcategories retain the physical-SINR explanation.
    if isempty(active_ids)
        own_interference = zeros(n_nodes, 1);
    else
        own_interference = sum(ap_rx(:, active_ids), 2);
    end
    own_sinr = desired_power ./ (noise_w + own_interference + eps);
    self_undecodable = own_sinr < sinr_threshold;

    sinr_harmful = false(n_nodes, 1);
    if ap_lock > 0 && ~tx_failed(ap_lock)
        other_active = active_ids(active_ids ~= ap_lock);
        if isempty(other_active)
            base_interference = 0;
        else
            base_interference = sum(ap_rx(ap_lock, other_active));
        end
        candidate_sinr_after_start = desired_power(ap_lock) ./ ...
            (noise_w + base_interference + ap_rx(ap_lock,:).' + eps);
        sinr_harmful = candidate_sinr_after_start < sinr_threshold;
        sinr_harmful(ap_lock) = false;
    end
    locked_single_user = false(n_nodes, 1);
    if ap_lock > 0
        locked_single_user(:) = true;
        locked_single_user(ap_lock) = false;
    end
    single_user_only = locked_single_user & ~sinr_harmful & ~self_undecodable;
    harmful = locked_single_user | sinr_harmful | self_undecodable;
end

function value = ap_sinr(candidate, active_ids, ap_rx, noise_w)
    interferers = active_ids(active_ids ~= candidate);
    if isempty(interferers)
        interference = 0;
    else
        interference = sum(ap_rx(candidate, interferers));
    end
    value = ap_rx(candidate, candidate) / (noise_w + interference + eps);
end

function diagnostics = initialise_diagnostics(cca_mode, seed, Tp_us, difs_us)
    diagnostics = struct();
    diagnostics.cca_mode = cca_mode;
    diagnostics.seed = double(seed);
    diagnostics.Tp_us = Tp_us;
    diagnostics.difs_us = difs_us;
    diagnostics.raw_listening_misses = 0;
    diagnostics.raw_listening_busy_opportunities = 0;
    diagnostics.eligible_cca_tp = 0;
    diagnostics.eligible_cca_fn = 0;
    diagnostics.eligible_cca_fp = 0;
    diagnostics.eligible_cca_tn = 0;
    diagnostics.ready_cca_tp = 0;
    diagnostics.ready_cca_fn = 0;
    diagnostics.ready_cca_fp = 0;
    diagnostics.ready_cca_tn = 0;
    diagnostics.eligible_sinr_harmful_opportunities = 0;
    diagnostics.eligible_self_undecodable_opportunities = 0;
    diagnostics.eligible_single_user_only_harmful_opportunities = 0;
    diagnostics.ready_sinr_harmful_opportunities = 0;
    diagnostics.ready_self_undecodable_opportunities = 0;
    diagnostics.ready_single_user_only_harmful_opportunities = 0;
    diagnostics.sinr_harmful_start_attempts = 0;
    diagnostics.self_undecodable_start_attempts = 0;
    diagnostics.single_user_only_harmful_start_attempts = 0;
    diagnostics.late_start_events = 0;
    diagnostics.late_start_attempts = 0;
    diagnostics.late_start_rejections = 0;
    diagnostics.simultaneous_start_events = 0;
    diagnostics.simultaneous_start_attempts = 0;
    diagnostics.simultaneous_loser_attempts = 0;
    diagnostics.capture_opportunities = 0;
    diagnostics.capture_candidates = 0;
    diagnostics.capture_initial_failures = 0;
    diagnostics.capture_partial_failures = 0;
    diagnostics.capture_successes = 0;
    diagnostics.capture_failures = 0;
    diagnostics.initial_sinr_rejections = 0;
    diagnostics.partial_collisions = 0;
    diagnostics.attempts = 0;
    diagnostics.successful_attempts = 0;
    diagnostics.failed_attempts = 0;
    diagnostics.collision_waste_us = 0;
    diagnostics.overlapping_transmission_time_us = 0;
    diagnostics.excess_transmitter_airtime_us = 0;
end

function value = safe_ratio(numerator, denominator)
    if denominator > 0
        value = numerator / denominator;
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
        error('simulate_sb_cf_v2:IntervalLengthMismatch', ...
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
