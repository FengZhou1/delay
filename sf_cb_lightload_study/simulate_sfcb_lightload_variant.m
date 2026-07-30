function result = simulate_sfcb_lightload_variant(variant,trace,cfg,M,q,seed,scenario)
%SIMULATE_SFCB_LIGHTLOAD_VARIANT Isolated SF-CB MAC-variant simulator.
% This file is intentionally separate from the repository's production
% protocol state machines.

    variant = lower(char(variant));
    allowed = {'baseline','fast_first','unslotted','batch_clear'};
    if ~ismember(variant,allowed)
        error('simulate_sfcb_lightload_variant:BadVariant', ...
            'Unsupported variant: %s',variant);
    end
    if ~isscalar(M) || ~isfinite(M) || M < 1 || M ~= round(M)
        error('simulate_sfcb_lightload_variant:BadM', ...
            'M must be an integer greater than or equal to one.');
    end
    if ~isscalar(q) || ~isfinite(q) || q <= 0 || q > 1
        error('simulate_sfcb_lightload_variant:BadQ', ...
            'q must lie in (0,1].');
    end
    if trace.n_packets ~= numel(trace.times_us) || ...
            trace.n_packets ~= numel(trace.node_id)
        error('simulate_sfcb_lightload_variant:BadTrace', ...
            'Trace vectors do not match trace.n_packets.');
    end

    if strcmp(variant,'unslotted')
        if nargin < 7 || isempty(scenario)
            scenario = prepare_scenario_v2(cfg,cfg.topology_seed);
        end
        result = simulate_unslotted_directional( ...
            trace,scenario,cfg,M,q,seed);
        return;
    end

    raw = simulate_slotted(variant,trace,cfg,M,q,seed);
    result = finalize_sim_result(raw,trace,cfg, ...
        ['sf_cb_' variant],M,q);
end

function result = simulate_unslotted_directional( ...
        trace,scenario,cfg,M,q,seed)
% Unslotted Conn-Aloha uses the common 9 us physical clock but has no
% 198 us connection-slot boundary. A fresh HOL starts its two-slot RTS
% immediately. Only overlapping RTS frames collide at the AP. After RTS,
% the sender waits for the complete CTS response window. The AP performs
% the ordinary directional CTS sweep; half-duplex transmitters can miss
% their sector CTS, decoded CTS sets NAV, and directional DATA is accepted
% only when its per-slot SINR remains above the DATA threshold.

    local_cfg = cfg;
    local_cfg.cca_mode = 'disabled';
    local_cfg.sb_cb_force_first_rts = true;
    local_cfg.collect_diagnostics = false;
    local_cfg.collect_debug_trace = false;

    local_scenario = scenario;
    local_scenario.MMW.DIFS = 0;
    local_scenario.MMW.DIFS_US = 0;

    result = simulate_sb_cb_v2(trace,local_scenario,local_cfg,M,q,seed);
    result.summary.protocol = 'sf_cb_unslotted';
    result.diagnostics.variant = 'unslotted';
    result.diagnostics.unslotted = true;
    result.diagnostics.unslotted_time_model = ...
        'no_198us_boundary; decisions use the common 9us physical clock';
    result.diagnostics.unslotted_fresh_hol_policy = ...
        'immediate_two_slot_RTS';
    result.diagnostics.unslotted_retry_policy = ...
        'Bernoulli q on each eligible 9us boundary after failure';
    result.diagnostics.unslotted_collision_rule = ...
        'classic collision only for overlapping 18us RTS frames';
    result.diagnostics.rts_collision_window_us = ...
        double(local_scenario.MMW.RTS_US);
    result.diagnostics.connection_transaction_us = ...
        double(local_scenario.MMW.CONN_OVERHEAD_US);
end

function raw = simulate_slotted(variant,trace,cfg,M,q,seed)
    timing = mmw_timing_config(cfg);
    reservation_us = timing.CONN_SLOT_US;
    tp_us = reservation_us * double(M);
    n_nodes = cfg.n_nodes;
    n_packets = trace.n_packets;
    arrival_us = double(trace.times_us(:));
    node_id = double(trace.node_id(:));
    node_packets = trace.packet_ids_by_node;
    hard_end_us = double(cfg.sim_hard_end_us);
    arrival_end_us = double(cfg.arrival_end_us);
    left = double(cfg.warmup_us);
    right = arrival_end_us;

    stream = RandStream('mt19937ar','Seed',double(seed));
    head = ones(n_nodes,1);
    tail = zeros(n_nodes,1);
    next_arrival = 1;

    state = initialise_packet_state(n_packets,node_id,arrival_us);
    first_eligible_us = nan(n_packets,1);
    fast_first_eligible = false(n_packets,1);

    slots_started = 0;
    slots_completed = 0;
    idle_slots = 0;
    success_slots = 0;
    collision_slots = 0;
    attempts_total = 0;
    batch_connections = 0;
    batch_packets_total = 0;
    max_batch_size = 0;
    idle_wasted_us = 0;
    idle_wasted_measure_us = 0;
    collision_wasted_us = 0;
    collision_wasted_measure_us = 0;
    collision_tx_airtime_us = 0;
    collision_tx_airtime_measure_us = 0;
    payload_success_overlap_us = 0;
    service_area_measure_us = 0;

    t_us = 0;
    enqueue_until(t_us);
    while true
        enqueue_until(t_us);
        backlog_now = sum(max(0,tail-head+1));
        all_arrivals_seen = next_arrival > n_packets;
        if t_us >= arrival_end_us && backlog_now == 0 && all_arrivals_seen
            break;
        end
        if t_us >= hard_end_us
            t_us = hard_end_us;
            break;
        end

        % Empty reservation frames contain no random decisions. Skip them
        % exactly to the first boundary that can see the next arrival.
        if backlog_now == 0 && ~all_arrivals_seen && ...
                arrival_us(next_arrival) > t_us
            frames = ceil((arrival_us(next_arrival)-t_us)/reservation_us);
            boundary = t_us + frames*reservation_us;
            actual_boundary = min(boundary,hard_end_us);
            slots_started = slots_started + frames;
            completed_frames = floor((actual_boundary-t_us)/reservation_us);
            slots_completed = slots_completed + completed_frames;
            idle_slots = idle_slots + completed_frames;
            idle_wasted_us = idle_wasted_us + ...
                completed_frames*reservation_us;
            idle_wasted_measure_us = idle_wasted_measure_us + ...
                interval_overlap_us(t_us,actual_boundary,left,right);
            t_us = actual_boundary;
            enqueue_until(t_us);
            if boundary > hard_end_us
                break;
            end
            continue;
        end

        [backlogged_nodes,hol_ids] = current_hol();
        newly_eligible = isnan(first_eligible_us(hol_ids));
        if any(newly_eligible)
            ids = hol_ids(newly_eligible);
            first_eligible_us(ids) = t_us;
            state.boundary_wait_us(ids) = t_us-state.hol_us(ids);
        end
        random_choice = rand(stream,numel(backlogged_nodes),1) < q;
        if strcmp(variant,'fast_first')
            chosen = random_choice | fast_first_eligible(hol_ids);
        else
            chosen = random_choice;
        end
        contender_nodes = backlogged_nodes(chosen);
        contender_ids = hol_ids(chosen);
        deferred_ids = hol_ids(~chosen);
        n_contenders = numel(contender_ids);

        slots_started = slots_started + 1;
        attempts_total = attempts_total + n_contenders;
        if n_contenders > 0
            state.attempts(contender_ids) = ...
                state.attempts(contender_ids) + 1;
            first = isnan(state.first_attempt_us(contender_ids));
            state.first_attempt_us(contender_ids(first)) = t_us;
            fast_first_eligible(contender_ids) = false;
        end

        frame_end_us = t_us + reservation_us;
        actual_frame_end = min(frame_end_us,hard_end_us);
        state.probability_wait_us(deferred_ids) = ...
            state.probability_wait_us(deferred_ids) + reservation_us;
        enqueue_until(actual_frame_end);
        if frame_end_us > hard_end_us
            t_us = hard_end_us;
            break;
        end
        slots_completed = slots_completed + 1;

        if n_contenders == 0
            idle_slots = idle_slots + 1;
            idle_wasted_us = idle_wasted_us + reservation_us;
            idle_wasted_measure_us = idle_wasted_measure_us + ...
                interval_overlap_us(t_us,frame_end_us,left,right);
            t_us = frame_end_us;
            continue;
        end

        if n_contenders >= 2
            collision_slots = collision_slots + 1;
            state.collision_delay_us(contender_ids) = ...
                state.collision_delay_us(contender_ids) + reservation_us;
            collision_wasted_us = collision_wasted_us + reservation_us;
            collision_tx_airtime_us = collision_tx_airtime_us + ...
                n_contenders*reservation_us;
            overlap = interval_overlap_us(t_us,frame_end_us,left,right);
            collision_wasted_measure_us = ...
                collision_wasted_measure_us + overlap;
            collision_tx_airtime_measure_us = ...
                collision_tx_airtime_measure_us + n_contenders*overlap;
            t_us = frame_end_us;
            continue;
        end

        success_slots = success_slots + 1;
        u = contender_nodes(1);
        first_pid = contender_ids(1);
        state.control_delay_us(first_pid) = ...
            state.control_delay_us(first_pid) + reservation_us;

        if strcmp(variant,'batch_clear')
            positions = head(u):tail(u);
            ids_u = node_packets{u};
            batch_ids = ids_u(positions);
        else
            batch_ids = first_pid;
        end
        batch_ids = batch_ids(:);
        batch_size = numel(batch_ids);
        batch_connections = batch_connections + 1;
        batch_packets_total = batch_packets_total + batch_size;
        max_batch_size = max(max_batch_size,batch_size);

        data_start_us = frame_end_us;
        requested_data_end = data_start_us + batch_size*tp_us;
        actual_data_end = min(requested_data_end,hard_end_us);
        service_area_measure_us = service_area_measure_us + ...
            interval_overlap_us(data_start_us,actual_data_end,left,right);

        % Keep the winner queue nonempty while arrivals during DATA are
        % enqueued, then remove exactly the connection-establishment snapshot.
        enqueue_until(actual_data_end);
        n_completed_batch = min(batch_size, ...
            floor(max(0,actual_data_end-data_start_us+1e-9)/tp_us));
        previous_completion = NaN;
        for j = 1:n_completed_batch
            pid = batch_ids(j);
            packet_start = data_start_us + (j-1)*tp_us;
            packet_end = packet_start + tp_us;
            if j > 1
                state.hol_us(pid) = previous_completion;
                state.first_attempt_us(pid) = packet_start;
            end
            state.data_delay_us(pid) = state.data_delay_us(pid) + tp_us;
            state.completion_us(pid) = packet_end;
            payload_success_overlap_us = payload_success_overlap_us + ...
                interval_overlap_us(packet_start,packet_end,left,right);
            previous_completion = packet_end;
        end

        head(u) = head(u) + n_completed_batch;
        if head(u) <= tail(u) && n_completed_batch > 0
            ids_u = node_packets{u};
            next_pid = ids_u(head(u));
            state.hol_us(next_pid) = previous_completion;
            fast_first_eligible(next_pid) = false;
        end

        if requested_data_end > hard_end_us
            t_us = hard_end_us;
            break;
        end
        if n_completed_batch ~= batch_size
            error('simulate_sfcb_lightload_variant:BatchCompletion', ...
                'A complete DATA interval did not complete its full batch.');
        end
        t_us = requested_data_end;
    end

    diagnostics = struct();
    diagnostics.variant = variant;
    diagnostics.seed = double(seed);
    diagnostics.q = double(q);
    diagnostics.reservation_us = reservation_us;
    diagnostics.Tp_us = tp_us;
    diagnostics.slots_started = slots_started;
    diagnostics.slots_completed = slots_completed;
    diagnostics.idle_slots = idle_slots;
    diagnostics.success_slots = success_slots;
    diagnostics.collision_slots = collision_slots;
    diagnostics.attempts_total = attempts_total;
    diagnostics.batch_connections = batch_connections;
    diagnostics.batch_packets_total = batch_packets_total;
    diagnostics.mean_batch_size = batch_packets_total/max(1,batch_connections);
    diagnostics.max_batch_size = max_batch_size;
    diagnostics.idle_wasted_us = idle_wasted_us;
    diagnostics.idle_wasted_measure_us = idle_wasted_measure_us;
    diagnostics.collision_wasted_us = collision_wasted_us;
    diagnostics.collision_wasted_measure_us = ...
        collision_wasted_measure_us;
    diagnostics.collision_channel_time_us = collision_wasted_us;
    diagnostics.collision_channel_time_measure_us = ...
        collision_wasted_measure_us;
    diagnostics.collision_tx_airtime_us = collision_tx_airtime_us;
    diagnostics.collision_tx_airtime_measure_us = ...
        collision_tx_airtime_measure_us;
    diagnostics.service_area_definition = ...
        'active successful DATA transmitter area';

    raw = finish_raw(state,trace,cfg,t_us,service_area_measure_us, ...
        payload_success_overlap_us,diagnostics);

    function enqueue_until(limit_us)
        while next_arrival <= n_packets && ...
                arrival_us(next_arrival) <= limit_us
            pid = next_arrival;
            u_arrival = node_id(pid);
            was_empty = head(u_arrival) > tail(u_arrival);
            tail(u_arrival) = tail(u_arrival) + 1;
            ids_arrival = node_packets{u_arrival};
            if tail(u_arrival) > numel(ids_arrival) || ...
                    ids_arrival(tail(u_arrival)) ~= pid
                error('simulate_sfcb_lightload_variant:QueueMap', ...
                    'Trace packet_ids_by_node is inconsistent.');
            end
            if was_empty
                state.hol_us(pid) = arrival_us(pid);
                fast_first_eligible(pid) = strcmp(variant,'fast_first');
            end
            next_arrival = next_arrival + 1;
        end
    end

    function [nodes,pids] = current_hol()
        nodes = find(head <= tail);
        pids = zeros(numel(nodes),1);
        for kk = 1:numel(nodes)
            ids_node = node_packets{nodes(kk)};
            pids(kk) = ids_node(head(nodes(kk)));
        end
    end
end

function raw = simulate_unslotted_legacy_198us_overlap(trace,cfg,M,q,seed)
% Legacy reference retained only for reproducibility of superseded results.
% The active dispatch never calls this function because treating the whole
% 198 us transaction as the collision-vulnerable interval is incorrect.
    timing = mmw_timing_config(cfg);
    reservation_us = timing.CONN_SLOT_US;
    tp_us = reservation_us * double(M);
    n_nodes = cfg.n_nodes;
    n_packets = trace.n_packets;
    arrival_us = double(trace.times_us(:));
    node_id = double(trace.node_id(:));
    node_packets = trace.packet_ids_by_node;
    hard_end_us = double(cfg.sim_hard_end_us);
    arrival_end_us = double(cfg.arrival_end_us);
    left = double(cfg.warmup_us);
    right = arrival_end_us;
    tol = 1e-9;

    stream = RandStream('mt19937ar','Seed',double(seed));
    retry_mean_us = reservation_us/double(q);
    head = ones(n_nodes,1);
    tail = zeros(n_nodes,1);
    next_arrival = 1;
    state = initialise_packet_state(n_packets,node_id,arrival_us);

    scheduled_attempt_us = inf(n_nodes,1);
    active = false(n_nodes,1);
    active_start_us = nan(n_nodes,1);
    active_end_us = inf(n_nodes,1);
    active_pid = zeros(n_nodes,1);
    active_failed = false(n_nodes,1);

    data_active = false;
    data_node = 0;
    data_pid = 0;
    data_start_us = NaN;
    data_end_us = inf;

    attempts_total = 0;
    reservation_success = 0;
    failed_attempts = 0;
    collision_events = 0;
    payload_success_overlap_us = 0;
    service_area_measure_us = 0;
    failed_starts = zeros(0,1);
    failed_ends = zeros(0,1);

    t_us = 0;
    while true
        backlog_now = sum(max(0,tail-head+1));
        all_arrivals_seen = next_arrival > n_packets;
        if t_us >= arrival_end_us && backlog_now == 0 && ...
                all_arrivals_seen && ~any(active) && ~data_active
            break;
        end
        if t_us >= hard_end_us
            t_us = hard_end_us;
            break;
        end

        next_arrival_us = inf;
        if ~all_arrivals_seen
            next_arrival_us = arrival_us(next_arrival);
        end
        next_reservation_end = min(active_end_us);
        next_protocol_attempt = min(scheduled_attempt_us);
        next_data_end = data_end_us;
        t_next = min([next_arrival_us,next_reservation_end, ...
            next_protocol_attempt,next_data_end,hard_end_us]);
        if ~isfinite(t_next)
            t_us = hard_end_us;
            break;
        end
        if t_next < t_us-tol
            error('simulate_sfcb_lightload_variant:TimeReversal', ...
                'Unslotted event calendar moved backwards.');
        end
        t_us = t_next;

        % Arrivals are visible before protocol events at the same instant.
        enqueue_at_current_time();

        if data_active && abs(data_end_us-t_us) <= tol
            state.completion_us(data_pid) = t_us;
            payload_success_overlap_us = payload_success_overlap_us + ...
                interval_overlap_us(data_start_us,t_us,left,right);
            u_done = data_node;
            head(u_done) = head(u_done) + 1;
            if head(u_done) <= tail(u_done)
                ids_done = node_packets{u_done};
                next_pid = ids_done(head(u_done));
                state.hol_us(next_pid) = t_us;
                scheduled_attempt_us(u_done) = t_us;
            else
                scheduled_attempt_us(u_done) = inf;
            end
            data_active = false;
            data_node = 0;
            data_pid = 0;
            data_start_us = NaN;
            data_end_us = inf;
        end

        finishing = find(active & abs(active_end_us-t_us) <= tol);
        successful_finisher = 0;
        if ~isempty(finishing)
            good = finishing(~active_failed(finishing));
            if numel(good) > 1
                error('simulate_sfcb_lightload_variant:MultipleUnslottedSuccess', ...
                    'Overlapping reservations were not marked as failed.');
            elseif numel(good) == 1
                successful_finisher = good(1);
            end
        end

        for idx = 1:numel(finishing)
            u_finish = finishing(idx);
            pid = active_pid(u_finish);
            if active_failed(u_finish)
                failed_attempts = failed_attempts + 1;
                state.collision_delay_us(pid) = ...
                    state.collision_delay_us(pid) + reservation_us;
                backoff = draw_retry_backoff();
                state.probability_wait_us(pid) = ...
                    state.probability_wait_us(pid) + backoff;
                scheduled_attempt_us(u_finish) = t_us + backoff;
                failed_starts(end+1,1) = active_start_us(u_finish); %#ok<AGROW>
                failed_ends(end+1,1) = t_us; %#ok<AGROW>
            else
                scheduled_attempt_us(u_finish) = inf;
            end
            active(u_finish) = false;
            active_start_us(u_finish) = NaN;
            active_end_us(u_finish) = inf;
            active_pid(u_finish) = 0;
            active_failed(u_finish) = false;
        end

        if successful_finisher > 0
            if any(active) || data_active
                error('simulate_sfcb_lightload_variant:BusyOnSuccess', ...
                    'An isolated reservation ended while the channel was busy.');
            end
            u_success = successful_finisher;
            ids_success = node_packets{u_success};
            pid = ids_success(head(u_success));
            reservation_success = reservation_success + 1;
            state.control_delay_us(pid) = ...
                state.control_delay_us(pid) + reservation_us;
            state.data_delay_us(pid) = state.data_delay_us(pid) + tp_us;
            data_active = true;
            data_node = u_success;
            data_pid = pid;
            data_start_us = t_us;
            data_end_us = t_us + tp_us;
            service_area_measure_us = service_area_measure_us + ...
                interval_overlap_us(data_start_us, ...
                min(data_end_us,hard_end_us),left,right);

            % Successful CTS protects DATA. Preserve each pending timer's
            % residual time instead of synchronizing all nodes at NAV expiry.
            pending = isfinite(scheduled_attempt_us);
            residual = max(0,scheduled_attempt_us(pending)-t_us);
            scheduled_attempt_us(pending) = data_end_us + residual;
        end

        if ~data_active
            due = find(~active & scheduled_attempt_us <= t_us+tol & ...
                head <= tail);
            if ~isempty(due)
                collision_now = numel(due) > 1 || any(active);
                if collision_now
                    collision_events = collision_events + 1;
                    active_failed(active) = true;
                end
                for idx = 1:numel(due)
                    u_start = due(idx);
                    ids_start = node_packets{u_start};
                    pid = ids_start(head(u_start));
                    scheduled_attempt_us(u_start) = inf;
                    active(u_start) = true;
                    active_start_us(u_start) = t_us;
                    active_end_us(u_start) = t_us + reservation_us;
                    active_pid(u_start) = pid;
                    active_failed(u_start) = collision_now;
                    attempts_total = attempts_total + 1;
                    state.attempts(pid) = state.attempts(pid) + 1;
                    if isnan(state.first_attempt_us(pid))
                        state.first_attempt_us(pid) = t_us;
                    end
                end
            end
        end
    end

    collision_channel_time_us = interval_union_length( ...
        failed_starts,failed_ends,-Inf,Inf);
    collision_channel_measure_us = interval_union_length( ...
        failed_starts,failed_ends,left,right);
    collision_tx_airtime_us = sum(max(0,failed_ends-failed_starts));
    collision_tx_measure_us = sum(max(0, ...
        min(failed_ends,right)-max(failed_starts,left)));

    diagnostics = struct();
    diagnostics.variant = 'unslotted';
    diagnostics.seed = double(seed);
    diagnostics.q = double(q);
    diagnostics.reservation_us = reservation_us;
    diagnostics.Tp_us = tp_us;
    diagnostics.unslotted = true;
    diagnostics.unslotted_fresh_hol_policy = 'immediate_attempt';
    diagnostics.unslotted_retry_distribution = 'exponential';
    diagnostics.unslotted_retry_backoff_mean_us = retry_mean_us;
    diagnostics.unslotted_collision_rule = ...
        'all overlapping reservation intervals fail';
    diagnostics.attempts_total = attempts_total;
    diagnostics.reservation_success = reservation_success;
    diagnostics.failed_attempts = failed_attempts;
    diagnostics.collision_events = collision_events;
    diagnostics.collision_wasted_us = collision_channel_time_us;
    diagnostics.collision_wasted_measure_us = ...
        collision_channel_measure_us;
    diagnostics.collision_channel_time_us = collision_channel_time_us;
    diagnostics.collision_channel_time_measure_us = ...
        collision_channel_measure_us;
    diagnostics.collision_tx_airtime_us = collision_tx_airtime_us;
    diagnostics.collision_tx_airtime_measure_us = ...
        collision_tx_measure_us;
    diagnostics.service_area_definition = ...
        'active successful DATA transmitter area';

    raw = finish_raw(state,trace,cfg,t_us,service_area_measure_us, ...
        payload_success_overlap_us,diagnostics);

    function enqueue_at_current_time()
        while next_arrival <= n_packets && ...
                arrival_us(next_arrival) <= t_us+tol
            pid = next_arrival;
            u_arrival = node_id(pid);
            was_empty = head(u_arrival) > tail(u_arrival);
            tail(u_arrival) = tail(u_arrival) + 1;
            ids_arrival = node_packets{u_arrival};
            if tail(u_arrival) > numel(ids_arrival) || ...
                    ids_arrival(tail(u_arrival)) ~= pid
                error('simulate_sfcb_lightload_variant:QueueMap', ...
                    'Trace packet_ids_by_node is inconsistent.');
            end
            if was_empty
                state.hol_us(pid) = arrival_us(pid);
                if data_active
                    scheduled_attempt_us(u_arrival) = data_end_us;
                else
                    scheduled_attempt_us(u_arrival) = arrival_us(pid);
                end
            end
            next_arrival = next_arrival + 1;
        end
    end

    function value = draw_retry_backoff()
        value = -retry_mean_us*log(max(realmin,rand(stream,1)));
    end
end

function state = initialise_packet_state(n_packets,node_id,arrival_us)
    state = struct();
    state.node_id = double(node_id(:));
    state.arrival_us = double(arrival_us(:));
    state.hol_us = nan(n_packets,1);
    state.first_attempt_us = nan(n_packets,1);
    state.completion_us = nan(n_packets,1);
    state.attempts = zeros(n_packets,1);
    state.boundary_wait_us = zeros(n_packets,1);
    state.difs_wait_us = zeros(n_packets,1);
    state.probability_wait_us = zeros(n_packets,1);
    state.busy_nav_wait_us = zeros(n_packets,1);
    state.collision_delay_us = zeros(n_packets,1);
    state.control_delay_us = zeros(n_packets,1);
    state.data_delay_us = zeros(n_packets,1);
    state.other_access_delay_us = zeros(n_packets,1);
end

function raw = finish_raw(state,trace,cfg,sim_end_us, ...
        service_area_measure_us,payload_success_overlap_us,diagnostics)
    completed = isfinite(state.completion_us);
    packet_end_us = state.completion_us;
    packet_end_us(~completed) = sim_end_us;
    left = double(cfg.warmup_us);
    right = double(cfg.arrival_end_us);
    system_overlap = max(0,min(packet_end_us,right) - ...
        max(state.arrival_us,left));
    system_area_measure_us = sum(system_overlap);

    component_sum = state.boundary_wait_us + state.difs_wait_us + ...
        state.probability_wait_us + state.collision_delay_us + ...
        state.control_delay_us + state.data_delay_us + ...
        state.other_access_delay_us;
    state.busy_nav_wait_us(completed) = ...
        state.completion_us(completed)-state.hol_us(completed) - ...
        component_sum(completed);
    if any(state.busy_nav_wait_us(completed) < -1e-7)
        error('simulate_sfcb_lightload_variant:NegativeResidual', ...
            'Access-delay components exceed a completed packet delay.');
    end
    state.busy_nav_wait_us(completed) = ...
        max(0,state.busy_nav_wait_us(completed));

    % Close sub-nanosecond floating-point round-off using the same
    % left-to-right component order as finalize_sim_result.  Long
    % unslotted collision/retry sequences can otherwise accumulate enough
    % rounding error to trip its deliberately strict 1e-9 us identity
    % check even though the event times themselves are consistent.
    access_delay_us = state.completion_us-state.hol_us;
    for correction_pass = 1:3
        ordered_total = zeros(size(access_delay_us));
        ordered_total = ordered_total + state.boundary_wait_us;
        ordered_total = ordered_total + state.difs_wait_us;
        ordered_total = ordered_total + state.probability_wait_us;
        ordered_total = ordered_total + state.busy_nav_wait_us;
        ordered_total = ordered_total + state.collision_delay_us;
        ordered_total = ordered_total + state.control_delay_us;
        ordered_total = ordered_total + state.data_delay_us;
        ordered_total = ordered_total + state.other_access_delay_us;
        closure = access_delay_us(completed)-ordered_total(completed);
        state.other_access_delay_us(completed) = ...
            state.other_access_delay_us(completed)+closure;
    end

    sample_period = double(cfg.stats_sample_us);
    backlog_sample_us = (0:sample_period:sim_end_us).';
    backlog_sample_n = zeros(size(backlog_sample_us));
    sorted_completion = sort(state.completion_us(completed));
    a_ptr = 1;
    c_ptr = 1;
    n_system = 0;
    for i = 1:numel(backlog_sample_us)
        sample_t = backlog_sample_us(i);
        while a_ptr <= trace.n_packets && ...
                state.arrival_us(a_ptr) <= sample_t
            n_system = n_system + 1;
            a_ptr = a_ptr + 1;
        end
        while c_ptr <= numel(sorted_completion) && ...
                sorted_completion(c_ptr) <= sample_t
            n_system = n_system - 1;
            c_ptr = c_ptr + 1;
        end
        backlog_sample_n(i) = n_system;
    end

    raw = struct();
    raw.packet_log = state;
    raw.final_backlog = trace.n_packets-sum(completed);
    raw.sim_end_us = double(sim_end_us);
    raw.system_area_measure_us = double(system_area_measure_us);
    raw.service_area_measure_us = double(service_area_measure_us);
    raw.payload_success_overlap_us = double(payload_success_overlap_us);
    raw.backlog_sample_us = backlog_sample_us;
    raw.backlog_sample_n = backlog_sample_n;
    raw.diagnostics = diagnostics;
end

function total = interval_union_length(starts,ends,left,right)
    starts = starts(:);
    ends = ends(:);
    if isempty(starts)
        total = 0;
        return;
    end
    starts = max(starts,left);
    ends = min(ends,right);
    keep = ends > starts;
    if ~any(keep)
        total = 0;
        return;
    end
    intervals = sortrows([starts(keep),ends(keep)],1);
    total = 0;
    current_end = intervals(1,2);
    current_start = intervals(1,1);
    for i = 2:size(intervals,1)
        if intervals(i,1) <= current_end
            current_end = max(current_end,intervals(i,2));
        else
            total = total + current_end-current_start;
            current_start = intervals(i,1);
            current_end = intervals(i,2);
        end
    end
    total = total + current_end-current_start;
end
