function result = simulate_unslotted_sf_cb(trace, scenario, cfg, M, q, seed)
%SIMULATE_UNSLOTTED_SF_CB Non-slotted p-persistent ALOHA (event-driven).
%   Wrapper around simulate_unslotted_engine with mode='unslotted'.
%   Output is compatible with finalize_sim_result.m / finalize_saturation_result.m.

    if ~isscalar(M) || ~isfinite(M) || M <= 0
        error('simulate_unslotted_sf_cb:BadM', ...
            'M must be a positive scalar.');
    end
    if ~isscalar(q) || ~isfinite(q) || q <= 0 || q > 1
        error('simulate_unslotted_sf_cb:BadQ', 'q must lie in (0,1].');
    end
    raw = simulate_unslotted_engine('unslotted', trace, scenario, ...
        cfg, M, q, seed);
    is_saturation = isfield(cfg,'traffic_mode') && ...
        strcmpi(char(cfg.traffic_mode),'saturation');
    if is_saturation
        result = finalize_saturation_result(raw, cfg, 'unslotted', M, q);
    else
        result = finalize_sim_result(raw, trace, cfg, 'unslotted', M, q);
    end
end
