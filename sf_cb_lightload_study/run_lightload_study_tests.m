function results = run_lightload_study_tests()
%RUN_LIGHTLOAD_STUDY_TESTS Self-checks for the four-protocol study.
% Verifies the exact timing constants, the slotted engine semantics
% (SF-CB one packet per reservation, batch_clear whole-queue snapshot,
% idle/collision wasting one conn-slot), the continuous engine success
% cycles (unslotted = 164.1 + M*164.1, sb_cb = 34 + 164.1 + M*164.1),
% packet conservation / delay identity and a physical-layer smoke test.

    fprintf('=== run_lightload_study_tests ===\n');
    cfg = default_lightload_sfcb_config('smoke','delay');
    cfg.n_nodes = 8;
    cfg.n_sectors = 8;
    timing = protocol_timing(cfg);
    scenario = prepare_scenario_v2(cfg, cfg.topology_seed);
    tol = 1e-6;

    results = struct();
    results.n_pass = 0;
    results.n_fail = 0;
    results.failures = {};

    % ---- T1: timing constants ----
    results = check(results, abs(timing.RTS_US - 14.5) < tol, ...
        'RTS = 14.5 us');
    results = check(results, abs(timing.SIFS_US - 16) < tol, ...
        'SIFS = 16 us');
    results = check(results, abs(timing.DIFS_US - 34) < tol, ...
        'DIFS = 34 us');
    results = check(results, abs(timing.CTS_US - 14.7) < tol, ...
        'CTS = 14.7 us');
    results = check(results, abs(timing.CTS_SWEEP_US - 117.6) < tol, ...
        'CTS sweep = 117.6 us');
    results = check(results, abs(timing.CONN_SLOT_US - 164.1) < tol, ...
        'conn-slot = 164.1 us');
    results = check(results, abs(timing.CTS_TIMEOUT_US - 133.6) < tol, ...
        'CTS timeout = 133.6 us');
    results = check(results, timing.DIFS_TICKS == 4, 'DIFS ticks = 4');

    % ---- T2: SF-CB single node, no contention ----
    c2 = test_window(cfg, 0, 1e4, 5e4);
    tr2 = manual_trace(c2, [0; 0], [1; 1]);          % M=1 and M=2 packets
    r2_1 = simulate_sf_cb(manual_trace(c2, 0, 1), scenario, c2, 1, 1, 7);
    s2_1 = r2_1.summary;
    results = check(results, abs(s2_1.mean_delay_us - 328.2) < tol, ...
        'SF-CB M=1 no-contention delay = 328.2 us');
    results = check(results, s2_1.completion_ratio == 1, ...
        'SF-CB M=1 completion ratio = 1');
    r2_2 = simulate_sf_cb(manual_trace(c2, 0, 1), scenario, c2, 2, 1, 7);
    results = check(results, abs(r2_2.summary.mean_delay_us - 492.3) < tol, ...
        'SF-CB M=2 no-contention delay = 492.3 us');

    % ---- T3: SF-CB collision wastes one conn-slot ----
    c3 = test_window(cfg, 0, 200, 250);
    tr3 = manual_trace(c3, [0; 0], [1; 2]);
    r3 = simulate_sf_cb(tr3, scenario, c3, 1, 1, 7);
    results = check(results, r3.diagnostics.collision_slots == 3, ...
        'SF-CB collision wastes 3 conn-slots before hard end');
    results = check(results, abs(r3.diagnostics.collision_waste_us - 3*164.1) < tol, ...
        'SF-CB collision waste = 3 x 164.1 us');
    results = check(results, r3.summary.completion_ratio == 0, ...
        'SF-CB all-collision completion ratio = 0');

    % ---- T4: SF-CB idle frame wastes one conn-slot ----
    c4 = test_window(cfg, 0, 1000, 1000);
    tr4 = manual_trace(c4, 200, 1);
    r4 = simulate_sf_cb(tr4, scenario, c4, 1, 1, 7);
    results = check(results, r4.diagnostics.idle_slots == 5, ...
        'SF-CB idle wastes 5 conn-slots (2 before arrival + 3 drain)');
    results = check(results, abs(r4.summary.mean_delay_us - 456.4) < tol, ...
        'SF-CB delayed arrival delay = 456.4 us');

    % ---- T5: batch_clear sends the whole queue snapshot ----
    c5 = test_window(cfg, 0, 1e4, 5e4);
    tr5 = manual_trace(c5, [0;0;0], [1;1;1]);
    r5 = simulate_batch_clear(tr5, scenario, c5, 1, 1, 7);
    results = check(results, r5.diagnostics.success_slots == 1, ...
        'batch_clear: one reservation for 3 queued packets');
    results = check(results, r5.summary.n_completed_total == 3, ...
        'batch_clear: all 3 packets completed');
    comp5 = sort(r5.packet_log.completion_us(~isnan(r5.packet_log.completion_us)));
    results = check(results, all(abs(comp5 - [328.2; 492.3; 656.4]) < tol), ...
        'batch_clear: back-to-back DATA completions');
    results = check(results, abs(r5.summary.sim_end_us - 10010.1) < tol, ...
        'batch_clear: sim drains to the next frame boundary after arrival_end');

    % ---- T6: SF-CB sends exactly one packet per reservation ----
    r6 = simulate_sf_cb(tr5, scenario, c5, 1, 1, 7);
    results = check(results, r6.diagnostics.success_slots == 3, ...
        'SF-CB: one packet per successful reservation');
    comp6 = sort(r6.packet_log.completion_us(~isnan(r6.packet_log.completion_us)));
    results = check(results, all(abs(comp6 - [328.2; 656.4; 984.6]) < tol), ...
        'SF-CB: three separate transactions');

    % ---- T7: unslotted no-contention cycle ----
    c7 = test_window(cfg, 0, 1e4, 5e4);
    tr7 = manual_trace(c7, 0, 1);
    r7 = simulate_unslotted_sf_cb(tr7, scenario, c7, 1, 1, 7);
    results = check(results, abs(r7.summary.mean_delay_us - 328.2) < tol, ...
        'unslotted no-contention delay = 164.1 + 164.1 us');
    results = check(results, abs(r7.packet_log.first_attempt_us(1) - 0) < tol, ...
        'unslotted: immediate first RTS at t=0');

    % ---- T8: sb_cb no-contention cycle (DIFS 34 + conn-slot + DATA) ----
    r8 = simulate_sb_cb(tr7, scenario, c7, 1, 1, 7);
    results = check(results, abs(r8.summary.mean_delay_us - 362.2) < tol, ...
        'sb_cb no-contention delay = 34 + 164.1 + 164.1 us');
    results = check(results, abs(r8.packet_log.first_attempt_us(1) - 34) < tol, ...
        'sb_cb: first RTS at DIFS instant t=34 us');

    % ---- T10: slotted queue refill after emptying ----
    c10 = test_window(cfg, 0, 1e4, 5e4);
    tr10 = manual_trace(c10, [0; 504], [1; 1]);   % 504 = 56 x 9 us slot
    r10 = simulate_sf_cb(tr10, scenario, c10, 1, 1, 7);
    comp10 = sort(r10.packet_log.completion_us(~isnan(r10.packet_log.completion_us)));
    results = check(results, all(abs(comp10 - [328.2; 984.6]) < tol), ...
        'SF-CB queue refill uses fresh packet ids');
    results = check(results, r10.summary.n_completed_total == 2, ...
        'SF-CB queue refill completes both packets');

    % ---- T11: continuous queue refill after emptying ----
    r11u = simulate_unslotted_sf_cb(tr10, scenario, c10, 1, 1, 7);
    comp11u = sort(r11u.packet_log.completion_us(~isnan(r11u.packet_log.completion_us)));
    results = check(results, all(abs(comp11u - [328.2; 832.2]) < tol), ...
        'unslotted queue refill completes both packets');
    r11s = simulate_sb_cb(tr10, scenario, c10, 1, 1, 7);
    comp11s = sort(r11s.packet_log.completion_us(~isnan(r11s.packet_log.completion_us)));
    results = check(results, all(abs(comp11s - [362.2; 866.2]) < tol), ...
        'sb_cb queue refill completes both packets');

    % ---- T9: SINR / event-driven smoke ----
    c9 = test_window(cfg, 0, 2e4, 2e4);
    tr9 = manual_trace(c9, [0; 5; 10], [1; 2; 3]);
    r9u = simulate_unslotted_sf_cb(tr9, scenario, c9, 1, 0.5, 7);
    r9s = simulate_sb_cb(tr9, scenario, c9, 1, 0.5, 7);
    results = check(results, isfinite(r9u.summary.sim_end_us) && ...
        r9u.diagnostics.rts_attempts > 0, ...
        'unslotted SINR smoke produced events');
    results = check(results, isfinite(r9s.summary.sim_end_us) && ...
        r9s.diagnostics.rts_attempts > 0, ...
        'sb_cb SINR smoke produced events');
    results = check(results, isfield(r9s.diagnostics,'data_fail_sinr') && ...
        isfield(r9s.diagnostics,'cts_miss_winner'), ...
        'sb_cb SINR diagnostics present');

    % ---- T12: geometric backoff distribution (p-persistent semantics) ----
    % With a single packet at t=0 and q=0.5, the wait first_attempt-hol must
    % be a multiple of SLOT=9 us with mean 9*(1-q)/q = 9 us, and the
    % probability_wait accounting must match the observed wait.
    c12 = test_window(cfg, 0, 2e5, 5e5);
    tr12 = manual_trace(c12, 0, 1);
    n12 = 400;
    w12 = zeros(n12,1);
    p12 = zeros(n12,1);
    for s = 1:n12
        r12 = simulate_unslotted_sf_cb(tr12, scenario, c12, 1, 0.5, 1000+s);
        w12(s) = r12.packet_log.first_attempt_us(1) - r12.packet_log.hol_us(1);
        p12(s) = r12.packet_log.probability_wait_us(1);
    end
    results = check(results, all(abs(w12 - round(w12/9)*9) < tol), ...
        'geometric backoff wait is a multiple of 9 us');
    results = check(results, all(abs(w12 - p12) < tol), ...
        'geometric backoff accounting matches observed wait');
    results = check(results, abs(mean(w12) - 9) < 2.0, ...
        'geometric backoff mean wait ~= 9 us at q=0.5');

    fprintf('tests: %d passed, %d failed\n', results.n_pass, results.n_fail);
    if results.n_fail > 0
        for i = 1:numel(results.failures)
            fprintf('  FAIL: %s\n', results.failures{i});
        end
        error('run_lightload_study_tests:Failed', ...
            '%d test(s) failed.', results.n_fail);
    end
end

function c = test_window(base, warmup, measure, drain)
    c = base;
    c.warmup_us = warmup;
    c.measure_us = measure;
    c.drain_max_us = drain;
    c.arrival_end_us = warmup + measure;
    c.sim_hard_end_us = c.arrival_end_us + drain;
end

function trace = manual_trace(cfg, times, nodes)
    times = double(times(:));
    nodes = double(nodes(:));
    if numel(times) ~= numel(nodes)
        error('manual_trace:SizeMismatch', ...
            'times and nodes must have the same length.');
    end
    n_nodes = double(cfg.n_nodes);
    packet_ids_by_node = cell(n_nodes,1);
    for u = 1:n_nodes
        packet_ids_by_node{u} = find(nodes == u).';
    end
    trace = struct();
    trace.times_us = times;
    trace.node_id = nodes;
    trace.packet_ids_by_node = packet_ids_by_node;
    trace.n_packets = numel(times);
    trace.lambda_per_node = NaN;
    trace.arrival_end_us = double(cfg.arrival_end_us);
    trace.hard_end_us = double(cfg.sim_hard_end_us);
end

function results = check(results, ok, label)
    if ok
        results.n_pass = results.n_pass + 1;
        fprintf('  PASS: %s\n', label);
    else
        results.n_fail = results.n_fail + 1;
        results.failures{end+1,1} = label;
        fprintf('  FAIL: %s\n', label);
    end
end
