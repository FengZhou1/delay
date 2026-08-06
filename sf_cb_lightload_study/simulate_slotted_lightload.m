function raw = simulate_slotted_lightload(batch_mode, trace, scenario, cfg, M, q, seed)
%SIMULATE_SLOTTED_LIGHTLOAD Shared slotted connection-Aloha engine.
% batch_mode = false -> SF-CB baseline: one successful reservation carries
%   exactly one packet (DATA = M * conn-slot).
% batch_mode = true  -> batch_clear: one successful reservation transmits
%   the whole queue snapshot taken when DATA begins (new arrivals during
%   the DATA phase are not appended).
% The frame boundary every conn-slot (164.1 us) drives Bernoulli(q)
% decisions; a singleton reserves and sends DATA; collisions and idle
% frames each waste one conn-slot, matching the plan's SF-CB timing model.

    timing = protocol_timing(cfg);
    reservation_us = timing.CONN_SLOT_US;
    tp_us = reservation_us * double(M);
    n_nodes = double(cfg.n_nodes);
    is_saturation = isfield(cfg,'traffic_mode') && ...
        strcmpi(char(cfg.traffic_mode),'saturation');
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

    hol_us = nan(n_packets,1);
    first_attempt_us = nan(n_packets,1);
    completion_us = nan(n_packets,1);
    attempts = zeros(n_packets,1);
    first_eligible_us = nan(n_packets,1);
    boundary_wait_us = zeros(n_packets,1);
    probability_wait_us = zeros(n_packets,1);
    collision_delay_us = zeros(n_packets,1);
    control_delay_us = zeros(n_packets,1);
    data_delay_us = zeros(n_packets,1);
    difs_wait_us = zeros(n_packets,1);
    busy_nav_wait_us = zeros(n_packets,1);
    other_access_delay_us = zeros(n_packets,1);

    queue_head = ones(n_nodes,1);
    queue_tail = zeros(n_nodes,1);
    queue_count = zeros(n_nodes,1);
    next_arrival = 1;

    system_area_measure_us = 0;
    service_area_measure_us = 0;
    payload_success_overlap_us = 0;
    saturation_per_node_completions = zeros(n_nodes,1);
    idle_slots = 0;
    collision_slots = 0;
    success_slots = 0;
    attempts_total = 0;
    idle_wasted_us = 0;
    idle_wasted_measure_us = 0;
    collision_wasted_us = 0;
    collision_wasted_measure_us = 0;
    backlog_sample_us = zeros(0,1);
    backlog_sample_n = zeros(0,1);
    next_backlog_sample_us = 0;

    t_us = 0;
    enqueue_until(t_us);
    while true
        enqueue_until(t_us);
        backlog_now = sum(queue_count);
        all_arrivals_seen = next_arrival > n_packets;
        if t_us >= arrival_end_us && backlog_now == 0 && all_arrivals_seen
            break;
        end
        if t_us >= hard_end_us
            t_us = hard_end_us;
            break;
        end

        while next_backlog_sample_us <= t_us
            backlog_sample_us(end+1,1) = next_backlog_sample_us; %#ok<AGROW>
            backlog_sample_n(end+1,1) = backlog_now; %#ok<AGROW>
            next_backlog_sample_us = next_backlog_sample_us + stats_sample_us;
        end

        backlogged = find(queue_count > 0).';
        if isempty(backlogged)
            chosen = false(0,1);
        else
            chosen = rand(stream, numel(backlogged), 1) < q;
        end
        contenders = backlogged(chosen);
        deferred = backlogged(~chosen);
        K = numel(contenders);
        attempts_total = attempts_total + K;

        if ~is_saturation
            for u = backlogged
                pid = head_packet_id(u);
                if isnan(first_eligible_us(pid))
                    first_eligible_us(pid) = t_us;
                    boundary_wait_us(pid) = t_us - hol_us(pid);
                end
            end
            if K > 0
                for u = contenders
                    pid = head_packet_id(u);
                    attempts(pid) = attempts(pid) + 1;
                    if isnan(first_attempt_us(pid))
                        first_attempt_us(pid) = t_us;
                    end
                end
            end
        end

        frame_end_us = t_us + reservation_us;
        frame_overlap = interval_overlap_us(t_us, frame_end_us, ...
            left_measure_us, right_measure_us);
        system_area_measure_us = system_area_measure_us + ...
            backlog_now * frame_overlap;

        if K == 0
            idle_slots = idle_slots + 1;
            idle_wasted_us = idle_wasted_us + reservation_us;
            idle_wasted_measure_us = idle_wasted_measure_us + frame_overlap;
            if ~is_saturation
                for u = deferred
                    pid = head_packet_id(u);
                    probability_wait_us(pid) = ...
                        probability_wait_us(pid) + reservation_us;
                end
            end
            t_us = frame_end_us;
        elseif K >= 2
            collision_slots = collision_slots + 1;
            collision_wasted_us = collision_wasted_us + reservation_us;
            collision_wasted_measure_us = ...
                collision_wasted_measure_us + frame_overlap;
            if ~is_saturation
                for u = contenders
                    pid = head_packet_id(u);
                    collision_delay_us(pid) = ...
                        collision_delay_us(pid) + reservation_us;
                end
                for u = deferred
                    pid = head_packet_id(u);
                    probability_wait_us(pid) = ...
                        probability_wait_us(pid) + reservation_us;
                end
            end
            t_us = frame_end_us;
        else
            winner = contenders(1);
            data_start_us = frame_end_us;

            % Snapshot at DATA start: arrivals during the conn-slot count.
            enqueue_until(data_start_us);
            ids = trace.packet_ids_by_node{winner};
            head_w = queue_head(winner);
            tail_w = queue_tail(winner);
            if is_saturation
                if batch_mode
                    % Batch clearing: send the whole current queue.
                    batch_size = queue_count(winner);
                else
                    % SF-CB baseline: one reservation carries one packet.
                    batch_size = 1;
                end
            elseif batch_mode
                snapshot = ids(head_w:tail_w).';
                batch_size = numel(snapshot);
            else
                snapshot = ids(head_w);
                batch_size = 1;
            end
            data_end_us = data_start_us + batch_size * tp_us;
            actual_data_end_us = min(data_end_us, hard_end_us);

            enqueue_until(actual_data_end_us);

            data_overlap = interval_overlap_us(data_start_us, ...
                actual_data_end_us, left_measure_us, right_measure_us);
            service_area_measure_us = service_area_measure_us + data_overlap;
            system_area_measure_us = system_area_measure_us + ...
                sum(queue_count) * data_overlap;

            if data_end_us > hard_end_us
                t_us = hard_end_us;
                break;
            end

            success_slots = success_slots + 1;
            payload_success_overlap_us = payload_success_overlap_us + ...
                interval_overlap_us(data_start_us, data_end_us, ...
                    left_measure_us, right_measure_us);

            if is_saturation
                if batch_size > 0
                    queue_count(winner) = queue_count(winner) - batch_size;
                    if data_end_us >= left_measure_us && ...
                            data_end_us < right_measure_us
                        saturation_per_node_completions(winner) = ...
                            saturation_per_node_completions(winner) + batch_size;
                    end
                end
            else
                for k = 1:batch_size
                    pid = snapshot(k);
                    completion_us(pid) = data_start_us + k * tp_us;
                    data_delay_us(pid) = tp_us;
                    if isnan(hol_us(pid))
                        % Batch packets never become individual heads; they
                        % share the batch HOL (the head packet's queue time).
                        hol_us(pid) = hol_us(snapshot(1));
                    end
                end
                if batch_size >= 1
                    control_delay_us(snapshot(1)) = reservation_us;
                end
                % Monotone head/tail pointers: after the queue empties the
                % pointers are kept at tail+1 so the next arrival occupies
                % a fresh position (resetting to 1 would resurrect the
                % already-completed first packet id).
                queue_head(winner) = queue_head(winner) + batch_size;
                queue_count(winner) = queue_count(winner) - batch_size;
                if queue_head(winner) <= queue_tail(winner)
                    next_pid = ids(queue_head(winner));
                    hol_us(next_pid) = data_end_us;
                else
                    queue_count(winner) = 0;
                end
            end
            t_us = data_end_us;
        end
    end

    sim_end_us = min(t_us, hard_end_us);
    enqueue_until(sim_end_us);
    if ~is_saturation && next_arrival <= n_packets
        error('simulate_slotted_lightload:UnseenArrivals', ...
            'Simulation ended before all arrivals were enqueued.');
    end
    final_backlog = sum(queue_count);

    diagnostics = struct();
    diagnostics.idle_slots = idle_slots;
    diagnostics.collision_slots = collision_slots;
    diagnostics.success_slots = success_slots;
    diagnostics.attempts_total = attempts_total;
    diagnostics.idle_wasted_us = idle_wasted_us;
    diagnostics.idle_wasted_measure_us = idle_wasted_measure_us;
    diagnostics.collision_waste_us = collision_wasted_us;
    diagnostics.collision_waste_measure_us = collision_wasted_measure_us;
    diagnostics.payload_success_overlap_us = payload_success_overlap_us;
    diagnostics.service_area_definition = ...
        'active payload-transmitter area (successful singleton reservation)';
    if batch_mode
        diagnostics.protocol = 'batch_clear';
    else
        diagnostics.protocol = 'sf_cb';
    end
    diagnostics.batch_snapshot_at = 'data_start';

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
        packet_log.boundary_wait_us = boundary_wait_us;
        packet_log.difs_wait_us = difs_wait_us;
        packet_log.collision_delay_us = collision_delay_us;
        packet_log.control_delay_us = control_delay_us;
        packet_log.data_delay_us = data_delay_us;
        packet_log.busy_nav_wait_us = busy_nav_wait_us;
        packet_log.other_access_delay_us = other_access_delay_us;
        raw.packet_log = packet_log;
    end

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
            if ~is_saturation && queue_count(u) == 1
                hol_us(pid) = arrival_us(pid);
            end
            next_arrival = next_arrival + 1;
        end
    end
end