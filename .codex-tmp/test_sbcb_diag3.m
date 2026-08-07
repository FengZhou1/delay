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
orig_fin = str2func('finalize_sim_result');
try
    raw = simulate_sb_cb_v2(trace, scenario, cfg, 1, 1, 16);
catch ME
    fprintf('ERROR: %s\n', ME.message);
end
