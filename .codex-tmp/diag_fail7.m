cfg = default_experiment_config('smoke');
cfg.n_nodes = 40;
cfg.cca_mode = 'directional';
cfg.collect_debug_trace = true;
cfg.warmup_us = 0;
cfg.measure_us = 700;
cfg.drain_max_us = 700;
cfg.arrival_end_us = 700;
cfg.sim_hard_end_us = 1400;
scenario = prepare_scenario_v2(cfg, 482);
scenario.PHY.Int_Matrix(:) = 0;
scenario.PHY.AP_Sector_Tx_Matrix(:) = 1e-6;
scenario.PHY.AP_Rx_Matrix(:) = 0;
scenario.PHY.AP_Rx_Matrix(1:cfg.n_nodes+1:end) = 1e-6;
trace = make_manual_arrival_trace([0;99],[1;3],cfg);
try
    r = simulate_sb_cb_v2(trace,scenario,cfg,1,1,483);
    fprintf('nav_set=%d rts_starts=%s nodes=%s\n', ...
        r.diagnostics.nav_set, mat2str(r.diagnostics.rts_start_times_us), mat2str(r.diagnostics.rts_start_nodes));
    fprintf('node3_starts: %s\n', mat2str(r.diagnostics.rts_start_times_us(r.diagnostics.rts_start_nodes==3)));
    fprintf('attempts=%d success=%d\n', r.diagnostics.rts_attempts, r.diagnostics.rts_success);
catch ME
    fprintf('ERROR: %s\n', ME.message);
    for k=1:numel(ME.stack)
        fprintf('  at %s line %d\n', ME.stack(k).name, ME.stack(k).line);
    end
end
