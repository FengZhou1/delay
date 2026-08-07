function result = simulate_unslotted_sf_cb(trace, scenario, cfg, M, q, seed)
%SIMULATE_UNSLOTTED_SF_CB Non-slotted ALOHA variant with exponential
% retry delay.  Whenever the HOL queue is non-empty the node draws
% T ~ Exp(lambda) with lambda = -ln(1-q)/9 per us, waits, then transmits
% (no DIFS, no carrier sensing, no 9 us boundary alignment).  This is the
% continuous equivalent of Bernoulli(q) at 9 us slot boundaries.  A single
% packet therefore attempts immediately iff the drawn delay is ~0.
% Transmissions use real durations: RTS=14.5 us, SIFS=16 us,
% CTS sweep=117.6 us, SIFS=16 us, DATA=M*164.1 us.  Overlapping RTSs
% collide; a colliding station waits the CTS timeout (SIFS + CTS sweep =
% 133.6 us) and then draws a fresh exponential delay.  CTS and DATA
% reception use the full directional SINR model, including NAV from
% decoded CTS, half-duplex CTS loss and late-RTS interference during the
% DATA phase.

    if ~isscalar(M) || ~isfinite(M) || M < 1 || M ~= round(M)
        error('simulate_unslotted_sf_cb:BadM', ...
            'M must be an integer >= 1.');
    end
    if ~isscalar(q) || ~isfinite(q) || q <= 0 || q > 1
        error('simulate_unslotted_sf_cb:BadQ', 'q must lie in (0,1].');
    end
    raw = simulate_lightload_continuous('unslotted', trace, scenario, ...
        cfg, M, q, seed);
    is_saturation = isfield(cfg,'traffic_mode') && ...
        strcmpi(char(cfg.traffic_mode),'saturation');
    if is_saturation
        result = finalize_lightload_saturation_result(raw, cfg, ...
            'unslotted', M, q);
    else
        result = finalize_lightload_sim_result(raw, trace, cfg, ...
            'unslotted', M, q);
    end
end