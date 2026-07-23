function experiment = script_csma_rts(lambda_val,sim_time_total_us,n_runs)
%SCRIPT_CSMA_RTS Run SB-CB through the unified v2 experiment engine.
    if nargin<1, lambda_val=[]; end
    if nargin<2, sim_time_total_us=[]; end
    if nargin<3, n_runs=[]; end
    experiment=run_protocol_compat_v2('sb_cb',lambda_val,sim_time_total_us,n_runs);
end
