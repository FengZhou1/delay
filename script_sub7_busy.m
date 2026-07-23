function experiment = script_sub7_busy(lambda_val,sim_time_total_us,n_runs)
%SCRIPT_SUB7_BUSY Run busy S7-AS through the unified v2 engine.
    if nargin<1, lambda_val=[]; end
    if nargin<2, sim_time_total_us=[]; end
    if nargin<3, n_runs=[]; end
    experiment=run_protocol_compat_v2('s7_busy',lambda_val,sim_time_total_us,n_runs);
end
