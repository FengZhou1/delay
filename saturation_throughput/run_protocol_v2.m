function result = run_protocol_v2(protocol, trace, scenario, cfg, M, q, seed)
%RUN_PROTOCOL_V2 Dispatch one condition to a v2 protocol simulator.
    switch protocol
        case 'sf_cf'
            result = simulate_aloha_v2(protocol, trace, scenario, cfg, M, q, seed);
        case 'sf_cb'
            cts_mode = 'sector_sweep';
            if isfield(cfg,'cts_mode') && ~isempty(cfg.cts_mode)
                cts_mode = lower(char(cfg.cts_mode));
            end
            if strcmp(cts_mode,'sector_sweep')
                result = simulate_aloha_v2(protocol, trace, scenario, cfg, M, q, seed);
            else
                result = simulate_sf_cb_cts_v2(trace, scenario, cfg, M, q, seed);
            end
        case 'sb_cf'
            result = simulate_sb_cf_v2(trace, scenario, cfg, M, q, seed);
        case 'sb_cb'
            result = simulate_sb_cb_v2(trace, scenario, cfg, M, q, seed);
        case 'unslotted'
            result = simulate_unslotted_sf_cb(trace, scenario, cfg, M, q, seed);
        case {'s7_clean','s7_busy'}
            result = simulate_s7_v2(protocol, trace, scenario, cfg, M, q, seed);
        otherwise
            error('run_protocol_v2:BadProtocol', 'Unknown protocol: %s', protocol);
    end
end
