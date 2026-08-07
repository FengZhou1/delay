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
try
    for M = [1 2]
        r = run_protocol_v2('sb_cf', trace, scenario, cfg, M, 1, 16);
        fprintf('M=%d completion=%.2f first=%.2f (expect %.1f and 36)\n', M, ...
            r.packet_log.completion_us(1), r.packet_log.first_attempt_us(1), 36+164.1*M);
    end
    fprintf('RUN OK\n');
catch ME
    fprintf('ERROR: %s\n', ME.message);
    for k=1:numel(ME.stack)
        fprintf('  at %s line %d\n', ME.stack(k).name, ME.stack(k).line);
    end
end
