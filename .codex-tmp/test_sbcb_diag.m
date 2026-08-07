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
raw = simulate_sb_cb_v2_engine(trace, scenario, cfg, 1, 1, 16);
p = raw.packet_log;
fprintf('completion=%.4f hol=%.4f arrival=%.4f\n', p.completion_us(1), p.hol_us(1), p.arrival_us(1));
fprintf('difs_wait=%.4f prob_wait=%.4f coll=%.4f control=%.4f data=%.4f busy_nav=%.4f boundary=%.4f other=%.4f\n', ...
    p.difs_wait_us(1), p.probability_wait_us(1), p.collision_delay_us(1), ...
    p.control_delay_us(1), p.data_delay_us(1), p.busy_nav_wait_us(1), ...
    p.boundary_wait_us(1), p.other_access_delay_us(1));
sumc = p.boundary_wait_us(1)+p.difs_wait_us(1)+p.probability_wait_us(1)+p.busy_nav_wait_us(1)+...
    p.collision_delay_us(1)+p.control_delay_us(1)+p.data_delay_us(1)+p.other_access_delay_us(1);
fprintf('component_sum=%.4f access=%.4f diff=%.6f\n', sumc, p.completion_us(1)-p.hol_us(1), sumc-(p.completion_us(1)-p.hol_us(1)));
