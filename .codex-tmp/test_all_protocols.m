cfg = default_experiment_config('smoke');
cfg.n_nodes = 8;
cfg.cca_mode = 'oracle';
cfg.warmup_us = 0;
cfg.measure_us = 2000;
cfg.drain_max_us = 2000;
cfg.arrival_end_us = cfg.warmup_us + cfg.measure_us;
cfg.sim_hard_end_us = cfg.arrival_end_us + cfg.drain_max_us;
scenario = prepare_scenario_v2(cfg, 3);
trace = make_manual_arrival_trace(0, 1, cfg);
for M = [1 2]
    fprintf('=== M=%d ===\n', M);
    for prot = {'sf_cf','sf_cb','sb_cb'}
        try
            r = run_protocol_v2(prot{1}, trace, scenario, cfg, M, 1, 16);
            fprintf('  %-6s completion=%.2f first=%.2f\n', prot{1}, r.packet_log.completion_us(1), r.packet_log.first_attempt_us(1));
        catch ME
            fprintf('  %-6s ERROR: %s\n', prot{1}, ME.message);
        end
    end
end
