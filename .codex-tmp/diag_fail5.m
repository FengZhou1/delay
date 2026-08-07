cfg = default_experiment_config('smoke');
cfg.n_nodes = 8;
cfg.warmup_us = 0;
cfg.measure_us = 792;
cfg.drain_max_us = 792;
cfg.arrival_end_us = 792;
cfg.sim_hard_end_us = 1584;
scenario = prepare_scenario_v2(cfg, 1);
trace = make_manual_arrival_trace(0,1,cfg);
r = simulate_aloha_v2('sf_cb',trace,scenario,cfg,2,1,12);
fprintf('mean_system=%.10f (expect 0.75) mean_service=%.10f (expect 0.5)\n', ...
    r.summary.mean_system_packets, r.summary.mean_service_packets);
