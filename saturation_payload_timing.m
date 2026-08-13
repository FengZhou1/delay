function payload = saturation_payload_timing(cfg, M)
%SATURATION_PAYLOAD_TIMING Map a requested M to a real-timing DATA frame.
%   Uses the TXOP-model real conn_slot_us (162.5 us) for all protocols.
%   No 9-us slot quantization -- exact microsecond timing throughout.

    if ~isscalar(M) || ~isfinite(M) || M <= 0
        error('saturation_payload_timing:BadM', ...
            'Saturation M must be a finite positive scalar.');
    end

    % Use the real mmWave connection slot (162.5 us) for all protocols.
    if isfield(cfg, 'mmw_real_conn_slot_us') && ~isempty(cfg.mmw_real_conn_slot_us)
        conn_slot_us = double(cfg.mmw_real_conn_slot_us);
    else
        timing = mmw_timing_config(cfg);
        conn_slot_us = timing.CONN_SLOT_US;
    end
    nominal_us = double(M) * conn_slot_us;
    actual_us = nominal_us;

    payload = struct();
    payload.requested_M = double(M);
    payload.nominal_payload_us = nominal_us;
    payload.payload_slots = nominal_us / 9;
    payload.actual_payload_us = actual_us;
    payload.effective_M = actual_us / conn_slot_us;
    payload.quantization_error_us = 0;
    payload.rounding_rule = 'exact_real_timing';
end
