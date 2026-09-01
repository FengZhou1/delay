function payload = saturation_payload_timing(cfg, M)
%SATURATION_PAYLOAD_TIMING Map a requested M to an integer-slot DATA frame.
%   Fractional M is a saturation-study axis only.  The requested payload
%   duration M*CONN_SLOT_US is quantized to the nearest mmWave slot, with a
%   minimum of one slot, matching the legacy saturation sweep's N_DATA
%   definition.  Delay experiments continue to require integer M.

    if ~isscalar(M) || ~isfinite(M) || M <= 0
        error('saturation_payload_timing:BadM', ...
            'Saturation M must be a finite positive scalar.');
    end

    % sf_cf / sb_cf / s7 still run on the legacy 9-us integer-slot grid, so
    % the saturation payload stays quantized to the legacy CONN_SLOT_US.
    % sf_cb / sb_cb compute their exact 162.5-us payloads inside their own
    % event-driven engines and do not call this helper for Tp.
    timing = mmw_timing_config(cfg);
    nominal_us = double(M) * timing.CONN_SLOT_US;
    payload_slots = max(1, round(nominal_us / timing.SLOT_US));
    actual_us = payload_slots * timing.SLOT_US;

    payload = struct();
    payload.requested_M = double(M);
    payload.nominal_payload_us = nominal_us;
    payload.payload_slots = payload_slots;
    payload.actual_payload_us = actual_us;
    payload.effective_M = actual_us / timing.CONN_SLOT_US;
    payload.quantization_error_us = actual_us - nominal_us;
    payload.rounding_rule = 'nearest_mmw_slot_minimum_one';
end
