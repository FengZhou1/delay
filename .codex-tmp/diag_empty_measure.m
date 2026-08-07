cfg = default_experiment_config('smoke');
cfg.n_nodes = 8;
cfg.warmup_us = 500;
cfg.measure_us = 500;
cfg.arrival_end_us = 1000;
cfg.sim_hard_end_us = 500;
cfg.cca_mode = 'disabled';
scenario = prepare_scenario_v2(cfg, 20260723);
trace = make_manual_arrival_trace([0;0],[1;2],cfg);
r = simulate_sb_cf_v2(trace,scenario,cfg,1,1,15001);
d = r.diagnostics;
fprintf('fail_total=%d waste_measure=%.4f waste_total=%.1f\n', ...
    d.rts_fail_total, d.collision_waste_measure_us, d.collision_waste_us);
fprintf('starts: %s\n', mat2str(d.rts_start_times_us));
