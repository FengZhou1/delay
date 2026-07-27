function result = simulate_aloha_v2(protocol, trace, scenario, cfg, M, q, seed)
%SIMULATE_ALOHA_V2 Event-driven sensing-free Aloha simulators.
%   result = simulate_aloha_v2(protocol, trace, scenario, cfg, M, q, seed)
%   supports:
%     sf_cf - packet-length slotted Aloha. A slot is Tp=M conn-slots.
%     sf_cb - connection-based Aloha. One reservation is one conn-slot;
%             a singleton is followed by exactly Tp us of payload.
%
% Arrivals exactly on a decision boundary are enqueued before the decision.
% FIFO queues use trace.packet_ids_by_node with head/tail indices; cell-array
% heads are never deleted.  Intervals use the half-open convention [a,b).

    protocol = lower(char(protocol));
    if ~ismember(protocol, {'sf_cf', 'sf_cb'})
        error('simulate_aloha_v2:BadProtocol', ...
              'protocol must be ''sf_cf'' or ''sf_cb''.');
    end
    if ~isscalar(M) || ~isfinite(M) || M < 1 || M ~= round(M)
        error('simulate_aloha_v2:BadM', 'M must be a positive integer scalar.');
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
    is_saturation = isfield(cfg,'traffic_mode') && ...
        strcmpi(char(cfg.traffic_mode),'saturation');
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
            ~isfield(scenario, 'MMW') || ...
            ~isfield(scenario.MMW, 'CONN_OVERHEAD_US')
        error('simulate_aloha_v2:MissingTiming', ...
            'scenario.MMW.CONN_OVERHEAD_US is required.');
    end
    reservation_us = double(scenario.MMW.CONN_OVERHEAD_US);
    Tp_us = reservation_us * double(M);
    if strcmp(protocol, 'sf_cf')
        contention_slot_us = Tp_us;
    else
        contention_slot_us = reservation_us;
    end
    hard_end_us = double(cfg.sim_hard_end_us);
    arrival_end_us = double(cfg.arrival_end_us);
    if hard_end_us < arrival_end_us
        error('simulate_aloha_v2:BadHorizon', ...
              'cfg.sim_hard_end_us must not precede cfg.arrival_end_us.');
    end

    stream = RandStream('mt19937ar', 'Seed', double(seed));

    % FIFO state.  tail(u) is the number of node-u packets that have arrived;
    % head(u) indexes the current HOL in trace.packet_ids_by_node{u}.
    head = ones(n_nodes, 1);
    tail = zeros(n_nodes, 1);
    next_arrival = 1;

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
    service_area_measure_us = 0;
    payload_success_overlap_us = 0;
    payload_attempt_overlap_us = 0;
    payload_collision_overlap_us = 0;
    saturation_per_node_completions = zeros(n_nodes,1);

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
    collision_tx_airtime_measure_us = 0;

    % For SF-CB, K is the number of backlogged HOL nodes at frame start.
    % Attempt-count histograms are stored separately, so A|K can be checked
    % against the intended Binomial(K,q) law.
    k_values = (0:n_nodes).';
    reservation_frames_by_k = zeros(n_nodes + 1, 1);
    reservation_full_frames_by_k = zeros(n_nodes + 1, 1);
    reservation_attempts_by_k = zeros(n_nodes + 1, 1);
    reservation_success_frames_by_k = zeros(n_nodes + 1, 1);
    reservation_frames_by_attempt_count = zeros(n_nodes + 1, 1);
    reservation_success_by_attempt_count = zeros(n_nodes + 1, 1);

    t_us = 0;
    enqueue_until(t_us);

    while true
        % enqueue_until is repeated here so arrivals at this exact boundary
        % are always visible to the Bernoulli decision.
        enqueue_until(t_us);
        backlog_now = sum(max(0, tail - head + 1));
        all_arrivals_seen = next_arrival > n_packets;
        if t_us >= arrival_end_us && backlog_now == 0 && all_arrivals_seen
            break;
        end
        if t_us >= hard_end_us
            t_us = hard_end_us;
            break;
        end

        [backlogged_nodes, hol_packet_ids] = current_hol_packets();
        new_eligible = isnan(first_eligible_us(hol_packet_ids));
        if any(new_eligible)
            eligible_ids = hol_packet_ids(new_eligible);
            first_eligible_us(eligible_ids) = t_us;
            boundary_wait_us(eligible_ids) = ...
                t_us - hol_us(eligible_ids);
        end
        if isempty(backlogged_nodes)
            chosen = false(0,1);
        else
            chosen = rand(stream, numel(backlogged_nodes), 1) < q;
        end
        contender_nodes = backlogged_nodes(chosen);
        contender_packets = hol_packet_ids(chosen);
        deferred_packets = hol_packet_ids(~chosen);
        K_backlogged = numel(backlogged_nodes);
        K = numel(contender_packets);

        slots_started = slots_started + 1;
        attempts_total = attempts_total + K;
        attempt_slots = attempt_slots + double(K > 0);
        if K > 0
            attempts(contender_packets) = attempts(contender_packets) + 1;
            first_mask = isnan(first_attempt_us(contender_packets));
            first_ids = contender_packets(first_mask);
            first_attempt_us(first_ids) = t_us;
        end

        if strcmp(protocol, 'sf_cf')
            slot_end_us = t_us + Tp_us;
            actual_end_us = min(slot_end_us, hard_end_us);
            if K > 0
                add_service_interval(t_us, actual_end_us, K);
                payload_attempt_overlap_us = payload_attempt_overlap_us + ...
                    K * interval_overlap_us(t_us, actual_end_us, ...
                                            measure_left, measure_right);
            end
            probability_wait_us(deferred_packets) = ...
                probability_wait_us(deferred_packets) + Tp_us;
            enqueue_until(actual_end_us);

            if slot_end_us > hard_end_us
                truncated_slots = truncated_slots + 1;
                t_us = hard_end_us;
                break;
            end

            slots_completed = slots_completed + 1;
            if K == 0
                idle_slots = idle_slots + 1;
                idle_wasted_us = idle_wasted_us + Tp_us;
                idle_wasted_measure_us = idle_wasted_measure_us + ...
                    interval_overlap_us(t_us, slot_end_us, ...
                                        measure_left, measure_right);
            elseif K == 1
                success_slots = success_slots + 1;
                data_delay_us(contender_packets(1)) = ...
                    data_delay_us(contender_packets(1)) + Tp_us;
                complete_hol(contender_nodes(1), contender_packets(1), slot_end_us);
                payload_success_overlap_us = payload_success_overlap_us + ...
                    interval_overlap_us(t_us, slot_end_us, ...
                                        measure_left, measure_right);
            else
                collision_slots = collision_slots + 1;
                collision_delay_us(contender_packets) = ...
                    collision_delay_us(contender_packets) + Tp_us;
                collision_wasted_us = collision_wasted_us + Tp_us;
                collision_tx_airtime_us = collision_tx_airtime_us + K*Tp_us;
                collision_wasted_measure_us = collision_wasted_measure_us + ...
                    interval_overlap_us(t_us, slot_end_us, ...
                                        measure_left, measure_right);
                collision_tx_airtime_measure_us = ...
                    collision_tx_airtime_measure_us + K*interval_overlap_us( ...
                        t_us,slot_end_us,measure_left,measure_right);
                payload_collision_overlap_us = payload_collision_overlap_us + ...
                    K * interval_overlap_us(t_us, slot_end_us, ...
                                            measure_left, measure_right);
            end
            t_us = slot_end_us;

        else
            % SF-CB: every decision consumes one complete conn-slot
            % frame.  Only a singleton continues into an exact Tp data phase.
            reservation_frames_by_k(K_backlogged+1) = ...
                reservation_frames_by_k(K_backlogged+1) + 1;
            reservation_attempts_by_k(K_backlogged+1) = ...
                reservation_attempts_by_k(K_backlogged+1) + K;
            reservation_frames_by_attempt_count(K+1) = ...
                reservation_frames_by_attempt_count(K+1) + 1;
            frame_end_us = t_us + reservation_us;
            probability_wait_us(deferred_packets) = ...
                probability_wait_us(deferred_packets) + reservation_us;
            actual_frame_end_us = min(frame_end_us, hard_end_us);
            enqueue_until(actual_frame_end_us);

            if frame_end_us > hard_end_us
                truncated_slots = truncated_slots + 1;
                t_us = hard_end_us;
                break;
            end

            slots_completed = slots_completed + 1;
            reservation_full_frames_by_k(K_backlogged+1) = ...
                reservation_full_frames_by_k(K_backlogged+1) + 1;
            if K == 0
                idle_slots = idle_slots + 1;
                idle_wasted_us = idle_wasted_us + reservation_us;
                idle_wasted_measure_us = idle_wasted_measure_us + ...
                    interval_overlap_us(t_us, frame_end_us, ...
                                        measure_left, measure_right);
                t_us = frame_end_us;
            elseif K >= 2
                collision_slots = collision_slots + 1;
                collision_delay_us(contender_packets) = ...
                    collision_delay_us(contender_packets) + reservation_us;
                collision_wasted_us = collision_wasted_us + reservation_us;
                collision_tx_airtime_us = collision_tx_airtime_us + ...
                    K*reservation_us;
                collision_wasted_measure_us = collision_wasted_measure_us + ...
                    interval_overlap_us(t_us, frame_end_us, ...
                                        measure_left, measure_right);
                collision_tx_airtime_measure_us = ...
                    collision_tx_airtime_measure_us + K*interval_overlap_us( ...
                        t_us,frame_end_us,measure_left,measure_right);
                t_us = frame_end_us;
            else
                success_slots = success_slots + 1;
                control_delay_us(contender_packets(1)) = ...
                    control_delay_us(contender_packets(1)) + reservation_us;
                data_delay_us(contender_packets(1)) = ...
                    data_delay_us(contender_packets(1)) + Tp_us;
                reservation_success_frames_by_k(K_backlogged+1) = ...
                    reservation_success_frames_by_k(K_backlogged+1) + 1;
                reservation_success_by_attempt_count(K+1) = ...
                    reservation_success_by_attempt_count(K+1) + 1;

                data_start_us = frame_end_us;
                data_end_us = data_start_us + Tp_us;
                actual_data_end_us = min(data_end_us, hard_end_us);
                add_service_interval(data_start_us, actual_data_end_us, 1);
                payload_attempt_overlap_us = payload_attempt_overlap_us + ...
                    interval_overlap_us(data_start_us, actual_data_end_us, ...
                                        measure_left, measure_right);
                enqueue_until(actual_data_end_us);

                if data_end_us > hard_end_us
                    t_us = hard_end_us;
                    break;
                end
                complete_hol(contender_nodes(1), contender_packets(1), data_end_us);
                payload_success_overlap_us = payload_success_overlap_us + ...
                    interval_overlap_us(data_start_us, data_end_us, ...
                                        measure_left, measure_right);
                t_us = data_end_us;
            end
        end
    end

    sim_end_us = min(t_us, hard_end_us);
    enqueue_until(sim_end_us);
    if next_arrival <= n_packets
        error('simulate_aloha_v2:UnseenArrivals', ...
              'Simulation ended before all generated arrivals were enqueued.');
    end

    final_backlog = sum(max(0, tail - head + 1));
    completed = isfinite(completion_us);
    packet_end_us = completion_us;
    packet_end_us(~completed) = sim_end_us;
    system_overlap = max(0, min(packet_end_us, measure_right) - ...
                            max(arrival_us, measure_left));
    system_area_measure_us = sum(system_overlap);

    % Configured system-backlog samples, with packet presence defined
    % on [arrival,completion): arrivals at a sample count, completions do not.
    sample_period_us = double(cfg.stats_sample_us);
    backlog_sample_us = (0:sample_period_us:sim_end_us).';
    backlog_sample_n = zeros(size(backlog_sample_us));
    sorted_completion = sort(completion_us(completed));
    a_ptr = 1;
    c_ptr = 1;
    n_in_system = 0;
    for si = 1:numel(backlog_sample_us)
        sample_t = backlog_sample_us(si);
        while a_ptr <= n_packets && arrival_us(a_ptr) <= sample_t
            n_in_system = n_in_system + 1;
            a_ptr = a_ptr + 1;
        end
        while c_ptr <= numel(sorted_completion) && ...
                sorted_completion(c_ptr) <= sample_t
            n_in_system = n_in_system - 1;
            c_ptr = c_ptr + 1;
        end
        backlog_sample_n(si) = n_in_system;
    end

    packet_log = struct();
    packet_log.node_id = double(node_id(:));
    packet_log.arrival_us = double(arrival_us(:));
    packet_log.hol_us = double(hol_us(:));
    packet_log.first_attempt_us = double(first_attempt_us(:));
    packet_log.completion_us = double(completion_us(:));
    packet_log.attempts = double(attempts(:));
    packet_log.boundary_wait_us = double(boundary_wait_us(:));
    packet_log.difs_wait_us = zeros(n_packets,1);
    packet_log.probability_wait_us = double(probability_wait_us(:));
    packet_log.collision_delay_us = double(collision_delay_us(:));
    packet_log.control_delay_us = double(control_delay_us(:));
    packet_log.data_delay_us = double(data_delay_us(:));
    component_sum = boundary_wait_us + probability_wait_us + ...
        collision_delay_us + control_delay_us + data_delay_us;
    packet_log.busy_nav_wait_us = zeros(n_packets,1);
    packet_log.other_access_delay_us = zeros(n_packets,1);
    completed_for_components = isfinite(completion_us);
    packet_log.busy_nav_wait_us(completed_for_components) = max(0, ...
        completion_us(completed_for_components) - hol_us(completed_for_components) - ...
        component_sum(completed_for_components));

    diagnostics = struct();
    diagnostics.protocol = protocol;
    diagnostics.M = double(M);
    diagnostics.Tp_us = Tp_us;
    diagnostics.q = double(q);
    diagnostics.seed = double(seed);
    diagnostics.contention_slot_us = contention_slot_us;
    diagnostics.slots_started = slots_started;
    diagnostics.slots_completed = slots_completed;
    diagnostics.truncated_slots = truncated_slots;
    diagnostics.attempts_total = attempts_total;
    diagnostics.attempt_slots = attempt_slots;
    diagnostics.idle_slots = idle_slots;
    diagnostics.success_slots = success_slots;
    diagnostics.collision_slots = collision_slots;
    diagnostics.idle_wasted_us = idle_wasted_us;
    diagnostics.collision_wasted_us = collision_wasted_us;
    diagnostics.collision_channel_time_us = collision_wasted_us;
    diagnostics.collision_tx_airtime_us = collision_tx_airtime_us;
    diagnostics.wasted_us = idle_wasted_us + collision_wasted_us;
    diagnostics.idle_wasted_measure_us = idle_wasted_measure_us;
    diagnostics.collision_wasted_measure_us = collision_wasted_measure_us;
    diagnostics.collision_channel_time_measure_us = ...
        collision_wasted_measure_us;
    diagnostics.collision_tx_airtime_measure_us = ...
        collision_tx_airtime_measure_us;
    diagnostics.wasted_measure_us = idle_wasted_measure_us + ...
                                     collision_wasted_measure_us;
    diagnostics.payload_attempt_overlap_us = payload_attempt_overlap_us;
    diagnostics.payload_collision_overlap_us = payload_collision_overlap_us;
    diagnostics.payload_success_overlap_us = payload_success_overlap_us;
    diagnostics.service_area_definition = ...
        ['active payload-transmitter area; SF-CF collisions count each ', ...
         'contender and SF-CB reservation controls are excluded'];
    if strcmp(protocol, 'sf_cb')
        diagnostics.reservation_k_definition = ...
            'number of backlogged HOL nodes at reservation-frame start';
        diagnostics.reservation_k_values = k_values;
        diagnostics.reservation_frames_by_k = reservation_frames_by_k;
        diagnostics.reservation_full_frames_by_k = reservation_full_frames_by_k;
        diagnostics.reservation_attempts_by_k = reservation_attempts_by_k;
        diagnostics.reservation_success_frames_by_k = ...
            reservation_success_frames_by_k;
        diagnostics.reservation_attempt_count_values = k_values;
        diagnostics.reservation_frames_by_attempt_count = ...
            reservation_frames_by_attempt_count;
        diagnostics.reservation_success_by_attempt_count = ...
            reservation_success_by_attempt_count;
    else
        diagnostics.reservation_k_definition = '';
        diagnostics.reservation_k_values = zeros(0,1);
        diagnostics.reservation_frames_by_k = zeros(0,1);
        diagnostics.reservation_full_frames_by_k = zeros(0,1);
        diagnostics.reservation_attempts_by_k = zeros(0,1);
        diagnostics.reservation_success_frames_by_k = zeros(0,1);
        diagnostics.reservation_attempt_count_values = zeros(0,1);
        diagnostics.reservation_frames_by_attempt_count = zeros(0,1);
        diagnostics.reservation_success_by_attempt_count = zeros(0,1);
    end

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

    if is_saturation
        raw.saturation_per_node_completions = ...
            saturation_per_node_completions;
        result = finalize_saturation_result(raw,cfg,protocol,M,q);
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
            next_arrival = next_arrival + 1;
        end
    end

    function [nodes, packet_ids] = current_hol_packets()
        nodes = find(head <= tail);
        packet_ids = zeros(numel(nodes), 1);
        for jj = 1:numel(nodes)
            uu = nodes(jj);
            ids_uu = trace.packet_ids_by_node{uu};
            packet_ids(jj) = ids_uu(head(uu));
        end
    end

    function complete_hol(u, packet_id, when_us)
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
            % Reuse the persistent packet id as the next virtual HOL.  All
            % per-packet accounting is reset because it now denotes a new
            % saturated packet becoming HOL at this completion boundary.
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
