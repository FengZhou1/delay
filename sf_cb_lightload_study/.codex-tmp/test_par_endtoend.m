
function test_par_endtoend()
addpath('..');
addpath(pwd);
cfg = default_lightload_sfcb_config('smoke','delay');
scenario = prepare_scenario_v2(cfg, cfg.topology_seed);
trace = generate_arrival_trace(1, cfg, cfg.traffic_seed_base);
qgrid = [0.1 0.5 1];
t0 = tic;
out = zeros(numel(qgrid),1);
parfor i = 1:numel(qgrid)
    r = simulate_sfcb_lightload_variant('unslotted', trace, scenario, cfg, 1, qgrid(i), 7);
    out(i) = r.summary.mean_delay_us;
end
fprintf('parfor end-to-end OK in %.2f s: %s\n', toc(t0), mat2str(out(:).', 6));
end
