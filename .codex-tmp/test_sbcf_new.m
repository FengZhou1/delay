c = checkcode('simulate_sb_cf_v2.m','-struct');
fprintf('checkcode issues: %d\n', numel(c));
parse_errors = 0;
for i = 1:numel(c)
    m = char(c(i).message);
    if contains(lower(m),'parse') || contains(lower(m),'syntax') || contains(lower(m),'??')
        parse_errors = parse_errors + 1;
        fprintf('PARSE L%d: %s\n', c(i).line, m);
    end
end
fprintf('parse issues: %d\n', parse_errors);
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
        fprintf('M=%d completion=%.1f first=%.1f (expect %d and 36)\n', M, ...
            r.packet_log.completion_us(1), r.packet_log.first_attempt_us(1), 36+round(164.1*M));
    end
    fprintf('RUN OK\n');
catch ME
    fprintf('ERROR: %s\n', ME.message);
    for k=1:numel(ME.stack)
        fprintf('  at %s line %d\n', ME.stack(k).name, ME.stack(k).line);
    end
end
