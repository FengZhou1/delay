function result = finalize_saturation_result(raw, cfg, protocol, M, q)
%FINALIZE_SATURATION_RESULT Summarize one persistent-backlog protocol run.

    required = {'payload_success_overlap_us','sim_end_us', ...
        'saturation_per_node_completions','diagnostics'};
    for i = 1:numel(required)
        if ~isfield(raw,required{i})
            error('finalize_saturation_result:MissingRawField', ...
                'raw.%s is required.',required{i});
        end
    end

    per_node = double(raw.saturation_per_node_completions(:));
    if numel(per_node) ~= cfg.n_nodes || any(per_node < 0)
        error('finalize_saturation_result:PerNodeCounts', ...
            'Per-node saturation completion counts are invalid.');
    end
    measure_s = double(cfg.measure_us) * 1e-6;
    completed = sum(per_node);
    pkt_s = completed / measure_s;
    payload_airtime = double(raw.payload_success_overlap_us) / ...
        double(cfg.measure_us);
    if payload_airtime < -1e-12 || payload_airtime > 1 + 1e-9
        error('finalize_saturation_result:AirtimeRange', ...
            'Successful payload airtime %.12g is outside [0,1].',payload_airtime);
    end
    payload_airtime = min(1,max(0,payload_airtime));
    normalized_goodput = double(M) * pkt_s;

    if isfield(cfg,'payload_bits_M1') && isfinite(cfg.payload_bits_M1)
        goodput_bit_s = normalized_goodput * double(cfg.payload_bits_M1);
    else
        goodput_bit_s = NaN;
    end
    if sum(per_node.^2) > 0
        jain = sum(per_node)^2 / (cfg.n_nodes * sum(per_node.^2));
    else
        jain = NaN;
    end

    timing = mmw_timing_config(cfg);
    summary = struct();
    summary.protocol = char(protocol);
    summary.study_type = 'saturation_throughput';
    summary.M = double(M);
    summary.Tp_us = timing.CONN_SLOT_US * double(M);
    summary.q = double(q);
    summary.n_nodes = double(cfg.n_nodes);
    summary.warmup_us = double(cfg.warmup_us);
    summary.measure_us = double(cfg.measure_us);
    summary.completed_packets = completed;
    summary.completed_pkt_s = pkt_s;
    summary.normalized_goodput_units_s = normalized_goodput;
    summary.goodput_bit_s = goodput_bit_s;
    summary.payload_airtime_fraction = payload_airtime;
    summary.jain_fairness = jain;
    summary.sim_end_us = double(raw.sim_end_us);
    summary.saturated = true;

    diagnostics = raw.diagnostics;
    diagnostics.saturation_per_node_completions = per_node;
    diagnostics.saturation_completed_measure = completed;
    diagnostics.payload_airtime_fraction = payload_airtime;

    result = struct('summary',summary, 'packet_log',struct(), ...
        'diagnostics',diagnostics);
end
