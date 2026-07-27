function report = run_saturation_tests(output_dir)
%RUN_SATURATION_TESTS Deterministic and theoretical saturation checks.

    if nargin < 1 || isempty(output_dir)
        output_dir = fullfile(pwd,'.codex-tmp','saturation_tests');
    end
    if ~exist(output_dir,'dir'), mkdir(output_dir); end
    rows = struct('test',{},'passed',{},'observed',{},'expected',{}, ...
        'tolerance',{});

    % One-node sensing-free checks have exact airtime answers.
    cfg1 = default_saturation_config('smoke');
    cfg1.n_nodes = 1;
    cfg1.n_sectors = 1;
    cfg1.warmup_us = 0;
    timing1 = mmw_timing_config(cfg1);
    conn1_us = timing1.CONN_SLOT_US;
    cfg1.measure_us = conn1_us*120;
    cfg1.arrival_end_us = cfg1.measure_us;
    cfg1.sim_hard_end_us = cfg1.measure_us;
    cfg1.run_preflight_tests = false;
    cfg1.parallel = false;
    cfg1 = validate_saturation_config(cfg1);
    scenario1 = prepare_scenario_v2(cfg1,cfg1.topology_seed);
    trace1 = make_saturation_trace(cfg1);

    sf_cf = run_protocol_v2('sf_cf',trace1,scenario1,cfg1,1,1,101);
    rows(end+1) = check_close('single_node_sf_cf_airtime', ... %#ok<AGROW>
        sf_cf.summary.payload_airtime_fraction,1,1e-12);

    cfg_cb = cfg1;
    cfg_cb.measure_us = (conn1_us+2*conn1_us)*100;
    cfg_cb.arrival_end_us = cfg_cb.measure_us;
    cfg_cb.sim_hard_end_us = cfg_cb.measure_us;
    trace_cb = make_saturation_trace(cfg_cb);
    sf_cb = run_protocol_v2('sf_cb',trace_cb,scenario1,cfg_cb,2,1,102);
    rows(end+1) = check_close('single_node_sf_cb_airtime', ... %#ok<AGROW>
        sf_cb.summary.payload_airtime_fraction,2/3,1e-12);

    % Forty-node classic Aloha must match the analytical saturation law.
    cfg40 = default_saturation_config('smoke');
    cfg40.warmup_us = 0;
    cfg40.measure_us = 2e6;
    cfg40.arrival_end_us = cfg40.measure_us;
    cfg40.sim_hard_end_us = cfg40.measure_us;
    cfg40.run_preflight_tests = false;
    cfg40.parallel = false;
    cfg40 = validate_saturation_config(cfg40);
    scenario40 = prepare_scenario_v2(cfg40,cfg40.topology_seed);
    trace40 = make_saturation_trace(cfg40);
    q = 1/cfg40.n_nodes;
    p_success = cfg40.n_nodes*q*(1-q)^(cfg40.n_nodes-1);

    aloha_cf = run_protocol_v2('sf_cf',trace40,scenario40,cfg40,1,q,201);
    rows(end+1) = check_close('forty_node_sf_cf_theory', ... %#ok<AGROW>
        aloha_cf.summary.payload_airtime_fraction,p_success,0.025);

    aloha_cb = run_protocol_v2('sf_cb',trace40,scenario40,cfg40,2,q,202);
    expected_cb = p_success*2/(1+p_success*2);
    rows(end+1) = check_close('forty_node_sf_cb_theory', ... %#ok<AGROW>
        aloha_cb.summary.payload_airtime_fraction,expected_cb,0.035);

    % All six current state machines must preserve one virtual HOL per MLO
    % station and return a finite saturation summary.
    smoke_cfg = default_saturation_config('smoke');
    smoke_cfg.run_preflight_tests = false;
    smoke_cfg.parallel = false;
    smoke_cfg = validate_saturation_config(smoke_cfg);
    smoke_scenario = prepare_scenario_v2(smoke_cfg,smoke_cfg.topology_seed);
    smoke_trace = make_saturation_trace(smoke_cfg);
    protocols = smoke_cfg.protocols;
    for i = 1:numel(protocols)
        protocol = protocols{i};
        q_values = smoke_cfg.protocol_q_grids.(protocol);
        q_test = q_values(min(numel(q_values),ceil(numel(q_values)/2)));
        result = run_protocol_v2(protocol,smoke_trace,smoke_scenario, ...
            smoke_cfg,1,q_test,300+i);
        observed = result.summary.payload_airtime_fraction;
        passed = result.summary.saturated && isfinite(observed) && ...
            observed >= 0 && observed <= 1 && ...
            numel(result.diagnostics.saturation_per_node_completions) == ...
            smoke_cfg.n_nodes;
        rows(end+1) = struct('test',['six_protocol_' protocol], ... %#ok<AGROW>
            'passed',passed,'observed',observed,'expected',NaN, ...
            'tolerance',NaN);
    end

    % With a single SB-CF node, repeated successes must still pay a fresh
    % four-slot DIFS.  Its payload fraction must therefore stay below the
    % no-DIFS value of one and near Tp/(Tp+DIFS).
    sb_cf = run_protocol_v2('sb_cf',trace1,scenario1,cfg1,1,1,401);
    expected_sb_cf = conn1_us/(conn1_us+scenario1.MMW.DIFS_US);
    rows(end+1) = check_close('sb_cf_fresh_difs_after_success', ... %#ok<AGROW>
        sb_cf.summary.payload_airtime_fraction,expected_sb_cf,0.03);

    report = struct2table(rows);
    writetable(report,fullfile(output_dir,'saturation_tests.csv'));
    save(fullfile(output_dir,'saturation_tests.mat'),'report');
    if ~all(report.passed)
        failed = strjoin(cellstr(string(report.test(~report.passed))),', ');
        error('run_saturation_tests:Failure', ...
            'Saturation tests failed: %s',failed);
    end
    fprintf('Saturation tests passed: %d/%d\n',height(report),height(report));
end

function row = check_close(name,observed,expected,tolerance)
    row = struct('test',name, ...
        'passed',isfinite(observed) && abs(observed-expected) <= tolerance, ...
        'observed',observed,'expected',expected,'tolerance',tolerance);
end
