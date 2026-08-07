cfg = default_experiment_config('smoke');
cfg.n_nodes = 8;
cfg.cca_mode = 'disabled';   % no sensing => both send
cfg.warmup_us = 0;
cfg.measure_us = 1000;
cfg.drain_max_us = 0;
cfg.arrival_end_us = 1000;
cfg.sim_hard_end_us = 1000;
scenario = prepare_scenario_v2(cfg, 4);
trace = make_manual_arrival_trace([0;0],[1;2],cfg);
try
    r = run_protocol_v2('sb_cf', trace, scenario, cfg, 1, 1, 17);
    d = r.diagnostics;
    fprintf('attempts=%d fail_collision=%d success=%d\n', d.rts_attempts, d.rts_fail_collision, d.rts_success);
    fprintf('completions: %s\n', mat2str(r.packet_log.completion_us));
    fprintf('COLLISION TEST OK\n');
catch ME
    fprintf('ERROR: %s\n', ME.message);
    for k=1:numel(ME.stack)
        fprintf('  at %s line %d\n', ME.stack(k).name, ME.stack(k).line);
    end
end
