function run_analysis_1s_batch_m()
%RUN_ANALYSIS_1S_BATCH_M Delay-vs-M analysis using M-packet request queues.
%   Runs sf_cb, sb_cb, unslotted, s7_clean and s7_busy for M=1:6.

    run_delay_m_analysis('batch_M','R9_merged_batch_M',false);
end
