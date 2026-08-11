addpath('C:\Users\Administrator\Documents\delay');
addpath('C:\Users\Administrator\Documents\delay\sf_cb_lightload_study');

cfg = default_lightload_sfcb_config('analysis','delay');
cfg.topology_seed = 42;
scenario = prepare_scenario_v2(cfg, cfg.topology_seed);

% USE TUNE CFG (1s measure, not 2s)
tune_cfg = cfg;
tune_cfg.warmup_us = cfg.tune_warmup_us;
tune_cfg.measure_us = cfg.tune_measure_us;
tune_cfg.drain_max_us = cfg.tune_drain_max_us;
tune_cfg.arrival_end_us = tune_cfg.warmup_us + tune_cfg.measure_us;
tune_cfg.sim_hard_end_us = tune_cfg.arrival_end_us + tune_cfg.drain_max_us;

tr = generate_arrival_trace(1, tune_cfg, cfg.traffic_seed_base);
fprintf('Trace: n_packets=%d, seed=%d, arrival_end=%.0f\n', tr.n_packets, cfg.traffic_seed_base, tr.arrival_end_us);

result = simulate_sfcb_lightload_variant('sf_cb', tr, scenario, tune_cfg, 1, 1, cfg.protocol_seed_base);
s = result.summary;
fprintf('sf_cb q=1: delay=%.2f cr=%.4f n_arrived=%d n_completed=%d stable=%d\n', ...
    s.mean_delay_us, s.completion_ratio, s.n_arrived, s.n_completed, s.stable);

% Check collisions
diag = result.diagnostics;
fprintf('collision_slots=%d idle_slots=%d success_slots=%d\n', ...
    diag.collision_slots, diag.idle_slots, diag.success_slots);
fprintf('collision_waste_us=%.0f sim_end_us=%.0f\n', ...
    diag.collision_waste_us, s.sim_end_us);

% Same for batch_clear
result2 = simulate_sfcb_lightload_variant('batch_clear', tr, scenario, tune_cfg, 1, 1, cfg.protocol_seed_base);
s2 = result2.summary;
fprintf('\nbatch_clear q=1: delay=%.2f cr=%.4f n_arrived=%d n_completed=%d stable=%d\n', ...
    s2.mean_delay_us, s2.completion_ratio, s2.n_arrived, s2.n_completed, s2.stable);
