cfg = default_experiment_config('smoke');
cfg.n_nodes = 8;
cfg.cca_mode = 'oracle';
cfg.warmup_us = 0;
cfg.measure_us = 2000;
cfg.drain_max_us = 2000;
cfg.arrival_end_us = cfg.warmup_us + cfg.measure_us;
cfg.sim_hard_end_us = cfg.arrival_end_us + cfg.drain_max_us;
scenario = prepare_scenario_v2(cfg, 3);
fprintf('MMW_REAL: RTS=%.1f SIFS=%.1f DIFS=%.1f CTS=%.1f sweep=%.1f conn=%.1f timeout=%.1f\n', ...
    scenario.MMW_REAL.RTS_US, scenario.MMW_REAL.SIFS_US, scenario.MMW_REAL.DIFS_US, ...
    scenario.MMW_REAL.CTS_US, scenario.MMW_REAL.CTS_SWEEP_US, scenario.MMW_REAL.CONN_OVERHEAD_US, ...
    scenario.MMW_REAL.CTS_TIMEOUT_US);
trace = make_manual_arrival_trace(0, 1, cfg);
try
    r = simulate_sb_cb_v2(trace, scenario, cfg, 1, 1, 16);
    fprintf('completion_us: %.1f (expect 364.2 = 36+164.1+164.1)\n', r.packet_log.completion_us(1));
    fprintf('first_attempt_us: %.1f (expect 36)\n', r.packet_log.first_attempt_us(1));
    fprintf('sim_end_us: %.1f\n', r.summary.sim_end_us);
    fprintf('stable: %d completion_ratio: %.3f\n', r.summary.stable, r.summary.completion_ratio);
    fprintf('mean_delay_us: %.1f\n', r.summary.mean_delay_us);
    fprintf('RUN OK\n');
catch ME
    fprintf('ERROR: %s\n', ME.message);
    for k=1:numel(ME.stack)
        fprintf('  at %s line %d\n', ME.stack(k).name, ME.stack(k).line);
    end
end
