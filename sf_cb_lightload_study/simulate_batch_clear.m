function result = simulate_batch_clear(trace, scenario, cfg, M, q, seed)
%SIMULATE_BATCH_CLEAR Slotted connection Aloha with batch clearing.
% Reservation rules are identical to SF-CB (162.5 us conn-slot frames,
% Bernoulli(q) at every boundary).  After a successful reservation the node
% transmits, back-to-back, every packet that was in its queue when the DATA
% phase began (a snapshot; packets arriving during DATA are not appended).
% Each packet occupies one DATA frame of M * 162.5 us.  Collisions and idle
% frames waste one conn-slot, exactly as in SF-CB.

    if ~isscalar(M) || ~isfinite(M) || M < 1 || M ~= round(M)
        error('simulate_batch_clear:BadM', 'M must be an integer >= 1.');
    end
    if ~isscalar(q) || ~isfinite(q) || q <= 0 || q > 1
        error('simulate_batch_clear:BadQ', 'q must lie in (0,1].');
    end
    raw = simulate_slotted_lightload(true, trace, scenario, cfg, M, q, seed);
    is_saturation = isfield(cfg,'traffic_mode') && ...
        strcmpi(char(cfg.traffic_mode),'saturation');
    if is_saturation
        result = finalize_lightload_saturation_result(raw, cfg, ...
            'batch_clear', M, q);
    else
        result = finalize_lightload_sim_result(raw, trace, cfg, ...
            'batch_clear', M, q);
    end
end