function validation=validate_aloha_theory_v2(output_dir)
%VALIDATE_ALOHA_THEORY_V2 Controlled saturated SF-CB probability check.
    if nargin<1 || isempty(output_dir)
        stamp=char(datetime('now','Format','yyyyMMdd_HHmmss'));
        output_dir=fullfile(pwd,'results_v2',['aloha_theory_' stamp]);
    end
    if ~exist(output_dir,'dir'), mkdir(output_dir); end

    cfg=default_experiment_config('smoke');
    cfg.n_nodes=40;
    cfg.n_sectors=8;
    cfg.warmup_us=0;
    cfg.measure_us=3e6;
    cfg.drain_max_us=0;
    cfg.arrival_end_us=cfg.measure_us;
    cfg.sim_hard_end_us=cfg.measure_us;
    cfg.parallel=false;
    cfg.stability_require_slope=false;
    cfg.stats_sample_us=1e4;
    M=1;
    K=cfg.n_nodes;
    q=1/K;
    packets_per_node=1000;
    node_id=repelem((1:K)',packets_per_node);
    trace=make_manual_arrival_trace(zeros(size(node_id)),node_id,cfg);
    scenario=prepare_scenario_v2(cfg,cfg.topology_seed);
    reservation_us=scenario.MMW_REAL.CONN_OVERHEAD_US;
    result=simulate_aloha_v2('sf_cb',trace,scenario,cfg,M,q,91357);

    d=result.diagnostics;
    trials=d.reservation_full_frames_by_k(K+1);
    successes=d.reservation_success_frames_by_k(K+1);
    empirical_ps=successes/trials;
    theoretical_ps=K*q*(1-q)^(K-1);
    [ci_low,ci_high]=wilson_interval(successes,trials);
    probability_pass=theoretical_ps>=ci_low && theoretical_ps<=ci_high;

    completions=sort(result.packet_log.completion_us( ...
        isfinite(result.packet_log.completion_us)));
    empirical_service_cycle_us=mean(diff(completions));
    theoretical_service_cycle_us=reservation_us*M+reservation_us/theoretical_ps;
    service_relative_error=abs(empirical_service_cycle_us- ...
        theoretical_service_cycle_us)/theoretical_service_cycle_us;

    metrics=table(K,q,trials,successes,empirical_ps,theoretical_ps, ...
        ci_low,ci_high,probability_pass,empirical_service_cycle_us, ...
        theoretical_service_cycle_us,service_relative_error);
    writetable(metrics,fullfile(output_dir,'aloha_theory_validation.csv'));
    save(fullfile(output_dir,'aloha_theory_validation.mat'), ...
         'metrics','result','cfg','-v7.3');

    if ~probability_pass
        error('validate_aloha_theory_v2:ProbabilityMismatch', ...
            'Theoretical Ps is outside the empirical 95%% interval.');
    end
    if service_relative_error>0.05
        error('validate_aloha_theory_v2:ServiceMismatch', ...
            'Empirical service cycle differs from theory by more than 5%%.');
    end

    report_path=fullfile(output_dir,'Aloha理论概率验证.md');
    fid=fopen(report_path,'w','n','UTF-8');
    if fid<0, error('validate_aloha_theory_v2:Write','Cannot write report.'); end
    cleanup=onCleanup(@() fclose(fid));
    fprintf(fid,'# SF-CB 受控理论验证\n\n');
    fprintf(fid,'固定 K=%d、q=1/K=%.6f、M=%d。\n\n',K,q,M);
    fprintf(fid,'- 理论 Ps�?.8f\n- 经验 Ps�?.8f�?d/%d）\n', ...
        theoretical_ps,empirical_ps,successes,trials);
    fprintf(fid,'- Wilson 95%% CI：[%.8f, %.8f]，理论值在区间内：%d。\n', ...
        ci_low,ci_high,probability_pass);
    fprintf(fid,'- 理论服务周期 `Tp+%.0f/Ps`�?.3f us；经验相邻完成间隔：%.3f us；相对误差：%.3f%%。\n\n', ...
        reservation_us,theoretical_service_cycle_us,empirical_service_cycle_us, ...
        100*service_relative_error);
    fprintf(fid,'## Material Passport\n\n- Origin Skill: experiment-agent\n');
    fprintf(fid,'- Origin Mode: run/validate\n- Origin Date: 2026-07-22\n');
    fprintf(fid,'- Verification Status: VERIFIED\n- Version Label: aloha_theory_v2\n');
    clear cleanup;
    validation=struct('output_dir',output_dir,'metrics',metrics, ...
                      'report_path',report_path);
end

function [low,high]=wilson_interval(successes,trials)
    z=1.95996398454005;
    p=successes/trials;
    denom=1+z^2/trials;
    center=(p+z^2/(2*trials))/denom;
    half=z*sqrt(p*(1-p)/trials+z^2/(4*trials^2))/denom;
    low=max(0,center-half);
    high=min(1,center+half);
end
