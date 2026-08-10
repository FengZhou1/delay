function report = run_v2_tests(output_dir)
%RUN_V2_TESTS Deterministic timing and accounting tests for the v2 simulator.
%   report = RUN_V2_TESTS() executes the complete deterministic suite.
%   A machine-readable MAT/JSON report is written when output_dir is given.

    if nargin < 1
        output_dir = '';
    end

    tests = { ...
        @test_config_rejects_fractional_M, ...
        @test_mmw_integer_slot_parameters, ...
        @test_hash_ignores_runtime_output_path, ...
        @test_all_censored_cohort_is_unstable, ...
        @test_optional_slope_gate_can_be_disabled, ...
        @test_common_arrival_trace_reproducible, ...
        @test_common_arrival_seed_by_effective_rate, ...
        @test_neighbor_stable_q_selection, ...
        @test_refined_q_grid_and_edge_expansion, ...
        @test_theory_boundary_trace_is_explicit, ...
        @test_single_packet_M_endpoints, ...
        @test_sf_cf_single_and_boundary, ...
        @test_sf_cb_exact_payload, ...
        @test_aloha_classic_collision, ...
        @test_sb_cf_fresh_difs, ...
        @test_sb_cf_classic_collision, ...
        @test_sb_cf_empty_measurement_collision_intervals, ...
        @test_offgrid_horizon_keeps_last_arrival, ...
        @test_sb_cb_timing_and_collision, ...
        @test_sb_cb_separate_cts_data_thresholds, ...
        @test_sb_cb_response_timeout, ...
        @test_sb_cb_counterfactual_cca, ...
        @test_sb_cb_cts_halfduplex_and_late_data, ...
        @test_sb_cb_nav_exact_expiry, ...
        @test_s7_exact_timing, ...
        @test_s7_collision_does_not_freeze_bystander, ...
        @test_all_protocol_conservation, ...
        @test_serial_parallel_packet_equivalence, ...
        @test_analysis_protocol_q_grid_and_filter, ...
        @test_independent_q_validation_flow, ...
        @test_runner_checkpoint_resume_and_guard};
    names = cellfun(@func2str, tests, 'UniformOutput', false);
    elapsed_s = zeros(numel(tests),1);
    passed = false(numel(tests),1);
    messages = strings(numel(tests),1);

    suite_started = tic;
    for i = 1:numel(tests)
        started = tic;
        try
            tests{i}();
            passed(i) = true;
            messages(i) = "passed";
            fprintf('[PASS] %s\n', names{i});
        catch ME
            messages(i) = string(getReport(ME,'extended','hyperlinks','off'));
            fprintf(2, '[FAIL] %s: %s\n', names{i}, ME.message);
        end
        elapsed_s(i) = toc(started);
    end

    report = struct();
    report.schema_version = '2.0';
    report.run_at = char(datetime('now','Format','yyyy-MM-dd''T''HH:mm:ss'));
    report.matlab_version = version;
    report.names = names(:);
    report.passed = passed;
    report.elapsed_s = elapsed_s;
    report.messages = cellstr(messages);
    report.total_elapsed_s = toc(suite_started);
    report.n_passed = sum(passed);
    report.n_failed = sum(~passed);

    if ~isempty(output_dir)
        if ~exist(output_dir,'dir'), mkdir(output_dir); end
        save(fullfile(output_dir,'test_report.mat'),'report');
        write_report_json(fullfile(output_dir,'test_report.json'),report);
    end

    if any(~passed)
        failed_names = strjoin(names(~passed), ', ');
        error('run_v2_tests:Failed', '%d test(s) failed: %s', ...
              sum(~passed), failed_names);
    end
end

function test_mmw_integer_slot_parameters()
    cfg = validate_experiment_config(default_experiment_config('smoke'));
    timing = mmw_timing_config(cfg);
    assert(timing.SLOT_US==9 && timing.PHY_HEADER_SLOTS==2 && ...
        timing.SIFS_SLOTS==2 && timing.DIFS_SLOTS==4 && ...
        timing.RTS_SLOTS==2 && timing.CTS_SLOTS==2, ...
        'The configured mmWave integer-slot parameters are incorrect.');
    assert(timing.N_SECTORS==8 && timing.CONN_SLOT_SLOTS==22 && ...
        timing.CONN_SLOT_US==198, ...
        'RTS+SIFS+8*CTS+SIFS did not produce a 22-slot connection frame.');
    assert(timing.DATA_RATE_BPS==2.7e9 && ...
        timing.CONTROL_RATE_BPS==260e6 && ...
        timing.RTS_BITS==160 && timing.CTS_BITS==112, ...
        'The configured mmWave rates or control-frame sizes are incorrect.');
    assert(cfg.data_sinr_th_db==21 && cfg.cts_sinr_th_db==6, ...
        'The DATA/CTS SINR thresholds are not 21 dB and 6 dB.');
    durations = [timing.PHY_HEADER_US timing.SIFS_US timing.DIFS_US ...
        timing.RTS_US timing.CTS_US timing.CONN_SLOT_US];
    assert(all(mod(durations,timing.SLOT_US)==0), ...
        'A mmWave protocol duration is not an integer number of slots.');
end

function test_config_rejects_fractional_M()
    cfg = default_experiment_config('smoke');
    cfg.M_values = [1, 1.5, 2];
    did_error = false;
    try
        validate_experiment_config(cfg);
    catch ME
        did_error = strcmp(ME.identifier, ...
                           'validate_experiment_config:BadM');
    end
    assert(did_error, 'Fractional M was not rejected.');
end

function test_common_arrival_trace_reproducible()
    cfg = base_test_config(4, 5000, 5000);
    a = generate_arrival_trace(30, cfg, 12345);
    b = generate_arrival_trace(30, cfg, 12345);
    assert(isequal(a.times_us,b.times_us) && isequal(a.node_id,b.node_id), ...
           'Arrival generation is not reproducible for a fixed seed.');
    assert(all(mod(a.times_us,cfg.arrival_tick_us)==0), ...
           'An arrival is not on the common mmWave physical grid.');
end

function test_common_arrival_seed_by_effective_rate()
    cfg = default_experiment_config('analysis');
    a = experiment_arrival_seed(cfg,10,1,0,1,2);
    b = experiment_arrival_seed(cfg,10,1,0,2,2);
    assert(a==b, ...
        'Equal effective rates did not reuse the same physical arrival seed.');
    c = experiment_arrival_seed(cfg,5,1,0,1,1);
    assert(a~=c, ...
        'Different effective arrival rates reused the same arrival seed.');

    cfg.common_arrivals_by_effective_rate = false;
    legacy_a = experiment_arrival_seed(cfg,10,1,0,1,2);
    legacy_b = experiment_arrival_seed(cfg,10,1,0,2,2);
    assert(legacy_a~=legacy_b, ...
        'The explicit legacy arrival-seed mode ignored load index.');
end

function test_neighbor_stable_q_selection()
    grid = fake_q_grid([0.1 0.2 0.3 0.4], ...
        [1 1 1 0],[10 9 1 NaN]);
    [q,idx,meta] = select_best_q_v2(grid,true,true);
    assert(abs(q-0.2)<eps && idx==2 && ...
        meta.selection_mode=="neighbor_stable", ...
        'Stable-neighbor selection chose a cliff-edge q.');
    assert(meta.stable_basin_left_q==0.1 && ...
           meta.stable_basin_right_q==0.3, ...
        'Stable-basin bounds were not recorded correctly.');

    isolated = fake_q_grid([0.1 0.2 0.3], ...
        [0 1 0],[NaN 5 NaN]);
    [q,~,meta] = select_best_q_v2(isolated,true,true);
    assert(abs(q-0.2)<eps && ...
        meta.selection_mode=="self_stable_fallback", ...
        'An isolated stable q did not use the documented fallback.');

    none = fake_q_grid([0.1 0.2 0.3],[0 0 0],[NaN NaN NaN]);
    [q,idx,meta] = select_best_q_v2(none,true,true);
    assert(isnan(q) && isnan(idx) && meta.selection_mode=="no_stable_q", ...
        'A grid with no stable q returned a finite best q.');

    wide = fake_q_grid(0.1:0.1:0.7, ...
        [1 1 1 1 1 0 0],[9 7 5 1 6 NaN NaN]);
    [q,~,meta] = select_best_q_v2(wide,true,true,2);
    assert(abs(q-0.3)<1e-12 && ...
        meta.selection_mode=="wide_neighbor_stable" && ...
        meta.neighbor_radius_used==2, ...
        'The preferred two-neighbor basin did not reject a cliff-side q.');
    assert(~isempty(meta.ranked_candidate_q) && ...
        abs(meta.ranked_candidate_q(1)-q)<1e-12, ...
        'The selected q is not first in the validation-candidate ranking.');
end

function test_refined_q_grid_and_edge_expansion()
    [high,meta] = build_refined_q_grid([0.1 0.2 0.5],2,5,'auto',1e-7);
    assert(all(ismember([0.1 0.2 0.3 0.4 0.5],round(high,12))), ...
        'High-q linear refinement omitted the intended 0.3/0.4 points.');
    assert(meta.scale_mode=="linear", ...
        'AUTO did not use linear refinement in the high-q region.');

    [low,meta] = build_refined_q_grid([0.005 0.01 0.02],2,5,'auto',1e-7);
    assert(any(abs(low-0.01)<1e-12) && meta.scale_mode=="log", ...
        'Low-q logarithmic refinement omitted its coarse center.');
    assert(numel(low)==5 && all(diff(low)>1e-12), ...
        ['A numerically duplicated logarithmic centre survived q-grid ', ...
         'deduplication.']);

    [edge,meta] = build_refined_q_grid([2e-5 5e-5 1e-4],1,5, ...
        'auto',1e-7);
    assert(min(edge)<2e-5 && abs(max(edge)-5e-5)<1e-15 && ...
           meta.expanded_lower, ...
        'A lower-bound coarse optimum did not expand the q range.');

    [wide,meta] = build_refined_q_grid( ...
        [0.001 0.002 0.005 0.01 0.02],3,9,'auto',1e-7,2);
    assert(abs(min(wide)-0.001)<1e-15 && ...
           abs(max(wide)-0.02)<1e-15 && meta.neighbor_span==2, ...
        'Wide first-pass refinement did not span two coarse neighbors.');
end

function test_all_censored_cohort_is_unstable()
    cfg=base_test_config(2,100,0);
    cfg.warmup_us=100;
    cfg.measure_us=100;
    cfg.arrival_end_us=200;
    cfg.sim_hard_end_us=200;
    trace=make_manual_arrival_trace([0;100],[1;2],cfg);
    raw=struct();
    raw.packet_log=struct('node_id',[1;2],'arrival_us',[0;100], ...
        'hol_us',[0;100],'first_attempt_us',[0;NaN], ...
        'completion_us',[150;NaN],'attempts',[1;0]);
    raw.final_backlog=1;
    raw.sim_end_us=200;
    raw.system_area_measure_us=150;
    raw.service_area_measure_us=50;
    raw.payload_success_overlap_us=50;
    raw.backlog_sample_us=[100;150];
    raw.backlog_sample_n=[2;1];
    raw.diagnostics=struct();
    result=finalize_sim_result(raw,trace,cfg,'sf_cf',1,1);
    assert(~result.summary.stable && result.summary.completion_ratio==0, ...
        'A measurement cohort with 100% censoring was marked stable.');
end

function test_optional_slope_gate_can_be_disabled()
    cfg=base_test_config(2,1000,0);
    cfg.stability_rate_tolerance=0;
    cfg.stability_censor_tolerance=0;
    cfg.stability_slope_fraction=0;
    trace=make_manual_arrival_trace([0;500],[1;2],cfg);
    raw=struct();
    raw.packet_log=struct('node_id',[1;2],'arrival_us',[0;500], ...
        'hol_us',[0;500],'first_attempt_us',[0;500], ...
        'completion_us',[100;600],'attempts',[1;1]);
    raw.final_backlog=0;
    raw.sim_end_us=1000;
    raw.system_area_measure_us=200;
    raw.service_area_measure_us=200;
    raw.payload_success_overlap_us=200;
    raw.backlog_sample_us=[500;750;995];
    raw.backlog_sample_n=[1;10;20];
    raw.diagnostics=struct();

    cfg.stability_require_slope=false;
    without_gate=finalize_sim_result(raw,trace,cfg,'sf_cf',1,1);
    assert(without_gate.summary.stable, ...
        'Finite positive slope was still applied when its gate was disabled.');
    cfg.stability_require_slope=true;
    with_gate=finalize_sim_result(raw,trace,cfg,'sf_cf',1,1);
    assert(~with_gate.summary.stable, ...
        'Required positive backlog-slope gate did not reject the run.');
end

function test_hash_ignores_runtime_output_path()
    a=default_experiment_config('smoke');
    b=a;
    b.output_dir=fullfile(tempdir,'resume-location');
    b.resume=false;
    b.parallel=~a.parallel;
    [hash_a,code_a]=experiment_config_hash(a);
    [hash_b,code_b]=experiment_config_hash(b);
    assert(strcmp(hash_a,hash_b) && strcmp(code_a,code_b), ...
        'Runtime output/resume/parallel controls changed scientific hash.');
end

function test_sf_cf_single_and_boundary()
    cfg = base_test_config(1, 396, 396);
    scenario = prepare_scenario_v2(cfg, 1);
    trace = make_manual_arrival_trace([0;162.5],[1;1],cfg);
    result = simulate_aloha_v2('sf_cf',trace,scenario,cfg,1,1,11);
    assert_equal(result.packet_log.hol_us,[0;162.5],'SF-CF HOL timing');
    assert_equal(result.packet_log.first_attempt_us,[0;162.5], ...
                 'SF-CF boundary decision ordering');
    assert_equal(result.packet_log.completion_us,[162.5;325.0], ...
                 'SF-CF completion timing');
    assert_delay_and_conservation(result,trace);
end

function test_theory_boundary_trace_is_explicit()
    cfg=base_test_config(8,3960,0);
    trace=generate_boundary_arrival_trace(30,cfg,125,162.5);
    assert(trace.theory_boundary_only && all(mod(trace.times_us,162.5)<1e-9), ...
        'Theory-only arrivals were not aligned to 162.5-us boundaries.');
    assert(abs(trace.tick_us-162.5)<1e-9 && cfg.arrival_tick_us==9, ...
        'Theory trace obscured the common physical arrival-grid definition.');
end

function test_single_packet_M_endpoints()
    cfg=base_test_config(1,3000,1000);
    cfg.cca_mode='oracle';
    scenario=prepare_scenario_v2(cfg,515);
    trace=make_manual_arrival_trace(0,1,cfg);
    for M=[1 6]
        tp_real=scenario.MMW_REAL.CONN_OVERHEAD_US*M;
        tp=scenario.MMW.CONN_OVERHEAD_US*M;
        sf_cf=run_protocol_v2('sf_cf',trace,scenario,cfg,M,1,5100+M);
        sf_cb=run_protocol_v2('sf_cb',trace,scenario,cfg,M,1,5200+M);
        sb_cf=run_protocol_v2('sb_cf',trace,scenario,cfg,M,1,5300+M);
        sb_cb=run_protocol_v2('sb_cb',trace,scenario,cfg,M,1,5400+M);
        s7=run_protocol_v2('s7_clean',trace,scenario,cfg,M,1,5500+M);
        assert_equal(sf_cf.packet_log.completion_us,tp_real, ...
            sprintf('SF-CF M=%d exact payload completion',M));
        assert_equal(sf_cb.packet_log.completion_us,162.5+tp_real, ...
            sprintf('SF-CB M=%d reservation plus payload',M));
        assert_equal(sb_cf.packet_log.completion_us,36+tp_real, ...
            sprintf('SB-CF M=%d DIFS plus payload',M));
        assert_equal(sb_cb.packet_log.completion_us,198.5+tp_real, ...
            sprintf('SB-CB M=%d handshake plus payload',M));
        expected_s7=36 + scenario.SUB7.RTS_US + ...
            scenario.SUB7.SIFS_US + scenario.SUB7.CTS_US + ...
            scenario.SUB7.SIFS_US + tp_real;
        assert_equal(s7.packet_log.completion_us,expected_s7, ...
            sprintf('S7-clean M=%d control plus payload',M));
        results={sf_cf,sf_cb,sb_cf,sb_cb,s7};
        for i=1:numel(results), assert_delay_and_conservation(results{i},trace); end
    end
end

function test_sf_cb_exact_payload()
    cfg = base_test_config(1, 792, 792);
    scenario = prepare_scenario_v2(cfg, 1);
    trace = make_manual_arrival_trace(0,1,cfg);
    result = simulate_aloha_v2('sf_cb',trace,scenario,cfg,2,1,12);
    assert_equal(result.packet_log.first_attempt_us,0,'SF-CB first attempt');
    expected_completion = 162.5 + 2*162.5;   % one conn-slot + exact payload
    assert(abs(result.packet_log.completion_us - expected_completion) < 1e-9, ...
        'SF-CB must use one 162.5-us reservation plus exact payload');
    assert(abs(result.summary.mean_system_packets - 487.5/792) < 1e-12, ...
           'SF-CB exact system-area integral is wrong.');
    assert(abs(result.summary.mean_service_packets - 325.0/792) < 1e-12, ...
           'SF-CB exact payload service-area integral is wrong.');
    assert_delay_and_conservation(result,trace);
end

function test_aloha_classic_collision()
    cfg = base_test_config(2, 396, 396);
    scenario = prepare_scenario_v2(cfg, 1);
    trace = make_manual_arrival_trace([0;0],[1;2],cfg);
    result = simulate_aloha_v2('sf_cf',trace,scenario,cfg,1,1,13);
    assert(all(~isfinite(result.packet_log.completion_us)), ...
           'Two simultaneous SF-CF transmissions must both fail.');
    assert(result.summary.final_backlog==2, ...
           'Collided Aloha packets must remain queued.');
    assert(result.diagnostics.collision_slots>=2, ...
           'Every completed data slot with both HOL packets should collide.');
    assert_delay_and_conservation(result,trace);
end

function test_sb_cf_fresh_difs()
    cfg = base_test_config(1, 600, 600);
    cfg.cca_mode = 'oracle';
    scenario = prepare_scenario_v2(cfg, 1);
    trace = make_manual_arrival_trace([0;9],[1;1],cfg);
    result = simulate_sb_cf_v2(trace,scenario,cfg,1,1,14);
    assert_equal(result.packet_log.hol_us,[0;198.5], ...
                 'SB-CF next-HOL timing');
    assert_equal(result.packet_log.first_attempt_us,[36;234], ...
                 'SB-CF fresh full-DIFS timing');
    assert_equal(result.packet_log.completion_us,[198.5;396.5], ...
                 'SB-CF completion timing');
    assert_delay_and_conservation(result,trace);
end

function test_sb_cf_classic_collision()
    cfg = base_test_config(2, 400, 400);
    cfg.cca_mode = 'disabled';
    scenario = prepare_scenario_v2(cfg, 2);
    trace = make_manual_arrival_trace([0;0],[1;2],cfg);
    result = simulate_sb_cf_v2(trace,scenario,cfg,1,1,15);
    assert(result.diagnostics.rts_attempts>=2 && ...
           result.diagnostics.rts_fail_collision>=1 && ...
           result.diagnostics.rts_success==0, ...
           'SB-CF classic simultaneous collision was not recorded.');
    assert(all(~isfinite(result.packet_log.completion_us)), ...
           'SB-CF decoded a frame from two simultaneous transmitters.');
    assert(result.diagnostics.rts_sinr_used==false, ...
           'SB-CF still used AP capture or SINR.');
    assert_delay_and_conservation(result,trace);

    late_cfg = base_test_config(2,252,0);
    late_cfg.cca_mode = 'disabled';
    late_scenario = prepare_scenario_v2(late_cfg,2002);
    late_trace = make_manual_arrival_trace([0;9],[1;2],late_cfg);
    late = simulate_sb_cf_v2(late_trace,late_scenario,late_cfg,1,1,1501);
    assert(all(~isfinite(late.packet_log.completion_us)) && ...
           late.diagnostics.rts_fail_collision>=1, ...
        'A late SB-CF DATA overlap did not invalidate both frames.');
    assert_delay_and_conservation(late,late_trace);
end

function test_sb_cf_empty_measurement_collision_intervals()
    cfg = base_test_config(2,500,0);
    cfg.warmup_us = 500;
    cfg.measure_us = 500;
    cfg.arrival_end_us = 1000;
    % Stop before the measurement window so only the interval-clipping
    % calculation is exercised; classic collisions otherwise keep retrying.
    cfg.sim_hard_end_us = 500;
    cfg.cca_mode = 'disabled';
    scenario = prepare_scenario_v2(cfg,20260723);
    trace = make_manual_arrival_trace([0;0],[1;2],cfg);
    result = simulate_sb_cf_v2(trace,scenario,cfg,1,1,15001);
    assert(result.diagnostics.rts_fail_total>=1, ...
        'The regression setup did not create an out-of-window failure.');
    assert(result.diagnostics.collision_waste_measure_us==0, ...
        'A collision outside the measurement window leaked into its union.');
    assert_delay_and_conservation(result,trace);
end

function test_offgrid_horizon_keeps_last_arrival()
    cfg = base_test_config(1,20000,0);
    cfg.cca_mode = 'oracle';
    scenario = prepare_scenario_v2(cfg,20260727);
    trace = make_manual_arrival_trace(19998,1,cfg);
    sb_cf = simulate_sb_cf_v2(trace,scenario,cfg,1,1,15002);
    sb_cb = simulate_sb_cb_v2(trace,scenario,cfg,1,1,15003);
    assert(sb_cf.summary.final_backlog==1 && ...
           sb_cb.summary.final_backlog==1, ...
        'A final grid-aligned arrival was skipped at an off-grid horizon.');
    assert_delay_and_conservation(sb_cf,trace);
    assert_delay_and_conservation(sb_cb,trace);
end

function test_sb_cb_timing_and_collision()
    assert(exist('simulate_sb_cb_v2.m','file')==2, ...
           'simulate_sb_cb_v2.m has not been implemented.');
    cfg = base_test_config(1, 600, 600);
    cfg.cca_mode = 'oracle';
    scenario = prepare_scenario_v2(cfg, 3);
    trace = make_manual_arrival_trace(0,1,cfg);
    result = simulate_sb_cb_v2(trace,scenario,cfg,1,1,16);
    assert_equal(result.packet_log.first_attempt_us,36, ...
                 'SB-CB full DIFS before RTS');
    % DIFS-align36 + RTS14.5 + SIFS16 + 8-sector CTS scan116.0 + SIFS16
    % + payload162.5 = 361 us.
    assert_equal(result.packet_log.completion_us,361, ...
                 'SB-CB handshake/payload completion timing');
    assert_delay_and_conservation(result,trace);

    cfg2 = base_test_config(2, 500, 500);
    cfg2.cca_mode = 'disabled';
    scenario2 = prepare_scenario_v2(cfg2, 4);
    trace2 = make_manual_arrival_trace([0;0],[1;2],cfg2);
    result2 = simulate_sb_cb_v2(trace2,scenario2,cfg2,1,1,17);
    assert(result2.diagnostics.rts_attempts >= 2 && ...
           result2.diagnostics.rts_fail_collision >= 2, ...
           'SB-CB simultaneous RTS was not classified as collision.');
    assert(all(~isfinite(result2.packet_log.completion_us)) && ...
           result2.diagnostics.rts_success==0 && ...
           result2.diagnostics.rts_fail_collision>=2, ...
           'A collided RTS was captured or successfully reserved.');
    assert(result2.diagnostics.rts_sinr_used==false, ...
           'SB-CB still used RTS capture or RTS SINR.');
    assert(any(result2.packet_log.attempts>=2), ...
           'Collided RTS packets did not remain queued for retry.');
    assert_delay_and_conservation(result2,trace2);

    cfg3 = base_test_config(2,300,0);
    cfg3.cca_mode = 'disabled';
    scenario3 = prepare_scenario_v2(cfg3, 4004);
    trace3 = make_manual_arrival_trace([0;9],[1;2],cfg3);
    staggered = simulate_sb_cb_v2(trace3,scenario3,cfg3,1,1,1701);
    assert(staggered.diagnostics.rts_fail_collision>=2 && ...
           staggered.diagnostics.rts_success==0 && ...
           all(~isfinite(staggered.packet_log.completion_us)), ...
        'Partially overlapping RTS frames did not both collide.');
    assert_delay_and_conservation(staggered,trace3);
end

function test_sb_cb_separate_cts_data_thresholds()
    cfg = base_test_config(1,700,700);
    cfg.cca_mode = 'disabled';
    scenario = prepare_scenario_v2(cfg,20260728);
    noise_w = 10^((scenario.PHY.NOISE_DBM-30)/10);
    trace = make_manual_arrival_trace(0,1,cfg);

    cts_fail = scenario;
    cts_fail.PHY.AP_Sector_Tx_Matrix(:) = noise_w*10^(5/10);
    cts_fail.PHY.AP_Rx_Matrix(:) = noise_w*10^(30/10);
    low_cts = simulate_sb_cb_v2(trace,cts_fail,cfg,1,1,16001);
    assert(low_cts.diagnostics.rts_success>=1 && ...
           low_cts.diagnostics.cts_miss_winner>=1 && ...
           all(~isfinite(low_cts.packet_log.completion_us)), ...
        'A 5-dB CTS was decoded despite the 6-dB CTS threshold.');

    data_fail = scenario;
    data_fail.PHY.AP_Sector_Tx_Matrix(:) = noise_w*10^(10/10);
    data_fail.PHY.AP_Rx_Matrix(:) = noise_w*10^(20/10);
    low_data = simulate_sb_cb_v2(trace,data_fail,cfg,1,1,16002);
    assert(low_data.diagnostics.rts_success>=1 && ...
           low_data.diagnostics.data_fail_sinr>=1 && ...
           all(~isfinite(low_data.packet_log.completion_us)), ...
        'A 20-dB DATA frame passed the 21-dB DATA threshold.');

    success = scenario;
    success.PHY.AP_Sector_Tx_Matrix(:) = noise_w*10^(10/10);
    success.PHY.AP_Rx_Matrix(:) = noise_w*10^(22/10);
    passed = simulate_sb_cb_v2(trace,success,cfg,1,1,16003);
    assert(isfinite(passed.packet_log.completion_us) && ...
           passed.diagnostics.cts_sinr_th_db==6 && ...
           passed.diagnostics.data_sinr_th_db==21, ...
        'Separate 6-dB CTS and 21-dB DATA thresholds were not applied.');
    assert_delay_and_conservation(low_cts,trace);
    assert_delay_and_conservation(low_data,trace);
    assert_delay_and_conservation(passed,trace);
end

function test_s7_exact_timing()
    cfg = base_test_config(1, 1000, 1000);
    scenario = prepare_scenario_v2(cfg, 5);
    trace = make_manual_arrival_trace(0,1,cfg);
    result = simulate_s7_v2('s7_clean',trace,scenario,cfg,1,1,18);
    assert_equal(result.packet_log.first_attempt_us,36, ...
                 'S7 DIFS-aligned 36-us timing');
    expected = 36 + scenario.SUB7.RTS_US + scenario.SUB7.SIFS_US + ...
        scenario.SUB7.CTS_US + scenario.SUB7.SIFS_US + ...
        scenario.MMW_REAL.CONN_OVERHEAD_US;
    assert(abs(result.packet_log.completion_us - expected) < 1e-9, ...
        'S7 request/response/exact-payload timing');
    assert_delay_and_conservation(result,trace);
end

function test_sb_cb_counterfactual_cca()
    % The event-driven SB-CB engine senses the real channel; with the
    % hidden-terminal setup (zero interference matrix) two nodes never
    % sense each other, so both RTS attempts proceed and collide at the AP.
    cfg = base_test_config(2,100,0);
    cfg.cca_mode = 'directional';
    cfg.rx_sens_dbm = -62;
    % Both nodes arrive at t=0 so their DIFS-aligned RTS share the same
    % boundary and overlap at the AP (zero interference => no carrier
    % sensing between them).
    trace = make_manual_arrival_trace([0;0],[1;2],cfg);

    classic = prepare_scenario_v2(cfg,46);
    classic.PHY.AP_Rx_Matrix(:) = 0;
    classic.PHY.Int_Matrix(:) = 0;
    missed = simulate_sb_cb_v2(trace,classic,cfg,1,1,173);
    assert(missed.diagnostics.rts_attempts>=2 && ...
           missed.diagnostics.rts_fail_collision>=1 && ...
           missed.diagnostics.rts_success==0, ...
        'Hidden-terminal RTS pair did not collide at the AP.');
    assert(missed.diagnostics.rts_sinr_used==false, ...
        'RTS decoding must not use SINR.');
    assert_delay_and_conservation(missed,trace);
end

function test_sb_cb_cts_halfduplex_and_late_data()
    cfg=base_test_config(40,700,700);
    cfg.cca_mode='disabled';
    cfg.collect_debug_trace=true;
    scenario=prepare_scenario_v2(cfg,480);
    scenario.PHY.Int_Matrix(:)=0;
    scenario.PHY.AP_Sector_Tx_Matrix(:)=1e-6;
    scenario.PHY.AP_Rx_Matrix(:)=0;
    scenario.PHY.AP_Rx_Matrix(1:cfg.n_nodes+1:end)=1e-6;
    % A late node-2 RTS is strong interference to node 1 at the AP.
    scenario.PHY.AP_Rx_Matrix(1,2)=1e-6;
    trace=make_manual_arrival_trace([0;36],[1;2],cfg);
    result=simulate_sb_cb_v2(trace,scenario,cfg,1,1,481);
    assert(result.diagnostics.late_start_data>=1 && ...
           result.diagnostics.data_partial_collision_events>=1, ...
        'A CTS-deaf retry during data did not create the intended partial collision.');
    assert(result.diagnostics.data_failure_transaction_delay_us>=492.3, ...
        'Failed data transaction did not include control plus payload time.');
    % The node-2 retries land at DIFS-aligned boundaries after each
    % CTS-timeout / NAV release (values differ from the legacy 9-us grid).
    node2_starts=result.diagnostics.rts_start_times_us( ...
        result.diagnostics.rts_start_nodes==2);
    assert(numel(node2_starts)>=3, ...
        'Half-duplex node did not retry through CTS timeout and fresh DIFS.');
    assert_delay_and_conservation(result,trace);
end

function test_sb_cb_nav_exact_expiry()
    cfg=base_test_config(40,700,700);
    cfg.cca_mode='directional';
    cfg.collect_debug_trace=true;
    scenario=prepare_scenario_v2(cfg,482);
    scenario.PHY.Int_Matrix(:)=0;
    scenario.PHY.AP_Sector_Tx_Matrix(:)=1e-6;
    scenario.PHY.AP_Rx_Matrix(:)=0;
    scenario.PHY.AP_Rx_Matrix(1:cfg.n_nodes+1:end)=1e-6;
    trace=make_manual_arrival_trace([0;99],[1;3],cfg);
    result=simulate_sb_cb_v2(trace,scenario,cfg,1,1,483);
    assert(result.diagnostics.nav_set>=1, ...
        'The bystander did not decode CTS/NAV in the controlled scenario.');
    node3_starts=result.diagnostics.rts_start_times_us( ...
        result.diagnostics.rts_start_nodes==3);
    % Node 1 (t=0): DIFS-align 36 + handshake + payload = 361 us.  Node 3
    % is NAV-protected until 361, then aligns a fresh DIFS to 396 us.
    assert(~isempty(node3_starts) && node3_starts(1)==396, ...
        'The bystander transmitted before NAV expiry plus a fresh DIFS.');
    assert_delay_and_conservation(result,trace);
end

function test_sb_cb_response_timeout()
    cfg = base_test_config(2, 300, 0);
    cfg.cca_mode = 'disabled';
    cfg.collect_debug_trace = true;
    scenario = prepare_scenario_v2(cfg, 44);
    trace = make_manual_arrival_trace([0;0],[1;2],cfg);
    result = simulate_sb_cb_v2(trace,scenario,cfg,1,1,171);
    assert_equal(result.packet_log.first_attempt_us,[36;36], ...
                 'SB-CB response timeout followed by fresh DIFS');
    assert(result.diagnostics.rts_response_timeouts>=2, ...
           'The first failed RTS pair did not wait for CTS timeout.');
    assert(all(abs(result.packet_log.collision_delay_us - 293) < 1e-9), ...
        'RTS failure delay must include RTS plus CTS response timeout');
    assert_delay_and_conservation(result,trace);
end

function test_s7_collision_does_not_freeze_bystander()
    cfg = base_test_config(3, 700, 0);
    scenario = prepare_scenario_v2(cfg, 45);
    trace = make_manual_arrival_trace([0;0;99],[1;2;3],cfg);
    result = simulate_s7_v2('s7_clean',trace,scenario,cfg,1,1,172);
    assert_equal(result.packet_log.first_attempt_us(1:3),[36;36;135], ...
        'S7 bystander progress during collided senders response timeout');
    assert(result.diagnostics.mlo_collision_timeouts>=2, ...
           'Collided S7 senders did not enter response timeout.');
    assert_delay_and_conservation(result,trace);
end

function test_all_protocol_conservation()
    assert(exist('simulate_sb_cb_v2.m','file')==2, ...
           'simulate_sb_cb_v2.m has not been implemented.');
    cfg = base_test_config(4, 5000, 5000);
    scenario = prepare_scenario_v2(cfg, 6);
    trace = generate_arrival_trace(30,cfg,24680);
    protocols = {'sf_cf','sf_cb','sb_cf','sb_cb','s7_clean','s7_busy'};
    for i=1:numel(protocols)
        result = run_protocol_v2(protocols{i},trace,scenario,cfg,1,0.2,100+i);
        assert_delay_and_conservation(result,trace);
    end
end

function test_serial_parallel_packet_equivalence()
    if ~license('test','Distrib_Computing_Toolbox')
        return;
    end
    cfg = base_test_config(8,2000,4000);
    scenario = prepare_scenario_v2(cfg,606);
    trace = make_manual_arrival_trace([0;0;198;396],[1;2;1;3],cfg);
    protocols = {'sf_cf','sf_cb','sb_cf','sb_cb','s7_clean','s7_busy'};
    seeds = 9100+(1:numel(protocols));
    serial = cell(numel(protocols),1);
    for i=1:numel(protocols)
        serial{i}=run_protocol_v2(protocols{i},trace,scenario,cfg,1,0.2,seeds(i));
    end

    pool = gcp('nocreate');
    created_pool = isempty(pool);
    if created_pool
        pool = parpool('local',2);
        cleanup = onCleanup(@() delete(pool)); %#ok<NASGU>
    end
    parallel = cell(numel(protocols),1);
    parfor i=1:numel(protocols)
        parallel{i}=run_protocol_v2(protocols{i},trace,scenario,cfg,1,0.2,seeds(i));
    end
    for i=1:numel(protocols)
        assert(isequaln(serial{i},parallel{i}), ...
            'Serial/parallel result mismatch for %s.',protocols{i});
    end
end

function test_analysis_protocol_q_grid_and_filter()
    output_dir=tempname;
    cleanup=onCleanup(@() remove_test_output(output_dir));
    cfg=default_experiment_config('analysis');
    cfg.protocols={'sf_cb','sb_cf'};
    cfg.lambda_values=5;
    cfg.M_values=[1 2];
    cfg.load_modes={'fixed_packet'};
    cfg.n_tune_runs=1;
    cfg.q_coarse_tune_runs=1;
    cfg.q_fine_tune_runs=1;
    cfg.q_validation_runs=0;
    cfg.n_eval_runs=1;
    cfg.warmup_us=0;
    cfg.measure_us=2e4;
    cfg.drain_max_us=2e4;
    cfg.tune_warmup_us=0;
    cfg.tune_measure_us=2e4;
    cfg.tune_drain_max_us=2e4;
    cfg.tune_measure_max_us=2e4;
    cfg.tune_min_expected_arrivals=0;
    cfg.parallel=false;
    cfg.run_preflight_tests=false;
    cfg.condition_filter={ ...
        'sf_cb_fixed_packet_lam5_M1', ...
        'sb_cf_fixed_packet_lam5_M2'};
    cfg.output_dir=output_dir;
    experiment=run_experiment(cfg);
    sf_cb=load(fullfile(output_dir,'checkpoints', ...
        'sf_cb_fixed_packet_lam5_M1.mat'));
    sb_cf=load(fullfile(output_dir,'checkpoints', ...
        'sb_cf_fixed_packet_lam5_M2.mat'));
    assert(isequal([sf_cb.condition.tuning.coarse_grid.q], ...
        cfg.protocol_q_grids.sf_cb), ...
        'SF-CB protocol coarse q grid was not selected.');
    assert(isequal([sb_cf.condition.tuning.coarse_grid.q], ...
        cfg.protocol_q_grids.sb_cf), ...
        'SB-CF protocol coarse q grid was not selected.');
    assert(~isempty(sf_cb.condition.tuning.refined_grid) && ...
           ~isempty(sb_cf.condition.tuning.refined_grid), ...
        'Two-stage analysis tuning did not create a local fine grid.');
    assert(height(experiment.summary)==2, ...
        'Condition filter did not restrict the runner to two conditions.');
    assert(numel(dir(fullfile(output_dir,'checkpoints','*.mat')))==2, ...
        'Condition filter wrote an unexpected number of checkpoints.');
    clear cleanup;
    remove_test_output(output_dir);
end

function test_runner_checkpoint_resume_and_guard()
    output_dir = tempname;
    cleanup = onCleanup(@() remove_test_output(output_dir));
    cfg = default_experiment_config('smoke');
    cfg.protocols = {'sf_cb'};
    cfg.lambda_values = 30;
    cfg.M_values = 1;
    cfg.load_modes = {'fixed_packet'};
    cfg.n_nodes = 8;
    cfg.n_sectors = 8;
    cfg.warmup_us = 0;
    cfg.measure_us = 5e4;
    cfg.drain_max_us = 1e5;
    cfg.tune_warmup_us = 0;
    cfg.tune_measure_us = 5e4;
    cfg.tune_drain_max_us = 1e5;
    cfg.n_tune_runs = 1;
    cfg.n_eval_runs = 1;
    cfg.q_coarse = [1e-5 1/8];
    cfg.q_refine_points = 0;
    cfg.parallel = false;
    cfg.run_preflight_tests = false;
    cfg.run_cca_ablation = false;
    cfg.run_topology_robustness = false;
    % The rate screen mirrors the final stability predicate exactly.  A
    % tolerance of 1 would (correctly) allow zero service, so use the
    % production-like tolerance here when asserting that q=1e-5 is rejected.
    cfg.stability_rate_tolerance = 0.05;
    cfg.stability_censor_tolerance = 1;
    cfg.stability_require_slope = false;
    cfg.output_dir = output_dir;
    cfg.resume = true;

    first = run_experiment(cfg);
    assert(height(first.summary)==1 && ...
        strcmp(char(first.manifest.status),'completed'), ...
        'Unified runner did not produce one completed condition.');
    assert(isfile(fullfile(output_dir,'summary.csv')) && ...
        isfile(fullfile(output_dir,'manifest.json')) && ...
        numel(dir(fullfile(output_dir,'checkpoints','*.mat')))==1, ...
        'Unified runner did not write its versioned artifacts.');
    checkpoint_files = dir(fullfile(output_dir,'checkpoints','*.mat'));
    saved = load(fullfile(checkpoint_files(1).folder,checkpoint_files(1).name), ...
                 'condition');
    tuning_grid = saved.condition.tuning.grid;
    low_q = find(abs([tuning_grid.q]-1e-5)<eps,1);
    assert(~isempty(low_q) && ...
        tuning_grid(low_q).rate_screen_rejected_fraction==1, ...
        'Provably rate-infeasible tuning q was not screened before drain.');

    resumed = run_experiment(cfg);
    assert(isequaln(first.summary,resumed.summary), ...
        'Checkpoint resume changed the condition summary.');

    changed = cfg;
    changed.lambda_values = 31;
    rejected = false;
    try
        run_experiment(changed);
    catch cause
        rejected = strcmp(cause.identifier,'run_experiment:ConfigHashMismatch');
    end
    assert(rejected, ...
        'A scientifically different config reused an existing output directory.');
    clear cleanup;
    remove_test_output(output_dir);
end

function test_independent_q_validation_flow()
    output_dir = tempname;
    cleanup = onCleanup(@() remove_test_output(output_dir));
    cfg = default_experiment_config('analysis');
    cfg.protocols = {'sf_cf'};
    cfg.load_modes = {'fixed_packet'};
    cfg.lambda_values = 5;
    cfg.M_values = 1;
    cfg.warmup_us = 0;
    cfg.measure_us = 1e5;
    cfg.drain_max_us = 2e5;
    cfg.tune_warmup_us = 0;
    cfg.tune_measure_us = 1e5;
    cfg.tune_drain_max_us = 2e5;
    cfg.tune_measure_max_us = 1e5;
    cfg.q_coarse_tune_runs = 1;
    cfg.q_fine_tune_runs = 2;
    cfg.q_validation_runs = 1;
    cfg.q_validation_max_candidates = 2;
    cfg.n_eval_runs = 1;
    cfg.protocol_q_grids.sf_cf = ...
        [0.01 0.02 0.05 0.1 0.2 0.4 0.6 0.8 1];
    cfg.stability_rate_tolerance = 1;
    cfg.stability_censor_tolerance = 1;
    cfg.stability_require_slope = false;
    cfg.parallel = false;
    cfg.run_preflight_tests = false;
    cfg.output_dir = output_dir;
    cfg.resume = false;

    experiment = run_experiment(cfg);
    row = experiment.summary(1,:);
    assert(row.q_validation_runs==1 && ...
           row.q_validation_candidates_tested>=1 && ...
           row.q_validation_passed && isfinite(row.best_q), ...
        'Independent q validation did not select a finite validated q.');
    checkpoint = load(fullfile(output_dir,'checkpoints', ...
        'sf_cf_fixed_packet_lam5_M1.mat'),'condition');
    tune = checkpoint.condition.tuning;
    assert(~isempty(tune.q_validation_records) && ...
           tune.q_validation_selected_rank==1 && ...
           abs(tune.q_validation_records(1).q-row.best_q)<1e-12, ...
        'The q-validation record does not match the final selected q.');
    clear cleanup;
    remove_test_output(output_dir);
end

function grid = fake_q_grid(q,stable_fraction,mean_delay_us)
    n = numel(q);
    grid = repmat(struct('q',NaN,'stable_fraction',0, ...
        'mean_delay_us',NaN,'se_delay_us',0,'mean_p95_us',NaN, ...
        'mean_collision_waste_us',NaN),1,n);
    for i=1:n
        grid(i).q = q(i);
        grid(i).stable_fraction = stable_fraction(i);
        grid(i).mean_delay_us = mean_delay_us(i);
        grid(i).mean_p95_us = mean_delay_us(i);
        grid(i).mean_collision_waste_us = i;
    end
end

function cfg = base_test_config(n_nodes, measure_us, drain_us)
    cfg = default_experiment_config('smoke');
    % The production topology places an equal number of stations in each
    % of eight sectors.  Keep that invariant even when a test only injects
    % packets into one or two of the stations.
    cfg.n_nodes = max(8,8*ceil(n_nodes/8));
    cfg.n_sectors = 8;
    cfg.warmup_us = 0;
    cfg.measure_us = measure_us;
    cfg.drain_max_us = drain_us;
    cfg.arrival_end_us = cfg.warmup_us + cfg.measure_us;
    cfg.sim_hard_end_us = cfg.arrival_end_us + cfg.drain_max_us;
    cfg.parallel = false;
    cfg.collect_debug_trace = false;
    cfg.stats_sample_us = min(100,measure_us);
    cfg.stability_rate_tolerance = 10;
    cfg.stability_censor_tolerance = 1;
    cfg.stability_slope_fraction = 10;
    cfg.stability_require_slope = false;
end

function assert_delay_and_conservation(result,trace)
    completed = isfinite(result.packet_log.completion_us);
    identity_error = result.packet_log.total_delay_us(completed) - ...
        result.packet_log.queue_delay_us(completed) - ...
        result.packet_log.access_delay_us(completed);
    assert(all(abs(identity_error)<1e-9), ...
           'total_delay != queue_delay + access_delay.');
    assert(trace.n_packets == sum(completed) + result.summary.final_backlog, ...
           'Packet conservation failed.');
    assert(result.summary.packet_conservation_ok, ...
           'Result did not certify packet conservation.');
    components = {'boundary_wait_us','difs_wait_us','probability_wait_us', ...
        'busy_nav_wait_us','collision_delay_us','control_delay_us', ...
        'data_delay_us','other_access_delay_us'};
    if all(isfield(result.packet_log,components))
        component_sum = zeros(size(result.packet_log.access_delay_us));
        for i=1:numel(components)
            component_sum = component_sum + result.packet_log.(components{i});
        end
        assert(all(abs(component_sum(completed) - ...
            result.packet_log.access_delay_us(completed)) < 1e-9), ...
            'Access-delay component accounting is not exact.');
    end
end

function assert_equal(actual,expected,label)
    assert(isequaln(double(actual(:)),double(expected(:))), ...
           '%s differs: actual=%s expected=%s', label, ...
           mat2str(actual(:).'),mat2str(expected(:).'));
end

function write_report_json(path,report)
    fid = fopen(path,'w');
    if fid<0
        error('run_v2_tests:ReportWrite','Cannot write %s.',path);
    end
    cleanup = onCleanup(@() fclose(fid));
    fwrite(fid,jsonencode(report,'PrettyPrint',true),'char');
end

function remove_test_output(path)
    if isfolder(path), rmdir(path,'s'); end
end



