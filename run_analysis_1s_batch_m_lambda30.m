function run_analysis_1s_batch_m_lambda30()
%RUN_ANALYSIS_1S_BATCH_M_LAMBDA30 Logic-2 M sweep at lambda=30 pkt/STA/s.
%   Runs sf_cb, sb_cb, unslotted, s7_clean and s7_busy for M=1:6.
%   Results are written to results_v2/R9_merged_batch_M_lambda30/.

    override = struct();
    override.lambda_values = 30;
    run_delay_m_analysis('batch_M','R9_merged_batch_M_lambda30',false,override);
end
