cfg = default_experiment_config('smoke');
cfg.n_nodes = 8;
cfg.cca_mode = 'oracle';
cfg.warmup_us = 0;
cfg.measure_us = 2000;
cfg.drain_max_us = 2000;
cfg.arrival_end_us = 2000;
cfg.sim_hard_end_us = 4000;
scenario = prepare_scenario_v2(cfg, 3);
trace = make_manual_arrival_trace(0, 1, cfg);
r = run_protocol_v2('sb_cf', trace, scenario, cfg, 1, 1, 16);
d = r.diagnostics;
fprintf('attempts=%d success=%d fail_total=%d fail_collision=%d ap_busy=%d\n', ...
    d.rts_attempts, d.rts_success, d.rts_fail_total, d.rts_fail_collision, d.rts_fail_ap_busy);
fprintf('data_success=%d data_fail_sinr=%d data_reservations=%d\n', ...
    d.data_success, d.data_fail_sinr, d.data_reservations);
fprintf('sim_end=%.1f backlog=%d\n', r.summary.sim_end_us, r.summary.final_backlog);
fprintf('starts: %s\n', mat2str(d.rts_start_times_us));
p = r.packet_log;
fprintf('attempts_log=%d first=%.1f hol=%.1f\n', p.attempts(1), p.first_attempt_us(1), p.hol_us(1));
