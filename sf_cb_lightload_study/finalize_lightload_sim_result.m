function result = finalize_lightload_sim_result(raw, trace, cfg, protocol, M, q)
%FINALIZE_LIGHTLOAD_SIM_RESULT Summarize one non-saturated light-load run.
% Mirrors the semantics of the parent finalize_sim_result (measurement
% cohort = arrivals in [warmup, arrival_end), conditional mean delays over
% completed cohort packets) but uses the study's own real-time conn-slot
% (162.5 us) instead of the parent mmw_timing_config value.

    timing = protocol_timing(cfg);
    pkt = raw.packet_log;
    completed = isfinite(pkt.completion_us);
    if any(completed & (~isfinite(pkt.hol_us) | ...
            pkt.completion_us < pkt.hol_us))
        error('finalize_lightload_sim_result:BadCompletion', ...
            'Completed packet has an invalid HOL or completion time.');
    end

    total_delay = pkt.completion_us - pkt.arrival_us;
    queue_delay = pkt.hol_us - pkt.arrival_us;
    access_delay = pkt.completion_us - pkt.hol_us;
    if any(abs(total_delay(completed) - queue_delay(completed) - ...
               access_delay(completed)) > 1e-9)
        error('finalize_lightload_sim_result:DelayIdentity', ...
            'Per-packet delay identity is violated.');
    end

    all_completed = sum(completed);
    if trace.n_packets ~= all_completed + raw.final_backlog
        error('finalize_lightload_sim_result:PacketConservation', ...
            'Packet conservation failed: arrived=%d completed=%d backlog=%d.', ...
            trace.n_packets, all_completed, raw.final_backlog);
    end

    left = double(cfg.warmup_us);
    right = double(cfg.arrival_end_us);
    measure_s = double(cfg.measure_us) * 1e-6;
    cohort = pkt.arrival_us >= left & pkt.arrival_us < right;
    cohort_completed = cohort & completed;
    completed_in_window = completed & pkt.completion_us >= left & ...
                          pkt.completion_us < right;

    n_arrived = sum(cohort);
    n_completed_cohort = sum(cohort_completed);
    n_censored = n_arrived - n_completed_cohort;
    completion_ratio = n_completed_cohort / max(1, n_arrived);
    departures = sum(completed_in_window);
    arrival_rate_system = n_arrived / measure_s;
    departure_rate_system = departures / measure_s;
    goodput_pkt_s = departure_rate_system;
    normalized_goodput = M * goodput_pkt_s;

    d = total_delay(cohort_completed);
    qd = queue_delay(cohort_completed);
    ad = access_delay(cohort_completed);
    conditional_mean = safe_mean(d);
    conditional_p50 = safe_prctile(d, 50);
    conditional_p95 = safe_prctile(d, 95);
    conditional_p99 = safe_prctile(d, 99);

    rate_tol = max(1, double(cfg.stability_rate_tolerance) * ...
                   max(arrival_rate_system, 1));
    rate_ok = abs(departure_rate_system - arrival_rate_system) <= rate_tol;
    allowed_censored = floor(double(cfg.stability_censor_tolerance) * n_arrived);
    censor_ok = n_censored <= allowed_censored;
    stable = n_arrived > 0 && n_completed_cohort > 0 && ...
             completion_ratio >= 0.99 && rate_ok;

    if stable && ~isempty(d)
        mean_delay = conditional_mean;
        mean_qd = safe_mean(qd);
        mean_ad = safe_mean(ad);
    else
        mean_delay = NaN;
        mean_qd = NaN;
        mean_ad = NaN;
    end

    mean_system = raw.system_area_measure_us / double(cfg.measure_us);
    mean_service = raw.service_area_measure_us / double(cfg.measure_us);
    mean_waiting = max(0, mean_system - mean_service);

    attempts_total = sum(pkt.attempts);
    attempts_completed = sum(pkt.attempts(cohort_completed));
    retransmissions_completed = sum(max(0, pkt.attempts(cohort_completed) - 1));
    if n_completed_cohort > 0
        mean_attempts_completed = attempts_completed / n_completed_cohort;
    else
        mean_attempts_completed = NaN;
    end

    collision_waste_total = diagnostic_value(raw.diagnostics, ...
        {'collision_waste_us','collision_wasted_us'}, NaN);
    collision_waste_measure = diagnostic_value(raw.diagnostics, ...
        {'collision_waste_measure_us','collision_wasted_measure_us'}, NaN);

    completed_nodes = pkt.node_id(completed_in_window);
    if isempty(completed_nodes)
        per_node = zeros(double(cfg.n_nodes), 1);
    else
        per_node = accumarray(completed_nodes(:), 1, ...
                              [double(cfg.n_nodes), 1], @sum, 0);
    end
    if sum(per_node.^2) > 0
        jain = sum(per_node)^2 / (double(cfg.n_nodes) * sum(per_node.^2));
    else
        jain = NaN;
    end

    summary = struct();
    summary.protocol = char(protocol);
    summary.M = double(M);
    summary.Tp_us = timing.CONN_SLOT_US * double(M);
    summary.q = double(q);
    summary.lambda_per_node = double(trace.lambda_per_node);
    summary.n_arrived_total = double(trace.n_packets);
    summary.n_completed_total = all_completed;
    summary.n_arrived = n_arrived;
    summary.n_completed = n_completed_cohort;
    summary.n_departures_window = departures;
    summary.n_censored = n_censored;
    summary.completion_ratio = completion_ratio;
    summary.final_backlog = raw.final_backlog;
    summary.arrival_rate_pkt_s = arrival_rate_system;
    summary.goodput_pkt_s = goodput_pkt_s;
    summary.normalized_goodput_units_s = normalized_goodput;
    summary.payload_airtime = raw.payload_success_overlap_us / ...
        double(cfg.measure_us);
    summary.mean_delay_us = mean_delay;
    summary.mean_queue_delay_us = mean_qd;
    summary.mean_access_delay_us = mean_ad;
    summary.conditional_mean_delay_us = conditional_mean;
    summary.p50_delay_us = conditional_p50;
    summary.p95_delay_us = conditional_p95;
    summary.p99_delay_us = conditional_p99;
    summary.mean_system_packets = mean_system;
    summary.mean_waiting_packets = mean_waiting;
    summary.mean_service_packets = mean_service;
    summary.jain_fairness = jain;
    summary.attempts_total = attempts_total;
    summary.attempts_completed_cohort = attempts_completed;
    summary.retransmissions_completed_cohort = retransmissions_completed;
    summary.mean_attempts_completed = mean_attempts_completed;
    summary.collision_waste_us_total = collision_waste_total;
    summary.collision_waste_us_measure = collision_waste_measure;
    summary.stability_rate_ok = rate_ok;
    summary.stability_censor_ok = censor_ok;
    summary.stable = stable;
    summary.sim_end_us = raw.sim_end_us;

    pkt.queue_delay_us = queue_delay;
    pkt.access_delay_us = access_delay;
    pkt.total_delay_us = total_delay;
    pkt.status = uint8(completed);
    pkt.is_censored = ~completed;
    pkt.in_measurement_cohort = cohort;

    result = struct('summary', summary, 'packet_log', pkt, ...
                    'diagnostics', raw.diagnostics);
end

function value = diagnostic_value(diagnostics, names, fallback)
    value = fallback;
    for i = 1:numel(names)
        if isfield(diagnostics, names{i})
            value = diagnostics.(names{i});
            return;
        end
    end
end

function value = safe_mean(x)
    if isempty(x)
        value = NaN;
    else
        value = mean(x);
    end
end

function value = safe_prctile(x, p)
    if isempty(x)
        value = NaN;
    else
        value = prctile(x, p);
    end
end