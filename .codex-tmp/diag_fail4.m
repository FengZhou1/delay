cfg = default_experiment_config('smoke');
cfg.n_nodes = 40;
cfg.cca_mode = 'disabled';
cfg.collect_debug_trace = true;
cfg.warmup_us = 0;
cfg.measure_us = 700;
cfg.drain_max_us = 700;
cfg.arrival_end_us = 700;
cfg.sim_hard_end_us = 1400;
scenario = prepare_scenario_v2(cfg, 480);
scenario.PHY.Int_Matrix(:) = 0;
scenario.PHY.AP_Sector_Tx_Matrix(:) = 1e-6;
scenario.PHY.AP_Rx_Matrix(:) = 0;
scenario.PHY.AP_Rx_Matrix(1:cfg.n_nodes+1:end) = 1e-6;
scenario.PHY.AP_Rx_Matrix(1,2) = 1e-6;
trace = make_manual_arrival_trace([0;36],[1;2],cfg);
try
    r = simulate_sb_cb_v2(trace,scenario,cfg,1,1,481);
    fprintf('icr_miss_halfduplex=%d icr_decoded=%d icr_expected=%d\n', ...
        r.diagnostics.icr_miss_halfduplex, r.diagnostics.icr_decoded, r.diagnostics.icr_expected);
    fprintf('late_start_data=%d data_partial_collision=%d\n', ...
        r.diagnostics.late_start_data, r.diagnostics.data_partial_collision_events);
    fprintf('data_failure_transaction_delay=%.1f\n', r.diagnostics.data_failure_transaction_delay_us);
    fprintf('rts_start_times=%s nodes=%s\n', mat2str(r.diagnostics.rts_start_times_us), mat2str(r.diagnostics.rts_start_nodes));
    fprintf('rts_attempts=%d rts_success=%d\n', r.diagnostics.rts_attempts, r.diagnostics.rts_success);
catch ME
    fprintf('ERROR: %s\n', ME.message);
    for k=1:numel(ME.stack)
        fprintf('  at %s line %d\n', ME.stack(k).name, ME.stack(k).line);
    end
end
