function run_analysis_1s()
%RUN_ANALYSIS_1S Delay-vs-M analysis using ready_queue TXOP admission.
%   CF protocols are fixed at M=1; the other five protocols scan M=1:6.
%   Results are merged into results_v2/R9_merged_logic1.

    run_delay_m_analysis('ready_queue','R9_merged_logic1',true);
end
