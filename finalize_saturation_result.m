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
    if ismember(char(protocol),{'sf_cb','sb_cb','unslotted'})
        % Real-timing protocols use the exact 162.5-us connection slot.
        real_conn = cfg_real_conn_slot_us(cfg);
        effective_M = real_conn * double(M) / real_conn;
        payload_timing = saturation_payload_timing(cfg,M);
        payload_timing.effective_M = double(M);
        payload_timing.actual_payload_us = real_conn * double(M);
        payload_timing.nominal_payload_us = real_conn * double(M);
        normalized_goodput = double(M) * pkt_s;
    else
        payload_timing = saturation_payload_timing(cfg,M);
        normalized_goodput = payload_timing.effective_M * pkt_s;
    end
    effective_payload = payload_airtime;

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

    summary = struct();
    summary.protocol = char(protocol);
    summary.study_type = 'saturation_throughput';
    summary.M = double(M);
    summary.requested_Tp_us = payload_timing.nominal_payload_us;
    summary.Tp_us = payload_timing.actual_payload_us;
    summary.payload_slots = payload_timing.payload_slots;
    summary.effective_M = payload_timing.effective_M;
    summary.payload_quantization_error_us = ...
        payload_timing.quantization_error_us;
    summary.q = double(q);
    summary.n_nodes = double(cfg.n_nodes);
    summary.warmup_us = double(cfg.warmup_us);
    summary.measure_us = double(cfg.measure_us);
    summary.completed_packets = completed;
    summary.completed_pkt_s = pkt_s;
    summary.normalized_goodput_units_s = normalized_goodput;
    summary.goodput_bit_s = goodput_bit_s;
    summary.payload_airtime_fraction = payload_airtime;
    summary.effective_payload_fraction = effective_payload;
    summary.jain_fairness = jain;
    summary.sim_end_us = double(raw.sim_end_us);
    summary.saturated = true;

    diagnostics = raw.diagnostics;
    diagnostics.saturation_per_node_completions = per_node;
    diagnostics.saturation_completed_measure = completed;
    diagnostics.payload_airtime_fraction = payload_airtime;
    diagnostics.effective_payload_fraction = effective_payload;
    diagnostics.requested_Tp_us = payload_timing.nominal_payload_us;
    diagnostics.actual_Tp_us = payload_timing.actual_payload_us;
    diagnostics.payload_slots = payload_timing.payload_slots;
    diagnostics.effective_M = payload_timing.effective_M;

    result = struct('summary',summary, 'packet_log',struct(), ...
        'diagnostics',diagnostics);
end

function value = cfg_real_conn_slot_us(cfg)
    if isfield(cfg,'mmw_real_conn_slot_us') && ~isempty(cfg.mmw_real_conn_slot_us)
        value = double(cfg.mmw_real_conn_slot_us);
    else
        value = 14.5 + 16 + 8*14.5 + 16;   % 162.5 us fallback
    end
end
