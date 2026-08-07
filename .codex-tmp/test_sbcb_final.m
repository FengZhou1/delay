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
try
    r = run_protocol_v2('sb_cb', trace, scenario, cfg, 1, 1, 16);
    fprintf('completion_us: %.2f (expect 364.2)\n', r.packet_log.completion_us(1));
    fprintf('first_attempt_us: %.2f (expect 36)\n', r.packet_log.first_attempt_us(1));
    fprintf('busy_nav_wait: %.2f\n', r.packet_log.busy_nav_wait_us(1));
    fprintf('stable: %d completion_ratio: %.3f mean_delay: %.2f\n', ...
        r.summary.stable, r.summary.completion_ratio, r.summary.mean_delay_us);
    fprintf('RUN OK\n');
catch ME
    fprintf('ERROR: %s\n', ME.message);
    for k=1:numel(ME.stack)
        fprintf('  at %s line %d\n', ME.stack(k).name, ME.stack(k).line);
    end
end
