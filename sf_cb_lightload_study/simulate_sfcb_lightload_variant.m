function result = simulate_sfcb_lightload_variant(protocol, trace, scenario, cfg, M, q, seed)
%SIMULATE_SFCB_LIGHTLOAD_VARIANT Thin dispatch layer for the four MAC
% variants of the light-load SF-CB study:
%   'sf_cb'       -> slotted full-coordinated connection Aloha (baseline)
%   'batch_clear' -> slotted reservation + whole-queue snapshot DATA
%   'unslotted'   -> non-slotted p-persistent ALOHA
%   'sb_cb'       -> continuous-time sensing-based connection protocol
% All timings come from protocol_timing() (RTS=14.5, SIFS=16, DIFS=34,
% CTS=14.5, conn-slot=162.5, CTS timeout=132.0 us).

    protocol = lower(char(protocol));
    switch protocol
        case 'sf_cb'
            result = simulate_sf_cb(trace, scenario, cfg, M, q, seed);
        case 'batch_clear'
            result = simulate_batch_clear(trace, scenario, cfg, M, q, seed);
        case 'unslotted'
            result = simulate_unslotted_sf_cb(trace, scenario, cfg, M, q, seed);
        case 'sb_cb'
            result = simulate_sb_cb(trace, scenario, cfg, M, q, seed);
        otherwise
            error('simulate_sfcb_lightload_variant:BadProtocol', ...
                'Unknown protocol "%s".', protocol);
    end
end