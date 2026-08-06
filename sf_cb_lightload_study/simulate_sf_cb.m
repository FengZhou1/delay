function result = simulate_sf_cb(trace, scenario, cfg, M, q, seed)
%SIMULATE_SF_CB Slotted full-coordinated connection Aloha (baseline).
% Time is divided into 164.1 us conn-slot frames.  At every frame boundary
% each backlogged node makes an independent Bernoulli(q) decision.  A
% singleton reserves the channel (RTS + SIFS + CTS sweep + SIFS) and then
% sends one DATA frame of M * 164.1 us.  Collisions and idle frames each
% waste one conn-slot.  Because transmitters are restricted to slot
% boundaries, a successful reservation always yields a successful CTS/DATA
% transfer, so no SINR judgment is needed (simplified model).

    if ~isscalar(M) || ~isfinite(M) || M < 1 || M ~= round(M)
        error('simulate_sf_cb:BadM', 'M must be an integer >= 1.');
    end
    if ~isscalar(q) || ~isfinite(q) || q <= 0 || q > 1
        error('simulate_sf_cb:BadQ', 'q must lie in (0,1].');
    end
    raw = simulate_slotted_lightload(false, trace, scenario, cfg, M, q, seed);
    is_saturation = isfield(cfg,'traffic_mode') && ...
        strcmpi(char(cfg.traffic_mode),'saturation');
    if is_saturation
        result = finalize_lightload_saturation_result(raw, cfg, 'sf_cb', M, q);
    else
        result = finalize_lightload_sim_result(raw, trace, cfg, 'sf_cb', M, q);
    end
end