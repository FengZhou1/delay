cfg = default_lightload_sfcb_config('analysis','saturation');
scenario = prepare_scenario_v2(cfg, cfg.topology_seed);
for M = [1 3 6]
    trace = build_sat_trace(cfg, M);
    fprintf('=== M=%d ===\n', M);
    for prot = {'unslotted','sb_cb'}
        q = 0.0015;
        r = simulate_sfcb_lightload_variant(prot{1}, trace, scenario, cfg, M, q, 1001);
        d = r.diagnostics;
        if isfield(d,'rts_attempts')
            fprintf('  %-10s q=%.4g: attempts=%d success=%d coll=%d apbusy=%d timeouts=%d data_succ=%d data_fail_sinr=%d\n', ...
                prot{1}, q, d.rts_attempts, d.rts_success, d.rts_fail_collision, d.rts_fail_ap_busy, ...
                d.rts_response_timeouts, d.data_success, d.data_fail_sinr);
        else
            fprintf('  %-10s q=%.4g: attempts_total=%d success_slots=%d collision_slots=%d idle_slots=%d\n', ...
                prot{1}, q, d.attempts_total, d.success_slots, d.collision_slots, d.idle_slots);
        end
    end
end
function trace = build_sat_trace(cfg, M)
    timing = protocol_timing(cfg);
    Tp = timing.CONN_SLOT_US * M;
    horizon = cfg.sim_hard_end_us;
    n_periods = max(1, ceil(horizon / Tp));
    period_times = (0:n_periods).' * Tp;
    n_nodes = cfg.n_nodes;
    times_us = repmat(period_times.', n_nodes, 1);
    node_id = repmat((1:n_nodes).', 1, numel(period_times));
    times_us = times_us(:); node_id = node_id(:);
    [times_us, order] = sort(times_us); node_id = node_id(order);
    packet_ids_by_node = cell(n_nodes,1);
    for u = 1:n_nodes
        packet_ids_by_node{u} = find(node_id == u).';
    end
    trace = struct('times_us',times_us,'node_id',node_id,...
        'packet_ids_by_node',{packet_ids_by_node},'n_packets',numel(times_us),...
        'arrival_end_us',cfg.arrival_end_us,'hard_end_us',cfg.sim_hard_end_us);
end
