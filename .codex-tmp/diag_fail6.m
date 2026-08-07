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
    fprintf('halfduplex=%d decoded=%d expected=%d late_start_data=%d partial_coll=%d\n', ...
        r.diagnostics.icr_miss_halfduplex, r.diagnostics.icr_decoded, r.diagnostics.icr_expected, ...
        r.diagnostics.late_start_data, r.diagnostics.data_partial_collision_events);
    fprintf('data_fail_tx_delay=%.1f rts_starts=%s nodes=%s success=%d\n', ...
        r.diagnostics.data_failure_transaction_delay_us, mat2str(r.diagnostics.rts_start_times_us), ...
        mat2str(r.diagnostics.rts_start_nodes), r.diagnostics.rts_success);
    fprintf('node2_starts: %s\n', mat2str(r.diagnostics.rts_start_times_us(r.diagnostics.rts_start_nodes==2)));
catch ME
    fprintf('ERROR: %s\n', ME.message);
    for k=1:numel(ME.stack)
        fprintf('  at %s line %d\n', ME.stack(k).name, ME.stack(k).line);
    end
end
