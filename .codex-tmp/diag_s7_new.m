cfg = default_experiment_config('smoke');
cfg.n_nodes = 8;
cfg.cca_mode = 'oracle';
cfg.warmup_us = 0;
cfg.measure_us = 2000;
cfg.drain_max_us = 2000;
cfg.arrival_end_us = 2000;
cfg.sim_hard_end_us = 4000;
scenario = prepare_scenario_v2(cfg, 3);
fprintf('SUB7: SIFS=%.1f DIFS=%.1f RTS=%.1f CTS=%.1f timeout=%.1f\n', ...
    scenario.SUB7.SIFS_US, scenario.SUB7.DIFS_US, scenario.SUB7.RTS_US, ...
    scenario.SUB7.CTS_US, scenario.SUB7.CTS_TIMEOUT_US);
trace = make_manual_arrival_trace(0, 1, cfg);
try
    r = run_protocol_v2('s7_clean', trace, scenario, cfg, 1, 1, 16);
    fprintf('completion=%.2f first=%.2f hol=%.2f\n', ...
        r.packet_log.completion_us(1), r.packet_log.first_attempt_us(1), r.packet_log.hol_us(1));
    fprintf('difs_wait=%.2f control=%.2f data=%.2f\n', ...
        r.packet_log.difs_wait_us(1), r.packet_log.control_delay_us(1), r.packet_log.data_delay_us(1));
catch ME
    fprintf('ERROR: %s\n', ME.message);
    for k=1:numel(ME.stack)
        fprintf('  at %s line %d\n', ME.stack(k).name, ME.stack(k).line);
    end
end
