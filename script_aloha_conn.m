function experiment = script_aloha_conn(lambda_val,sim_time_total_us,n_runs)
%SCRIPT_ALOHA_CONN Run SF-CB through the unified v2 experiment engine.
    if nargin<1, lambda_val=[]; end
    if nargin<2, sim_time_total_us=[]; end
    if nargin<3, n_runs=[]; end
    experiment=run_protocol_compat_v2('sf_cb',lambda_val,sim_time_total_us,n_runs);
end
