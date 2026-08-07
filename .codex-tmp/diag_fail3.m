cfg = default_experiment_config('smoke');
cfg.n_nodes = 8;
cfg.cca_mode = 'directional';
cfg.rx_sens_dbm = -62;
cfg.warmup_us = 0;
cfg.measure_us = 100;
cfg.drain_max_us = 0;
cfg.arrival_end_us = 100;
cfg.sim_hard_end_us = 100;
trace = make_manual_arrival_trace([0;18],[1;2],cfg);
classic = prepare_scenario_v2(cfg,46);
classic.PHY.AP_Rx_Matrix(:) = 0;
classic.PHY.Int_Matrix(:) = 0;
try
    missed = simulate_sb_cb_v2(trace,classic,cfg,1,1,173);
    fprintf('attempts=%d fail_collision=%d success=%d first=%s\n', ...
        missed.diagnostics.rts_attempts, missed.diagnostics.rts_fail_collision, ...
        missed.diagnostics.rts_success, mat2str(missed.packet_log.first_attempt_us));
catch ME
    fprintf('ERROR: %s\n', ME.message);
    for k=1:numel(ME.stack)
        fprintf('  at %s line %d\n', ME.stack(k).name, ME.stack(k).line);
    end
end
