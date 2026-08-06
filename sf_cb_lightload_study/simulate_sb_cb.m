function result = simulate_sb_cb(trace, scenario, cfg, M, q, seed)
%SIMULATE_SB_CB Modified sensing-based connection protocol (continuous time).
% The HOL station senses the channel at 9 us tick boundaries and, after a
% continuous idle of DIFS=34 us, immediately draws Bernoulli(q) and starts a
% real 14.5 us RTS (transmissions are NOT aligned to 9 us boundaries).
% A busy channel resets the DIFS counter.  RTS collisions use the classic
% overlap model; after a collision the station waits the CTS timeout
% (SIFS + CTS sweep = 133.6 us) and restarts DIFS sensing.  CTS and DATA
% use the full directional SINR model (CTS 6 dB, DATA 21 dB), with NAV from
% decoded CTS, half-duplex CTS loss and late-RTS interference during DATA.

    if ~isscalar(M) || ~isfinite(M) || M < 1 || M ~= round(M)
        error('simulate_sb_cb:BadM', 'M must be an integer >= 1.');
    end
    if ~isscalar(q) || ~isfinite(q) || q <= 0 || q > 1
        error('simulate_sb_cb:BadQ', 'q must lie in (0,1].');
    end
    raw = simulate_lightload_continuous('sb_cb', trace, scenario, ...
        cfg, M, q, seed);
    is_saturation = isfield(cfg,'traffic_mode') && ...
        strcmpi(char(cfg.traffic_mode),'saturation');
    if is_saturation
        result = finalize_lightload_saturation_result(raw, cfg, ...
            'sb_cb', M, q);
    else
        result = finalize_lightload_sim_result(raw, trace, cfg, ...
            'sb_cb', M, q);
    end
end