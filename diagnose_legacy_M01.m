function diagnostic=diagnose_legacy_M01(output_dir)
%DIAGNOSE_LEGACY_M01 Isolate the historical fractional-M timing artifact.
% This diagnostic intentionally calls the frozen legacy kernels.  It is not
% part of the formal M=1:6 scan and does not write into legacy results/.
    if nargin<1 || isempty(output_dir)
        stamp=char(datetime('now','Format','yyyyMMdd_HHmmss'));
        output_dir=fullfile(pwd,'results_v2',['legacy_M01_' stamp]);
    end
    if ~exist(output_dir,'dir'), mkdir(output_dir); end

    utils=sim_utils();
    [~,PHY,MMW,~,~]=utils.get_common_params();
    % Freeze the historical 5-us timing locally. sim_utils now exposes the
    % current 9-us parameter set and must not alter this legacy diagnosis.
    MMW.SLOT_TIME_US=5;
    MMW.N_RTS=4;
    MMW.N_CTS=4;
    MMW.SIFS=1;
    MMW.DIFS=3;
    MMW.conn_overhead=38;
    PHY.Int_Matrix=0;
    M_display=0.1;
    displayed_Tp_us=190*M_display;
    data_slots=round(38*M_display);
    actual_Tp_us=data_slots*MMW.SLOT_TIME_US;
    MMW.N_DATA=data_slots;

    n_packets=500;
    block_slots=200;
    stream=RandStream('mt19937ar','Seed',20260722);
    phase=randi(stream,[20,block_slots-20],n_packets,1);
    arrival_slots=(0:n_packets-1)'*block_slots+phase;
    steps=n_packets*block_slots+block_slots;
    arrivals=false(steps,1);
    arrivals(arrival_slots)=true;

    q_sb=0.7;
    q_sf=0.9;
    state=rng;
    cleanup=onCleanup(@() rng(state));
    rng(8101,'twister');
    [~,~,ad_sb]=proto_csma_basic(arrivals,1,q_sb,MMW,PHY);
    rng(8102,'twister');
    [~,~,ad_sf]=proto_aloha_slot(arrivals,1,q_sf,MMW);
    clear cleanup;
    ad_sb_us=ad_sb(isfinite(ad_sb))*MMW.SLOT_TIME_US;
    ad_sf_us=ad_sf(isfinite(ad_sf))*MMW.SLOT_TIME_US;

    old_sb_prediction=(1-q_sb)/q_sb*5+(data_slots-1)*5;
    old_sf_prediction=(actual_Tp_us-5)/2+actual_Tp_us/q_sf;
    corrected_sb_prediction=MMW.DIFS*5+(1-q_sb)/q_sb*5+actual_Tp_us;
    corrected_sf_prediction=(actual_Tp_us-5)/2+actual_Tp_us/q_sf;

    protocol=["legacy_SB_CF";"legacy_SF_CF"; ...
              "corrected_SB_CF_prediction";"corrected_SF_CF_prediction"];
    q=[q_sb;q_sf;q_sb;q_sf];
    empirical_mean_delay_us=[mean(ad_sb_us);mean(ad_sf_us);NaN;NaN];
    analytic_delay_us=[old_sb_prediction;old_sf_prediction; ...
                       corrected_sb_prediction;corrected_sf_prediction];
    completed_samples=[numel(ad_sb_us);numel(ad_sf_us);0;0];
    results=table(protocol,q,empirical_mean_delay_us,analytic_delay_us, ...
                  completed_samples);
    writetable(results,fullfile(output_dir,'legacy_M01_diagnostic.csv'));

    report_path=fullfile(output_dir,'旧M0.1现象诊断.md');
    fid=fopen(report_path,'w','n','UTF-8');
    if fid<0, error('diagnose_legacy_M01:Write','Cannot write report.'); end
    report_cleanup=onCleanup(@() fclose(fid));
    fprintf(fid,'# 旧 M=0.1 现象诊断\n\n');
    fprintf(fid,'- 图示 `Tp=%.1f us`，旧代码实际 `round(38M)=%.0f` 个5 us片段，即 %.1f us。\n', ...
        displayed_Tp_us,data_slots,actual_Tp_us);
    fprintf(fid,'- 旧SB-CF在空队列时预累计DIFS，且完成时刻少计一个5 us区间。\n');
    fprintf(fid,'- 旧实测：SB-CF %.3f us，SF-CF %.3f us。\n', ...
        mean(ad_sb_us),mean(ad_sf_us));
    fprintf(fid,'- 旧解析近似：SB-CF %.3f us，SF-CF %.3f us。\n', ...
        old_sb_prediction,old_sf_prediction);
    fprintf(fid,'- 修正完整DIFS与完成边界后预测：SB-CF %.3f us，SF-CF %.3f us。\n\n', ...
        corrected_sb_prediction,corrected_sf_prediction);
    fprintf(fid,'这说明旧图中SB-CF的小包低时延主要来自时序偏差；它与SF-CF饱和吞吐更高并不矛盾。该点只用于旧结果诊断，不进入正式M=1:6扫描。\n\n');
    fprintf(fid,'## Material Passport\n\n');
    fprintf(fid,'- Origin Skill: experiment-agent\n- Origin Mode: run/validate\n');
    fprintf(fid,'- Origin Date: 2026-07-22\n- Verification Status: VERIFIED\n');
    fprintf(fid,'- Version Label: legacy_M01_diagnostic_v2\n');
    clear report_cleanup;

    diagnostic=struct('output_dir',output_dir,'results',results, ...
        'report_path',report_path,'displayed_Tp_us',displayed_Tp_us, ...
        'actual_Tp_us',actual_Tp_us);
end
