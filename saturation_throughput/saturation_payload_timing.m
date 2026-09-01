function payload = saturation_payload_timing(cfg, M)
%SATURATION_PAYLOAD_TIMING Map a requested M to an integer-slot DATA frame.
%   All saturation protocols use the exact real-time connection slot
%   MMW_REAL.CONN_OVERHEAD_US (162.5 us), so sf_cf/sb_cf/s7 are consistent
%   with sf_cb/sb_cb/unslotted.  The requested payload duration is exactly
%   M*162.5 us; payload_slots is only a record of Tp/SLOT_US and may be
%   fractional.  Delay experiments continue to require integer M.

    if ~isscalar(M) || ~isfinite(M) || M <= 0
        error('saturation_payload_timing:BadM', ...
            'Saturation M must be a finite positive scalar.');
    end

    conn_us = real_conn_slot_us(cfg);
    timing = mmw_timing_config(cfg);
    actual_us = double(M) * conn_us;
    payload_slots = actual_us / timing.SLOT_US;

    payload = struct();
    payload.requested_M = double(M);
    payload.nominal_payload_us = actual_us;
    payload.payload_slots = payload_slots;
    payload.actual_payload_us = actual_us;
    payload.effective_M = double(M);
    payload.quantization_error_us = 0;
    payload.rounding_rule = 'exact_162p5_conn_slot';
end

function value = real_conn_slot_us(cfg)
    if isfield(cfg,'mmw_real_conn_slot_us') && ~isempty(cfg.mmw_real_conn_slot_us)
        value = double(cfg.mmw_real_conn_slot_us);
    else
        value = 14.5 + 16 + 8*14.5 + 16;   % 162.5 us
    end
end
