function result = finalize_lightload_saturation_result(raw, cfg, protocol, M, q)
%FINALIZE_LIGHTLOAD_SATURATION_RESULT Summarize one saturated light-load run.
% Normalized throughput = successful payload airtime fraction inside the
% measurement window.  With the study's exact timing, one successful DATA
% frame is exactly M * 162.5 us, so we also report M * completed_pkt_s.

    timing = protocol_timing(cfg);
    per_node = double(raw.saturation_per_node_completions(:));
    if numel(per_node) ~= double(cfg.n_nodes) || any(per_node < 0)
        error('finalize_lightload_saturation_result:PerNodeCounts', ...
            'Per-node saturation completion counts are invalid.');
    end
    measure_s = double(cfg.measure_us) * 1e-6;
    completed = sum(per_node);
    pkt_s = completed / measure_s;
    payload_airtime = raw.payload_success_overlap_us / double(cfg.measure_us);
    if payload_airtime < -1e-12 || payload_airtime > 1 + 1e-9
        error('finalize_lightload_saturation_result:AirtimeRange', ...
            'Payload airtime %.12g is outside [0,1].', payload_airtime);
    end
    payload_airtime = min(1, max(0, payload_airtime));
    normalized_goodput = double(M) * pkt_s;
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
    summary.n_nodes = double(cfg.n_nodes);
    summary.warmup_us = double(cfg.warmup_us);
    summary.measure_us = double(cfg.measure_us);
    summary.completed_packets = completed;
    summary.completed_pkt_s = pkt_s;
    summary.normalized_goodput_units_s = normalized_goodput;
    summary.payload_airtime_fraction = payload_airtime;
    summary.jain_fairness = jain;
    summary.sim_end_us = double(raw.sim_end_us);
    summary.saturated = true;

    result = struct('summary', summary, 'packet_log', struct(), ...
        'diagnostics', raw.diagnostics);
end