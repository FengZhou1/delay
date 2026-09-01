function run_analysis_1s_batch_m_lambda50()
%RUN_ANALYSIS_1S_BATCH_M_LAMBDA50 Logic-2 M sweep at lambda=50 pkt/STA/s.

    override = struct();
    override.lambda_values = 50;
    run_delay_m_analysis('batch_M','R9_merged_batch_M_lambda50',false,override);
end
