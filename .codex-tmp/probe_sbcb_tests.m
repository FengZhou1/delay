cfg = default_experiment_config('smoke');
cfg.n_nodes = 8;
cfg.cca_mode = 'disabled';
cfg.collect_debug_trace = true;
cfg.warmup_us = 0;
cfg.measure_us = 300;
cfg.drain_max_us = 0;
cfg.arrival_end_us = 300;
cfg.sim_hard_end_us = 300;
scenario = prepare_scenario_v2(cfg, 44);
trace = make_manual_arrival_trace([0;0],[1;2],cfg);
try
    r = simulate_sb_cb_v2(trace, scenario, cfg, 1, 1, 171);
    fprintf('rts_start_times: %s\n', mat2str(r.diagnostics.rts_start_times_us));
    fprintf('rts_response_timeouts: %d\n', r.diagnostics.rts_response_timeouts);
    fprintf('collision_delay: %s\n', mat2str(r.packet_log.collision_delay_us));
    fprintf('first_attempt: %s\n', mat2str(r.packet_log.first_attempt_us));
    fprintf('PROBE OK\n');
catch ME
    fprintf('ERROR: %s\n', ME.message);
    for k=1:numel(ME.stack)
        fprintf('  at %s line %d\n', ME.stack(k).name, ME.stack(k).line);
    end
end
