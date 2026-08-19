function result = simulate_aloha_v2(protocol, trace, scenario, cfg, M, q, seed)
%SIMULATE_ALOHA_V2 Event-driven sensing-free Aloha simulators (TXOP model).
%   Fixed packet length = 1 conn_slot (162.5 us).  M = TXOP length in
%   conn_slots.  In ready_queue mode each successful contention transmits
%   min(queue_depth, M) packets.  In batch_M mode every M packets form one
%   request; only complete requests contend and one success transmits
%   exactly M packets.  sf_cf uses per-packet collision detection (A-MPDU).
%
%   protocol: 'sf_cf' (slot = TXOP) or 'sf_cb' (slot = conn_slot).

    protocol = lower(char(protocol));
    if ~ismember(protocol, {'sf_cf', 'sf_cb'})
        error('simulate_aloha_v2:BadProtocol', ...
              'protocol must be ''sf_cf'' or ''sf_cb''.');
    end
    is_saturation = isfield(cfg,'traffic_mode') && ...
        strcmpi(char(cfg.traffic_mode),'saturation');
    valid_delay_M = isscalar(M) && isfinite(M) && M >= 1 && M == round(M);
    valid_saturation_M = isscalar(M) && isfinite(M) && M > 0;
    if (~is_saturation && ~valid_delay_M) || ...
            (is_saturation && ~valid_saturation_M)
        error('simulate_aloha_v2:BadM', ...
            'M must be an integer >=1 for delay or positive for saturation.');
    end
    if ~isscalar(q) || ~isfinite(q) || q <= 0 || q > 1
        error('simulate_aloha_v2:BadQ', 'q must be in the interval (0,1].');
    end
    if ~isscalar(seed) || ~isfinite(seed)
        error('simulate_aloha_v2:BadSeed', 'seed must be a finite scalar.');
    end

    required_cfg = {'n_nodes','warmup_us','measure_us','arrival_end_us', ...
                    'sim_hard_end_us'};
    for i = 1:numel(required_cfg)
        if ~isfield(cfg, required_cfg{i})
            error('simulate_aloha_v2:MissingConfig', ...
                  'cfg.%s is required.', required_cfg{i});
        end
    end
    required_trace = {'times_us','node_id','packet_ids_by_node','n_packets'};
    for i = 1:numel(required_trace)
        if ~isfield(trace, required_trace{i})
            error('simulate_aloha_v2:MissingTrace', ...
                  'trace.%s is required.', required_trace{i});
        end
    end
    if numel(trace.packet_ids_by_node) ~= cfg.n_nodes
        error('simulate_aloha_v2:TraceNodeCount', ...
              'trace.packet_ids_by_node does not match cfg.n_nodes.');
    end
    if ~isempty(scenario) && isstruct(scenario) && isfield(scenario, 'SYS') && ...
            isfield(scenario.SYS, 'N_MLO') && scenario.SYS.N_MLO ~= cfg.n_nodes
        error('simulate_aloha_v2:ScenarioNodeCount', ...
              'scenario.SYS.N_MLO does not match cfg.n_nodes.');
    end

    n_nodes = double(cfg.n_nodes);
    n_packets = double(trace.n_packets);
    arrival_us = double(trace.times_us(:));
    node_id = double(trace.node_id(:));
    if numel(arrival_us) ~= n_packets || numel(node_id) ~= n_packets
        error('simulate_aloha_v2:TraceLength', ...
              'trace vectors do not match trace.n_packets.');
    end
    if any(diff(arrival_us) < 0) || any(node_id < 1 | node_id > n_nodes | ...
            node_id ~= round(node_id))
        error('simulate_aloha_v2:BadTrace', ...
              'Trace times must be sorted and node IDs must be valid integers.');
    end

    if isempty(scenario) || ~isstruct(scenario) || ...
            ~isfield(scenario, 'MMW_REAL') || ...
            ~isfield(scenario.MMW_REAL, 'CONN_OVERHEAD_US')
        error('simulate_aloha_v2:MissingTiming', ...
            'scenario.MMW_REAL.CONN_OVERHEAD_US is required.');
    end
    conn_slot_us = double(scenario.MMW_REAL.CONN_OVERHEAD_US);
    txop_us = conn_slot_us * double(M);
    batch_requests = strcmp(protocol, 'sf_cb') && ...
        is_batch_txop_mode(cfg) && ~is_saturation;

    if strcmp(protocol, 'sf_cf')
        contention_slot_us = txop_us;     % slot = whole TXOP
    else
        contention_slot_us = conn_slot_us; % SF-CB: compete in one conn_slot
    end

    hard_end_us = double(cfg.sim_hard_end_us);
    arrival_end_us = double(cfg.arrival_end_us);
    if hard_end_us < arrival_end_us
        error('simulate_aloha_v2:BadHorizon', ...
              'cfg.sim_hard_end_us must not precede cfg.arrival_end_us.');
    end

    stream = RandStream('mt19937ar', 'Seed', double(seed));

    % FIFO queue state
    head = ones(n_nodes, 1);
    tail = zeros(n_nodes, 1);
    batch_fill = zeros(n_nodes, 1);
    request_count = zeros(n_nodes, 1);
    next_arrival = 1;

    % Per-packet statistics
    hol_us = nan(n_packets, 1);
    first_attempt_us = nan(n_packets, 1);
    completion_us = nan(n_packets, 1);
    attempts = zeros(n_packets, 1);
    first_eligible_us = nan(n_packets, 1);
    boundary_wait_us = zeros(n_packets, 1);
    probability_wait_us = zeros(n_packets, 1);
    collision_delay_us = zeros(n_packets, 1);
    control_delay_us = zeros(n_packets, 1);
    data_delay_us = zeros(n_packets, 1);

    measure_left = double(cfg.warmup_us);
    measure_right = arrival_end_us;
    system_area_measure_us = 0;
    service_area_measure_us = 0;
    payload_success_overlap_us = 0;
    payload_attempt_overlap_us = 0;
    payload_collision_overlap_us = 0;
    saturation_per_node_completions = zeros(n_nodes, 1);

    slots_started = 0;
    slots_completed = 0;
    truncated_slots = 0;
    attempts_total = 0;
    attempt_slots = 0;
    idle_slots = 0;
    success_slots = 0;
    collision_slots = 0;
    idle_wasted_us = 0;
    collision_wasted_us = 0;
    collision_tx_airtime_us = 0;
    idle_wasted_measure_us = 0;
    collision_wasted_measure_us = 0;
    tx_nodes_hist = zeros(1, n_nodes + 1);

    % Backlog sampling
    sample_interval_us = cfg.stats_sample_us;
    next_sample_us = sample_interval_us;
    backlog_sample_us = [];
    backlog_sample_n = [];
    diagnostics = struct();
    diagnostics.rts_success = 0;
    diagnostics.rts_collisions = 0;

    now_us = 0;
    sim_end_us = hard_end_us;
    truncated = false;

    while now_us < hard_end_us
        enqueue_until(now_us);
        slots_started = slots_started + 1;

        % Determine HOL nodes
        if batch_requests
            active_nodes = find(request_count > 0);
        else
            active_nodes = find(head <= tail);
        end
        k = numel(active_nodes);

        % Backlog sampling
        if now_us >= next_sample_us
            backlog_sample_us(end+1, 1) = now_us;
            backlog_sample_n(end+1, 1) = k;
            next_sample_us = next_sample_us + sample_interval_us;
        end

        if k == 0
            % No backlog: idle slot
            idle_slots = idle_slots + 1;
            idle_wasted_us = idle_wasted_us + contention_slot_us;
            if now_us >= measure_left && now_us < measure_right
                idle_wasted_measure_us = idle_wasted_measure_us + contention_slot_us;
            end
            now_us = now_us + contention_slot_us;
            continue;
        end

        % Bernoulli trial for each HOL node
        tx_mask = rand(stream, k, 1) < q;
        tx_local_idx = find(tx_mask);
        n_tx = numel(tx_local_idx);
        attempts_total = attempts_total + k;
        attempt_slots = attempt_slots + 1;

        if n_tx == 0
            % All decide not to send
            idle_slots = idle_slots + 1;
            idle_wasted_us = idle_wasted_us + contention_slot_us;
            if now_us >= measure_left && now_us < measure_right
                idle_wasted_measure_us = idle_wasted_measure_us + contention_slot_us;
            end
            now_us = now_us + contention_slot_us;
            continue;
        end

        tx_nodes = active_nodes(tx_local_idx);
        tx_nodes_hist(min(n_tx, n_nodes + 1)) = tx_nodes_hist(min(n_tx, n_nodes + 1)) + 1;

        % Each tx node determines how many packets it can send (saturation: always M)
        num_to_send = zeros(n_tx, 1);
        for i = 1:n_tx
            u = tx_nodes(i);
            if is_saturation
                num_to_send(i) = M;
            elseif batch_requests
                num_to_send(i) = M;
            else
                num_to_send(i) = min(tail(u) - head(u) + 1, M);
            end
        end

        % Mark first attempt for HOL packets
        for i = 1:n_tx
            u = tx_nodes(i);
            ids_u = trace.packet_ids_by_node{u};
            pid = ids_u(head(u));
            attempts(pid) = attempts(pid) + 1;
            if isnan(first_attempt_us(pid))
                first_attempt_us(pid) = now_us;
            end
            if isnan(first_eligible_us(pid))
                first_eligible_us(pid) = now_us;
            end
        end

        if strcmp(protocol, 'sf_cb')
            % SF-CB: one RTS transmitter reserves the channel.  The RTS,
            % SIFS, eight-sector CTS sweep and final SIFS occupy one
            % 162.5 us connection slot; DATA starts at the next boundary.
            % Multiple simultaneous RTS frames collide for the whole slot.
            if n_tx == 1
                u = tx_nodes(1);
                n_send = num_to_send(1);
                success_slots = success_slots + 1;
                diagnostics.rts_success = diagnostics.rts_success + 1;
                data_start = now_us + conn_slot_us;
                for p = 1:n_send
                    ids_u = trace.packet_ids_by_node{u};
                    pid = ids_u(head(u));
                    pkt_end = data_start + p * conn_slot_us;
                    if p == 1
                        control_delay_us(pid) = conn_slot_us;
                    end
                    data_delay_us(pid) = conn_slot_us;
                    complete_packet(u, pid, pkt_end);
                end
                if batch_requests
                    request_count(u) = max(0, request_count(u) - 1);
                end
                slot_dur = conn_slot_us + n_send * conn_slot_us;
                add_service_interval(data_start, data_start + n_send * conn_slot_us, 1);
                payload_success_overlap_us = payload_success_overlap_us + ...
                    interval_overlap_us(data_start, data_start + n_send * conn_slot_us, ...
                        measure_left, measure_right);
                payload_attempt_overlap_us = payload_attempt_overlap_us + ...
                    interval_overlap_us(data_start, data_start + n_send * conn_slot_us, ...
                        measure_left, measure_right);
                deferred = setdiff(active_nodes, tx_nodes);
                for uu = deferred(:).'
                    if head(uu) <= tail(uu)
                        pid_uu = trace.packet_ids_by_node{uu}(head(uu));
                        probability_wait_us(pid_uu) = ...
                            probability_wait_us(pid_uu) + conn_slot_us;
                    end
                end
                now_us = now_us + slot_dur;
            else
                % RTS collision: nodes retry at the next reservation slot.
                collision_slots = collision_slots + 1;
                diagnostics.rts_collisions = diagnostics.rts_collisions + 1;
                collision_wasted_us = collision_wasted_us + conn_slot_us;
                if now_us >= measure_left && now_us < measure_right
                    collision_wasted_measure_us = collision_wasted_measure_us + conn_slot_us;
                end
                for uu = tx_nodes(:).'
                    if head(uu) <= tail(uu)
                        pid_uu = trace.packet_ids_by_node{uu}(head(uu));
                        collision_delay_us(pid_uu) = ...
                            collision_delay_us(pid_uu) + conn_slot_us;
                    end
                end
                deferred = setdiff(active_nodes, tx_nodes);
                for uu = deferred(:).'
                    if head(uu) <= tail(uu)
                        pid_uu = trace.packet_ids_by_node{uu}(head(uu));
                        probability_wait_us(pid_uu) = ...
                            probability_wait_us(pid_uu) + conn_slot_us;
                    end
                end
                now_us = now_us + conn_slot_us;
            end
        else
            % SF-CF: per-packet collision detection within TXOP
            % Slot length is fixed = txop_us (M * conn_slot_us)
            % Multiple nodes may transmit with different durations
            for pkt_idx = 1:M
                % Nodes still transmitting in this packet period
                still_tx = find(num_to_send >= pkt_idx);
                n_still = numel(still_tx);

                pkt_start = now_us + (pkt_idx - 1) * conn_slot_us;
                pkt_end = pkt_start + conn_slot_us;

                if pkt_end > hard_end_us
                    truncated = true;
                    truncated_slots = truncated_slots + 1;
                    break;
                end

                if n_still == 1
                    % Exactly one node transmitting 锟斤拷 success for this packet
                    u = tx_nodes(still_tx(1));
                    ids_u = trace.packet_ids_by_node{u};
                    pid = ids_u(head(u));
                    complete_packet(u, pid, pkt_end);

                    add_service_interval(pkt_start, pkt_end, 1);
                    payload_success_overlap_us = payload_success_overlap_us + ...
                        interval_overlap_us(pkt_start, pkt_end, measure_left, measure_right);
                    payload_attempt_overlap_us = payload_attempt_overlap_us + ...
                        interval_overlap_us(pkt_start, pkt_end, measure_left, measure_right);
                elseif n_still > 1
                    % Multiple transmitters 锟斤拷 all packets in this period collide
                    collision_slots = collision_slots + 1;
                    collision_wasted_us = collision_wasted_us + conn_slot_us;
                    collision_tx_airtime_us = collision_tx_airtime_us + n_still * conn_slot_us;
                    if now_us >= measure_left && now_us < measure_right
                        collision_wasted_measure_us = collision_wasted_measure_us + conn_slot_us;
                    end
                    payload_attempt_overlap_us = payload_attempt_overlap_us + ...
                        n_still * interval_overlap_us(pkt_start, pkt_end, measure_left, measure_right);
                    payload_collision_overlap_us = payload_collision_overlap_us + ...
                        n_still * interval_overlap_us(pkt_start, pkt_end, measure_left, measure_right);
                    % Mark collision delay for HOL packets still in this period
                    for ii = 1:n_still
                        uu = tx_nodes(still_tx(ii));
                        ids_uu = trace.packet_ids_by_node{uu};
                        % Only mark the HOL packet (first unsent)
                        if head(uu) <= tail(uu)
                            pid_uu = ids_uu(head(uu));
                            if ~isfinite(completion_us(pid_uu))
                                collision_delay_us(pid_uu) = collision_delay_us(pid_uu) + conn_slot_us;
                            end
                        end
                    end
                end
                % n_still == 0: idle for this period (wasted)
            end
            % Regardless of what happened, the slot takes txop_us
            now_us = now_us + txop_us;
        end
    end

    sim_end_us = now_us;
    final_backlog = sum(max(0, tail - head + 1));

    % Build packet_log table
    completed = isfinite(completion_us);
    packet_log = table();
    packet_log.packet_id = (1:n_packets)';
    packet_log.node_id = node_id;
    packet_log.arrival_us = arrival_us;
    packet_log.hol_us = hol_us;
    packet_log.first_attempt_us = first_attempt_us;
    packet_log.first_eligible_us = first_eligible_us;
    packet_log.completion_us = completion_us;
    packet_log.attempts = attempts;
    packet_log.boundary_wait_us = boundary_wait_us;
    packet_log.probability_wait_us = probability_wait_us;
    packet_log.collision_delay_us = collision_delay_us;
    packet_log.control_delay_us = control_delay_us;
    packet_log.data_delay_us = data_delay_us;
    packet_log.difs_wait_us = zeros(n_packets, 1);
    packet_log.busy_nav_wait_us = zeros(n_packets, 1);
    packet_log.other_access_delay_us = zeros(n_packets, 1);
    packet_log.success = completed;

    % Diagnostics
    diagnostics.reservation_k_definition = 'number of HOL nodes at slot start';
    diagnostics.reservation_k_values = (0:n_nodes)';
    diagnostics.reservation_frames_by_k = zeros(n_nodes+1, 1);
    diagnostics.reservation_full_frames_by_k = zeros(n_nodes+1, 1);
    diagnostics.reservation_attempts_by_k = zeros(n_nodes+1, 1);
    diagnostics.reservation_success_frames_by_k = zeros(n_nodes+1, 1);
    diagnostics.reservation_attempt_count_values = (0:n_nodes)';
    diagnostics.reservation_frames_by_attempt_count = zeros(n_nodes+1, 1);
    diagnostics.reservation_success_by_attempt_count = zeros(n_nodes+1, 1);
    diagnostics.txop_mode = txop_mode(cfg);
    diagnostics.batch_requests = batch_requests;
    diagnostics.reservation_control_us = conn_slot_us;
    structural_censored = false(n_packets, 1);
    if batch_requests
        for u = 1:n_nodes
            if batch_fill(u) > 0 && tail(u) >= batch_fill(u)
                first = tail(u) - batch_fill(u) + 1;
                ids = trace.packet_ids_by_node{u}(first:tail(u));
                structural_censored(ids) = true;
            end
        end
    end
    diagnostics.structural_censored = sum(structural_censored);

    raw = struct();
    raw.packet_log = packet_log;
    raw.final_backlog = double(final_backlog);
    raw.sim_end_us = double(sim_end_us);
    raw.system_area_measure_us = double(system_area_measure_us);
    raw.service_area_measure_us = double(service_area_measure_us);
    raw.payload_success_overlap_us = double(payload_success_overlap_us);
    raw.backlog_sample_us = double(backlog_sample_us(:));
    raw.backlog_sample_n = double(backlog_sample_n(:));
    raw.diagnostics = diagnostics;
    raw.structural_censored = structural_censored;

    if is_saturation
        raw.saturation_per_node_completions = saturation_per_node_completions;
        result = finalize_saturation_result(raw, cfg, protocol, M, q);
    else
        result = finalize_sim_result(raw, trace, cfg, protocol, M, q);
    end

    function enqueue_until(limit_us)
        while next_arrival <= n_packets && arrival_us(next_arrival) <= limit_us
            packet_id = next_arrival;
            u = node_id(packet_id);
            was_empty = head(u) > tail(u);
            tail(u) = tail(u) + 1;
            ids_u = trace.packet_ids_by_node{u};
            if tail(u) > numel(ids_u) || ids_u(tail(u)) ~= packet_id
                error('simulate_aloha_v2:QueueMap', ...
                      'trace.packet_ids_by_node is inconsistent with trace vectors.');
            end
            if was_empty
                hol_us(packet_id) = arrival_us(packet_id);
            end
            if batch_requests
                batch_fill(u) = batch_fill(u) + 1;
                if batch_fill(u) >= M
                    batch_fill(u) = 0;
                    request_count(u) = request_count(u) + 1;
                end
            end
            next_arrival = next_arrival + 1;
        end
    end

    function complete_packet(u, packet_id, when_us)
        % Complete one HOL packet for node u
        ids_u = trace.packet_ids_by_node{u};
        if head(u) > tail(u) || ids_u(head(u)) ~= packet_id
            error('simulate_aloha_v2:BadCompletionOrder', ...
                  'Attempted to complete a non-HOL packet.');
        end
        if is_saturation
            if when_us >= measure_left && when_us < measure_right
                saturation_per_node_completions(u) = ...
                    saturation_per_node_completions(u) + 1;
            end
            hol_us(packet_id) = when_us;
            first_attempt_us(packet_id) = NaN;
            completion_us(packet_id) = NaN;
            attempts(packet_id) = 0;
            first_eligible_us(packet_id) = NaN;
            boundary_wait_us(packet_id) = 0;
            probability_wait_us(packet_id) = 0;
            collision_delay_us(packet_id) = 0;
            control_delay_us(packet_id) = 0;
            data_delay_us(packet_id) = 0;
        else
            completion_us(packet_id) = when_us;
            head(u) = head(u) + 1;
            if head(u) <= tail(u)
                next_packet = ids_u(head(u));
                hol_us(next_packet) = when_us;
            end
        end
    end

    function add_service_interval(a_us, b_us, multiplicity)
        if b_us <= a_us || multiplicity <= 0
            return;
        end
        service_area_measure_us = service_area_measure_us + multiplicity * ...
            interval_overlap_us(a_us, b_us, measure_left, measure_right);
    end
end
