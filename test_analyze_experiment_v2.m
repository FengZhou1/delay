function tests = test_analyze_experiment_v2
%TEST_ANALYZE_EXPERIMENT_V2 Synthetic partial-result regression test.
    tests = functiontests(localfunctions);
end

function testPartialSfCbAndSbCf(testCase)
    root = tempname;
    mkdir(root);
    mkdir(fullfile(root,'checkpoints_cca'));
    mkdir(fullfile(root,'checkpoints_topology'));
    mkdir(fullfile(root,'checkpoints'));
    mkdir(fullfile(root,'verification','aloha_controlled'));
    cleanup = onCleanup(@() remove_test_directory(root));

    protocol = ["sf_cb";"sb_cf";"sb_cb"];
    load_mode = ["fixed_packet";"fixed_packet";"fixed_packet"];
    lambda_base = [30;30;30];
    lambda_effective = [30;30;30];
    M = [1;1;1];
    Tp_us = [198;198;198];
    best_q = [0.2;0.2;0.2];
    stable_fraction = [1;0;1];
    mean_delay_us = [500;NaN;700];
    normalized_goodput_units_s = [100;80;70];
    arrival_rate_pkt_s = [100;100;100];
    goodput_pkt_s = [98;70;90];
    little_relative_error = [0.04;NaN;0.06];
    summary = table(protocol,load_mode,lambda_base,lambda_effective,M,Tp_us, ...
                    best_q,stable_fraction,mean_delay_us, ...
                    normalized_goodput_units_s,arrival_rate_pkt_s, ...
                    goodput_pkt_s,little_relative_error);
    writetable(summary,fullfile(root,'summary.csv'));
    cfg = struct('warmup_us',0,'arrival_end_us',10000, ...
                 'cca_mode','directional','rx_sens_dbm',-62);
    save(fullfile(root,'config.mat'),'cfg');

    K = 40; q = 1/40; trials = 10000; successes = 3725;
    empirical_ps = successes/trials;
    theoretical_ps = (1-1/40)^39;
    ci_low = 0.363; ci_high = 0.382; probability_pass = 1;
    empirical_service_cycle_us = 726;
    theoretical_service_cycle_us = 730;
    service_relative_error = abs(empirical_service_cycle_us- ...
        theoretical_service_cycle_us)/theoretical_service_cycle_us;
    controlled = table(K,q,trials,successes,empirical_ps,theoretical_ps, ...
        ci_low,ci_high,probability_pass,empirical_service_cycle_us, ...
        theoretical_service_cycle_us,service_relative_error);
    writetable(controlled,fullfile(root,'verification','aloha_controlled', ...
        'aloha_theory_validation.csv'));

    aloha_diag = struct('q',0.2,'reservation_k_values',(0:2).', ...
        'reservation_full_frames_by_k',[0;100;100], ...
        'reservation_success_frames_by_k',[0;20;32], ...
        'reservation_attempts_by_k',[0;20;40]);
    packet_log = struct('completion_us',[396;792;1188;1584]);
    aloha_run = struct('diagnostics',aloha_diag,'packet_log',packet_log);
    row = struct('protocol',"sf_cb",'load_mode',"fixed_packet", ...
        'lambda_base',30,'lambda_effective',30,'M',1,'Tp_us',198,'best_q',0.2);
    condition = struct('row',row,'evaluation',{{aloha_run}});
    save(fullfile(root,'checkpoints','sf_cb.mat'),'condition');

    csma_diag = struct('cca_mode','directional', ...
        'raw_listening_busy_opportunities',100,'raw_listening_misses',90, ...
        'eligible_cca_tp',8,'eligible_cca_fn',2, ...
        'eligible_cca_fp',1,'eligible_cca_tn',9, ...
        'late_start_attempts',1,'failed_attempts',1,'collision_waste_us',198);
    csma_run = struct('diagnostics',csma_diag,'packet_log',struct('completion_us',[]));
    row = struct('protocol',"sb_cf",'load_mode',"fixed_packet", ...
        'lambda_base',30,'lambda_effective',30,'M',1,'Tp_us',198,'best_q',0.2);
    condition = struct('row',row,'evaluation',{{csma_run}});
    save(fullfile(root,'checkpoints','sb_cf.mat'),'condition');

    failure_diag = struct('cca_mode','directional', ...
        'rts_fail_total',2,'rts_failure_detection_delay_us',300, ...
        'data_fail_sinr',4,'data_failure_transaction_delay_us',792);
    failure_run = struct('diagnostics',failure_diag, ...
        'packet_log',struct('completion_us',[]));
    row = struct('protocol',"sb_cb",'load_mode',"fixed_packet", ...
        'lambda_base',30,'lambda_effective',30,'M',1,'Tp_us',198,'best_q',0.2);
    condition = struct('row',row,'evaluation',{{failure_run}});
    save(fullfile(root,'checkpoints','sb_cb.mat'),'condition');

    analysis = analyze_experiment_v2(root);
    verifyEqual(testCase,height(analysis.theory_validation),3);
    by_k = analysis.theory_validation.row_type == "by_K";
    verifyEqual(testCase,analysis.theory_validation.theoretical_ps(by_k), ...
                [0.2;0.32],'AbsTol',1e-12);
    csma = analysis.csma_diagnostics;
    sb_cf_diag = csma.protocol == "sb_cf";
    verifyEqual(testCase,csma.raw_miss_rate(sb_cf_diag),0.9,'AbsTol',1e-12);
    verifyEqual(testCase,csma.eligible_fnr(sb_cf_diag),0.2,'AbsTol',1e-12);
    sb_cb_diag = csma.protocol == "sb_cb";
    verifyEqual(testCase,csma.mean_rts_failure_detection_delay_us(sb_cb_diag),150);
    verifyEqual(testCase,csma.mean_data_failure_transaction_delay_us(sb_cb_diag),198);
    checks = analysis.acceptance_checks;
    sf = checks.protocol == "sf_cb";
    verifyEqual(testCase,checks.rate_relative_error(sf),0.02,'AbsTol',1e-12);
    verifyEqual(testCase,checks.rate_check_status(sf),"pass");
    verifyEqual(testCase,checks.little_check_status(sf),"pass");
    verifyEqual(testCase,checks.aloha_probability_check_status(sf), ...
                "diagnostic_only");
    verifyEqual(testCase,checks.aloha_controlled_hard_gate_status(sf),"pass");
    verifyEqual(testCase,checks.overall_status(sf),"pass");
    verifyEqual(testCase,checks.overall_status(checks.protocol == "sb_cf"), ...
                "not_applicable");
    sb_cb = checks.protocol == "sb_cb";
    verifyEqual(testCase,checks.rate_check_status(sb_cb),"fail");
    verifyEqual(testCase,checks.little_check_status(sb_cb),"fail");
    verifyEqual(testCase,checks.overall_status(sb_cb),"fail");
    verifyTrue(testCase,isfile(fullfile(root,'中文理论-仿真报告.md')));
    verifyTrue(testCase,isfile(fullfile(root,'theory_validation.csv')));
    verifyTrue(testCase,isfile(fullfile(root,'acceptance_checks.csv')));
    verifyTrue(testCase,isfile(fullfile(root,'figures','delay_by_M.png')));
    verifyTrue(testCase,isfile(fullfile(root,'figures', ...
        'delay_by_M_with_unstable.png')));
    report = fileread(fullfile(root,'中文理论-仿真报告.md'));
    verifyTrue(testCase,contains(report,'失败条件'));
    verifyTrue(testCase,contains(report,'SB-CB'));
    clear cleanup;
end

function testSummaryWithoutCheckpoints(testCase)
    root = tempname;
    mkdir(root);
    mkdir(fullfile(root,'checkpoints_cca'));
    mkdir(fullfile(root,'checkpoints_topology'));
    cleanup = onCleanup(@() remove_test_directory(root));
    protocol = "sf_cb";
    load_mode = "fixed_payload";
    lambda_base = 5;
    M = 1;
    stable_fraction = 0;
    mean_delay_us = NaN;
    normalized_goodput_units_s = 0;
    summary = table(protocol,load_mode,lambda_base,M,stable_fraction, ...
                    mean_delay_us,normalized_goodput_units_s);
    writetable(summary,fullfile(root,'summary.csv'));
    analysis = analyze_experiment_v2(root);
    verifyEmpty(testCase,analysis.theory_validation);
    verifyEmpty(testCase,analysis.csma_diagnostics);
    verifyEmpty(testCase,analysis.cca_ablation_diagnostics);
    verifyEmpty(testCase,analysis.topology_cluster_ci);
    verifyNotEmpty(testCase,analysis.aloha_capacity_theory);
    verifyEqual(testCase,analysis.acceptance_checks.overall_status, ...
                "not_applicable");
    verifyEqual(testCase, ...
        analysis.acceptance_checks.aloha_controlled_file_status,"missing");
    verifyEqual(testCase, ...
        analysis.acceptance_checks.aloha_controlled_hard_gate_status, ...
        "not_applicable");
    verifyTrue(testCase,isfile(fullfile(root,'cca_ablation_diagnostics.csv')));
    verifyTrue(testCase,isfile(fullfile(root,'topology_cluster_ci.csv')));
    verifyTrue(testCase,isfile(fullfile(root,'中文理论-仿真报告.md')));
    report = fileread(fullfile(root,'中文理论-仿真报告.md'));
    verifyTrue(testCase,contains(report,'缺少受控验证文件'));
    clear cleanup;
end

function testCcaAblationTopologyClustersAndCapacity(testCase)
    root = tempname;
    mkdir(root);
    mkdir(fullfile(root,'checkpoints_cca'));
    mkdir(fullfile(root,'checkpoints_topology'));
    cleanup = onCleanup(@() remove_test_directory(root));

    protocol = "sb_cb";
    load_mode = "fixed_packet";
    lambda_base = 30;
    lambda_effective = 30;
    M = 1;
    Tp_us = 198;
    best_q = 0.025;
    stable_fraction = 1;
    mean_delay_us = 200;
    normalized_goodput_units_s = 1000;
    summary = table(protocol,load_mode,lambda_base,lambda_effective,M,Tp_us, ...
        best_q,stable_fraction,mean_delay_us,normalized_goodput_units_s);
    writetable(summary,fullfile(root,'summary.csv'));
    cfg = struct('n_nodes',40,'M_values',1:2,'lambda_values',30, ...
        'load_modes',{{'fixed_packet','fixed_payload'}}, ...
        'warmup_us',0,'arrival_end_us',10000, ...
        'cca_mode','directional','rx_sens_dbm',-62);
    save(fullfile(root,'config.mat'),'cfg');

    cca_row = synthetic_cca_row("directional_-62dBm","directional",-62,200,1000);
    diag = struct('cca_mode','directional','rx_sens_dbm',-70, ...
        'raw_listening_busy_opportunities',100,'raw_listening_misses',90, ...
        'eligible_cca_tp',8,'eligible_cca_fn',2, ...
        'eligible_cca_fp',1,'eligible_cca_tn',9, ...
        'late_start_handshake',1,'late_start_data',2, ...
        'failed_attempts',3,'collision_channel_time_us',25, ...
        'collision_tx_airtime_us',50, ...
        'rts_fail_total',2,'rts_failure_detection_delay_us',300, ...
        'data_fail_sinr',4,'data_failure_transaction_delay_us',792);
    run = struct('diagnostics',diag,'packet_log',struct('completion_us',[]));
    condition = struct('row',cca_row,'evaluation',{{run}});
    save(fullfile(root,'checkpoints_cca','directional.mat'),'condition');

    % The duplicate directional CSV row must not overwrite richer checkpoint
    % diagnostics.  The oracle row exists only in CSV and must still appear.
    duplicate = cca_row; duplicate.mean_delay_us = 9999;
    oracle = synthetic_cca_row("perfect","perfect",-62,160,1100);
    oracle.eligible_tp = 10; oracle.eligible_fn = 0;
    oracle.eligible_fp = 0; oracle.eligible_tn = 10;
    cca_csv = struct2table([duplicate oracle]);
    writetable(cca_csv,fullfile(root,'cca_ablation.csv'));

    delays = [100 120 140 160];
    goodputs = [1000 1100 900 1000];
    topology_rows = repmat(synthetic_topology_row(1,100,1000),1,4);
    for seed = 1:4
        topology_rows(seed) = synthetic_topology_row(seed,delays(seed),goodputs(seed));
        if seed <= 3
            condition = struct('row',topology_rows(seed),'evaluation',{{}});
            save(fullfile(root,'checkpoints_topology',sprintf('topo%d.mat',seed)), ...
                 'condition');
        end
    end
    unstable = synthetic_topology_row(11,NaN,800);
    unstable.M = 2; unstable.Tp_us = 396;
    unstable.stable_fraction = 0; unstable.p95_delay_us = NaN;
    unstable.backlog_slope_pkt_s = 25; unstable.completion_ratio = 0.7;
    topology_rows(end+1) = unstable;
    writetable(struct2table(topology_rows), ...
               fullfile(root,'topology_robustness.csv'));

    analysis = analyze_experiment_v2(root);
    cca = analysis.cca_ablation_diagnostics;
    verifyEqual(testCase,height(cca),2);
    directional = cca.cca_variant == "directional_-62dBm";
    verifyEqual(testCase,cca.mean_delay_us(directional),200);
    verifyEqual(testCase,cca.rx_sens_dbm(directional),-62);
    verifyEqual(testCase,cca.eligible_fnr(directional),0.2,'AbsTol',1e-12);
    verifyEqual(testCase, ...
        cca.mean_rts_failure_detection_delay_us(directional),150);
    verifyEqual(testCase, ...
        cca.mean_data_failure_transaction_delay_us(directional),198);
    verifyTrue(testCase,any(cca.cca_variant == "perfect"));
    verifyEqual(testCase,cca.eligible_fnr(cca.cca_variant == "perfect"),0);

    topo = analysis.topology_cluster_ci;
    verifyEqual(testCase,height(topo),2);
    topo_M1 = topo(topo.M == 1,:);
    verifyEqual(testCase,topo_M1.n_topology_clusters,4);
    verifyEqual(testCase,topo_M1.mean_delay_us_mean,130,'AbsTol',1e-12);
    expected_ci = tinv(0.975,3)*std(delays)/sqrt(4);
    verifyEqual(testCase,topo_M1.mean_delay_us_ci95,expected_ci,'AbsTol',1e-10);
    verifyEqual(testCase,topo_M1.normalized_goodput_units_s_mean,1000,'AbsTol',1e-12);
    verifyTrue(testCase,isnan(topo.mean_delay_us_mean(topo.M == 2)));
    verifyEqual(testCase,topo.stable_topology_fraction(topo.M == 2),0);

    capacity = analysis.aloha_capacity_theory;
    cap = capacity(capacity.load_mode == "fixed_packet" & capacity.M == 1,:);
    ps = 40*(1/40)*(1-1/40)^39;
    expected_rho = 40*30*(198+198/ps)/1e6;
    verifyEqual(testCase,cap.q_opt,1/40,'AbsTol',1e-12);
    verifyEqual(testCase,cap.rho,expected_rho,'AbsTol',1e-12);
    verifyTrue(testCase,isfile(fullfile(root,'figures','cca_ablation_diagnostics.png')));
    verifyTrue(testCase,isfile(fullfile(root,'figures','topology_cluster_ci.png')));
    verifyTrue(testCase,isfile(fullfile(root,'aloha_capacity_theory.csv')));
    report = fileread(fullfile(root,'中文理论-仿真报告.md'));
    verifyTrue(testCase,contains(report,'topology seed'));
    verifyTrue(testCase,contains(report,'lambda_base=30'));
    clear cleanup;
end

function row = synthetic_cca_row(variant,mode,sensitivity,delay,goodput)
    row = struct('protocol',"sb_cb",'load_mode',"fixed_packet", ...
        'lambda_base',30,'lambda_effective',30,'M',1,'Tp_us',198, ...
        'best_q',0.025,'q_source',"primary_tuned", ...
        'cca_variant',variant,'cca_mode',mode,'rx_sens_dbm',sensitivity, ...
        'stable_fraction',1,'mean_delay_us',delay,'p95_delay_us',1.5*delay, ...
        'normalized_goodput_units_s',goodput,'backlog_slope_pkt_s',0, ...
        'eligible_tp',NaN,'eligible_fn',NaN,'eligible_fp',NaN,'eligible_tn',NaN);
end

function row = synthetic_topology_row(seed,delay,goodput)
    row = struct('protocol',"sf_cb",'load_mode',"fixed_packet", ...
        'lambda_base',30,'lambda_effective',30,'M',1,'Tp_us',198, ...
        'topology_seed',seed,'stable_fraction',1, ...
        'mean_delay_us',delay,'p95_delay_us',1.5*delay, ...
        'normalized_goodput_units_s',goodput,'goodput_pkt_s',goodput, ...
        'backlog_slope_pkt_s',0,'completion_ratio',1,'jain_fairness',0.95);
end

function remove_test_directory(path)
    if isfolder(path), rmdir(path,'s'); end
end
