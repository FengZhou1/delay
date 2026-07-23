function report = run_v2_tests(output_dir)
%RUN_V2_TESTS Deterministic timing and accounting tests for the v2 simulator.
%   report = RUN_V2_TESTS() executes the complete deterministic suite.
%   A machine-readable MAT/JSON report is written when output_dir is given.

    if nargin < 1
        output_dir = '';
    end

    tests = { ...
        @test_config_rejects_fractional_M, ...
        @test_hash_ignores_runtime_output_path, ...
        @test_all_censored_cohort_is_unstable, ...
        @test_optional_slope_gate_can_be_disabled, ...
        @test_common_arrival_trace_reproducible, ...
        @test_theory_boundary_trace_is_explicit, ...
        @test_single_packet_M_endpoints, ...
        @test_sf_cf_single_and_boundary, ...
        @test_sf_cb_exact_payload, ...
        @test_aloha_classic_collision, ...
        @test_sb_cf_fresh_difs, ...
        @test_sb_cf_simultaneous_capture, ...
        @test_sb_cf_empty_measurement_collision_intervals, ...
        @test_sb_cb_timing_and_collision, ...
        @test_sb_cb_response_timeout, ...
        @test_sb_cb_counterfactual_cca, ...
        @test_sb_cb_cts_halfduplex_and_late_data, ...
        @test_sb_cb_nav_exact_expiry, ...
        @test_s7_exact_timing, ...
        @test_s7_collision_does_not_freeze_bystander, ...
        @test_all_protocol_conservation, ...
        @test_serial_parallel_packet_equivalence, ...
        @test_analysis_protocol_q_grid_and_filter, ...
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
           'An arrival is not on the common 5-us physical grid.');
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
    cfg = base_test_config(1, 380, 380);
    scenario = prepare_scenario_v2(cfg, 1);
    trace = make_manual_arrival_trace([0;190],[1;1],cfg);
    result = simulate_aloha_v2('sf_cf',trace,scenario,cfg,1,1,11);
    assert_equal(result.packet_log.hol_us,[0;190],'SF-CF HOL timing');
    assert_equal(result.packet_log.first_attempt_us,[0;190], ...
                 'SF-CF boundary decision ordering');
    assert_equal(result.packet_log.completion_us,[190;380], ...
                 'SF-CF completion timing');
    assert_delay_and_conservation(result,trace);
end

function test_theory_boundary_trace_is_explicit()
    cfg=base_test_config(8,3800,0);
    trace=generate_boundary_arrival_trace(30,cfg,125,190);
    assert(trace.theory_boundary_only && all(mod(trace.times_us,190)==0), ...
        'Theory-only arrivals were not aligned to 190-us boundaries.');
    assert(trace.tick_us==190 && cfg.arrival_tick_us==5, ...
        'Theory trace obscured the common physical arrival-grid definition.');
end

function test_single_packet_M_endpoints()
    cfg=base_test_config(1,3000,1000);
    cfg.cca_mode='oracle';
    scenario=prepare_scenario_v2(cfg,515);
    trace=make_manual_arrival_trace(0,1,cfg);
    for M=[1 6]
        tp=190*M;
        sf_cf=run_protocol_v2('sf_cf',trace,scenario,cfg,M,1,5100+M);
        sf_cb=run_protocol_v2('sf_cb',trace,scenario,cfg,M,1,5200+M);
        sb_cf=run_protocol_v2('sb_cf',trace,scenario,cfg,M,1,5300+M);
        sb_cb=run_protocol_v2('sb_cb',trace,scenario,cfg,M,1,5400+M);
        s7=run_protocol_v2('s7_clean',trace,scenario,cfg,M,1,5500+M);
        assert_equal(sf_cf.packet_log.completion_us,tp, ...
            sprintf('SF-CF M=%d exact payload completion',M));
        assert_equal(sf_cb.packet_log.completion_us,190+tp, ...
            sprintf('SF-CB M=%d reservation plus payload',M));
        assert_equal(sb_cf.packet_log.completion_us,15+tp, ...
            sprintf('SB-CF M=%d DIFS plus payload',M));
        assert_equal(sb_cb.packet_log.completion_us,205+tp, ...
            sprintf('SB-CB M=%d handshake plus payload',M));
        expected_s7=scenario.SUB7.DIFS_US + scenario.SUB7.ICF_US + ...
            scenario.SUB7.SIFS_US + scenario.SUB7.ICR_US + ...
            scenario.SUB7.SIFS_US + tp;
        assert_equal(s7.packet_log.completion_us,expected_s7, ...
            sprintf('S7-clean M=%d control plus payload',M));
        results={sf_cf,sf_cb,sb_cf,sb_cb,s7};
        for i=1:numel(results), assert_delay_and_conservation(results{i},trace); end
    end
end

function test_sf_cb_exact_payload()
    cfg = base_test_config(1, 760, 760);
    scenario = prepare_scenario_v2(cfg, 1);
    trace = make_manual_arrival_trace(0,1,cfg);
    result = simulate_aloha_v2('sf_cb',trace,scenario,cfg,2,1,12);
    assert_equal(result.packet_log.first_attempt_us,0,'SF-CB first attempt');
    assert_equal(result.packet_log.completion_us,570, ...
                 'SF-CB must use 190-us reservation plus exact 380-us payload');
    assert(abs(result.summary.mean_system_packets-0.75)<1e-12, ...
           'SF-CB exact system-area integral is wrong.');
    assert(abs(result.summary.mean_service_packets-0.5)<1e-12, ...
           'SF-CB exact payload service-area integral is wrong.');
    assert_delay_and_conservation(result,trace);
end

function test_aloha_classic_collision()
    cfg = base_test_config(2, 380, 380);
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
    cfg = base_test_config(1, 500, 500);
    cfg.cca_mode = 'oracle';
    scenario = prepare_scenario_v2(cfg, 1);
    trace = make_manual_arrival_trace([0;5],[1;1],cfg);
    result = simulate_sb_cf_v2(trace,scenario,cfg,1,1,14);
    assert_equal(result.packet_log.hol_us,[0;205], ...
                 'SB-CF next-HOL timing');
    assert_equal(result.packet_log.first_attempt_us,[15;220], ...
                 'SB-CF fresh full-DIFS timing');
    assert_equal(result.packet_log.completion_us,[205;410], ...
                 'SB-CF completion timing');
    assert_delay_and_conservation(result,trace);
end

function test_sb_cf_simultaneous_capture()
    cfg = base_test_config(2, 400, 400);
    cfg.cca_mode = 'disabled';
    scenario = prepare_scenario_v2(cfg, 2);
    trace = make_manual_arrival_trace([0;0],[1;2],cfg);
    result = simulate_sb_cf_v2(trace,scenario,cfg,1,1,15);
    assert(result.diagnostics.simultaneous_start_events>=1, ...
           'SB-CF simultaneous-start diagnostic was not triggered.');
    assert(result.diagnostics.capture_opportunities>=1, ...
           'SB-CF capture opportunity was not recorded.');
    assert(sum(isfinite(result.packet_log.completion_us))<=1, ...
           'The single-user AP decoded more than one simultaneous frame.');
    assert_delay_and_conservation(result,trace);
end

function test_sb_cf_empty_measurement_collision_intervals()
    cfg = base_test_config(2,500,0);
    cfg.warmup_us = 500;
    cfg.measure_us = 500;
    cfg.arrival_end_us = 1000;
    cfg.sim_hard_end_us = 1000;
    cfg.cca_mode = 'disabled';
    scenario = prepare_scenario_v2(cfg,20260723);
    trace = make_manual_arrival_trace([0;0],[1;2],cfg);
    result = simulate_sb_cf_v2(trace,scenario,cfg,1,1,15001);
    assert(result.diagnostics.failed_attempts>=1, ...
        'The regression setup did not create an out-of-window failure.');
    assert(result.diagnostics.collision_channel_time_measure_us==0, ...
        'A collision outside the measurement window leaked into its union.');
    assert_delay_and_conservation(result,trace);
end

function test_sb_cb_timing_and_collision()
    assert(exist('simulate_sb_cb_v2.m','file')==2, ...
           'simulate_sb_cb_v2.m has not been implemented.');
    cfg = base_test_config(1, 600, 600);
    cfg.cca_mode = 'oracle';
    scenario = prepare_scenario_v2(cfg, 3);
    trace = make_manual_arrival_trace(0,1,cfg);
    result = simulate_sb_cb_v2(trace,scenario,cfg,1,1,16);
    assert_equal(result.packet_log.first_attempt_us,15, ...
                 'SB-CB full DIFS before RTS');
    % RTS20 + SIFS5 + 8-sector CTS scan160 + SIFS5 + payload190.
    assert_equal(result.packet_log.completion_us,395, ...
                 'SB-CB handshake/payload completion timing');
    assert_delay_and_conservation(result,trace);

    cfg2 = base_test_config(2, 500, 500);
    cfg2.cca_mode = 'disabled';
    scenario2 = prepare_scenario_v2(cfg2, 4);
    trace2 = make_manual_arrival_trace([0;0],[1;2],cfg2);
    result2 = simulate_sb_cb_v2(trace2,scenario2,cfg2,1,1,17);
    assert(result2.diagnostics.rts_simultaneous_events >= 1, ...
           'SB-CB simultaneous RTS was not classified.');
    first_transaction_completions = ...
        sum(result2.packet_log.completion_us == 395);
    assert(first_transaction_completions==1 && ...
           numel(unique(result2.packet_log.completion_us(isfinite( ...
               result2.packet_log.completion_us)))) == ...
           sum(isfinite(result2.packet_log.completion_us)), ...
           'The single-user AP completed simultaneous payloads.');
    assert(any(result2.packet_log.attempts>=2), ...
           'The uncaptured RTS did not remain queued for a retry.');
    assert_delay_and_conservation(result2,trace2);
end

function test_s7_exact_timing()
    cfg = base_test_config(1, 1000, 1000);
    scenario = prepare_scenario_v2(cfg, 5);
    trace = make_manual_arrival_trace(0,1,cfg);
    result = simulate_s7_v2('s7_clean',trace,scenario,cfg,1,1,18);
    assert_equal(result.packet_log.first_attempt_us,36, ...
                 'S7 full 36-us DIFS timing');
    assert_equal(result.packet_log.completion_us,388, ...
                 'S7 request/response/exact-payload timing');
    assert_delay_and_conservation(result,trace);
end

function test_sb_cb_counterfactual_cca()
    cfg = base_test_config(2,100,0);
    cfg.cca_mode = 'directional';
    cfg.rx_sens_dbm = -62;
    trace = make_manual_arrival_trace([0;20],[1;2],cfg);

    harmful = prepare_scenario_v2(cfg,46);
    harmful.PHY.AP_Rx_Matrix(:) = 0;
    harmful.PHY.AP_Rx_Matrix(1:9:end) = 1e-6;
    harmful.PHY.AP_Rx_Matrix(1,2) = 1e-6;
    harmful.PHY.AP_Rx_Matrix(2,1) = 1e-12;
    harmful.PHY.Int_Matrix(:) = 0;
    missed = simulate_sb_cb_v2(trace,harmful,cfg,1,1,173);
    assert(missed.diagnostics.cca_eligible_fn>0, ...
        'A hidden RTS that destroys an ongoing AP RTS was not counted as FN.');

    harmless = prepare_scenario_v2(cfg,47);
    harmless.PHY.AP_Rx_Matrix(:) = 0;
    harmless.PHY.AP_Rx_Matrix(1:9:end) = 1e-6;
    harmless.PHY.AP_Rx_Matrix(1,2) = 1e-12;
    harmless.PHY.AP_Rx_Matrix(2,1) = 1e-12;
    harmless.PHY.Int_Matrix(:) = 0;
    harmless.PHY.Int_Matrix(1,2) = 1e-6;
    false_alarm = simulate_sb_cb_v2(trace,harmless,cfg,1,1,174);
    assert(false_alarm.diagnostics.cca_eligible_fp>0, ...
        'Harmless sensed energy with a decodable own RTS was not counted as FP.');
    assert(false_alarm.diagnostics.cca_eligible_fp + ...
           false_alarm.diagnostics.cca_eligible_tn == ...
           false_alarm.diagnostics.cca_eligible_decodable_negative, ...
           'Self-undecodable opportunities leaked into the FP/TN denominator.');
    assert_delay_and_conservation(missed,trace);
    assert_delay_and_conservation(false_alarm,trace);
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
    trace=make_manual_arrival_trace([0;20],[1;2],cfg);
    result=simulate_sb_cb_v2(trace,scenario,cfg,1,1,481);
    assert(result.diagnostics.icr_miss_halfduplex>=1, ...
        'A station transmitting during its CTS sector did not lose CTS by half duplex.');
    assert(result.diagnostics.late_start_data>=1 && ...
           result.diagnostics.data_partial_collision_events>=1, ...
        'A CTS-deaf retry during data did not create the intended partial collision.');
    assert(result.diagnostics.data_failure_transaction_delay_us>=380, ...
        'Failed data transaction did not include control plus payload time.');
    node2_starts=result.diagnostics.rts_start_times_us( ...
        result.diagnostics.rts_start_nodes==2);
    assert(any(node2_starts==35) && any(node2_starts==235), ...
        'Half-duplex node did not wait through CTS timeout and a fresh DIFS.');
    assert_delay_and_conservation(result,trace);
end

function test_sb_cb_nav_exact_expiry()
    cfg=base_test_config(40,700,700);
    cfg.cca_mode='disabled';
    cfg.collect_debug_trace=true;
    scenario=prepare_scenario_v2(cfg,482);
    scenario.PHY.Int_Matrix(:)=0;
    scenario.PHY.AP_Sector_Tx_Matrix(:)=1e-6;
    scenario.PHY.AP_Rx_Matrix(:)=0;
    scenario.PHY.AP_Rx_Matrix(1:cfg.n_nodes+1:end)=1e-6;
    trace=make_manual_arrival_trace([0;100],[1;3],cfg);
    result=simulate_sb_cb_v2(trace,scenario,cfg,1,1,483);
    assert(result.diagnostics.nav_set>=1, ...
        'The bystander did not decode CTS/NAV in the controlled scenario.');
    node3_starts=result.diagnostics.rts_start_times_us( ...
        result.diagnostics.rts_start_nodes==3);
    assert(~isempty(node3_starts) && node3_starts(1)==410, ...
        'The bystander transmitted before NAV expiry plus a fresh 15-us DIFS.');
    assert_delay_and_conservation(result,trace);
end

function test_sb_cb_response_timeout()
    cfg = base_test_config(2, 250, 0);
    cfg.cca_mode = 'disabled';
    cfg.collect_debug_trace = true;
    scenario = prepare_scenario_v2(cfg, 44);
    scenario.PHY.CTRL_SINR_TH_DB = 1000; % deterministic: no RTS capture
    trace = make_manual_arrival_trace([0;0],[1;2],cfg);
    result = simulate_sb_cb_v2(trace,scenario,cfg,1,1,171);
    assert_equal(result.diagnostics.rts_start_times_us, ...
                 [15;15;215;215], ...
                 'SB-CB response timeout followed by fresh DIFS');
    assert(result.diagnostics.rts_response_timeouts==2, ...
           'The first failed RTS pair did not wait for CTS timeout.');
    assert_equal(result.packet_log.collision_delay_us,[185;185], ...
        'RTS failure delay must include RTS plus SIFS/CTS response timeout');
    assert_delay_and_conservation(result,trace);
end

function test_s7_collision_does_not_freeze_bystander()
    cfg = base_test_config(3, 700, 0);
    scenario = prepare_scenario_v2(cfg, 45);
    trace = make_manual_arrival_trace([0;0;100],[1;2;3],cfg);
    result = simulate_s7_v2('s7_clean',trace,scenario,cfg,1,1,172);
    assert_equal(result.packet_log.first_attempt_us(1:3),[36;36;144], ...
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
    trace = make_manual_arrival_trace([0;0;190;380],[1;2;1;3],cfg);
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
    assert(isequal([sf_cb.condition.tuning.grid.q], ...
        cfg.protocol_q_grids.sf_cb), ...
        'SF-CB protocol q grid was not selected.');
    assert(isequal([sb_cf.condition.tuning.grid.q], ...
        cfg.protocol_q_grids.sb_cf), ...
        'SB-CF protocol q grid was not selected.');
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
