function timing = mmw_timing_config(cfg)
%MMW_TIMING_CONFIG Return the integer-slot mmWave timing configuration.
% Protocol state machines use slot counts as the source of truth.  Values
% in microseconds are derived here and are therefore always integer
% multiples of one mmWave slot.

    if nargin < 1 || isempty(cfg)
        cfg = struct();
    end

    timing.SLOT_US = scalar_field(cfg, 'mmw_slot_us', 9);
    timing.DATA_RATE_BPS = scalar_field(cfg, 'mmw_data_rate_bps', 2.7e9);
    timing.CONTROL_RATE_BPS = scalar_field(cfg, 'mmw_control_rate_bps', 260e6);
    timing.PHY_HEADER_SLOTS = scalar_field(cfg, 'mmw_phy_header_slots', 2);
    timing.SIFS_SLOTS = scalar_field(cfg, 'mmw_sifs_slots', 2);
    timing.DIFS_SLOTS = scalar_field(cfg, 'mmw_difs_slots', 4);
    timing.RTS_BITS = scalar_field(cfg, 'mmw_rts_bits', 160);
    timing.CTS_BITS = scalar_field(cfg, 'mmw_cts_bits', 112);
    timing.RTS_SLOTS = scalar_field(cfg, 'mmw_rts_slots', 2);
    timing.CTS_SLOTS = scalar_field(cfg, 'mmw_cts_slots', 2);
    timing.N_SECTORS = scalar_field(cfg, 'n_sectors', 8);

    positive_integer_fields = {'SLOT_US','PHY_HEADER_SLOTS','SIFS_SLOTS', ...
        'DIFS_SLOTS','RTS_BITS','CTS_BITS','RTS_SLOTS','CTS_SLOTS', ...
        'N_SECTORS'};
    for i = 1:numel(positive_integer_fields)
        name = positive_integer_fields{i};
        value = timing.(name);
        if ~isscalar(value) || ~isfinite(value) || value < 1 || ...
                value ~= round(value)
            error('mmw_timing_config:BadIntegerField', ...
                '%s must be a positive integer.', name);
        end
    end
    if ~isscalar(timing.DATA_RATE_BPS) || ...
            ~isfinite(timing.DATA_RATE_BPS) || timing.DATA_RATE_BPS <= 0 || ...
            ~isscalar(timing.CONTROL_RATE_BPS) || ...
            ~isfinite(timing.CONTROL_RATE_BPS) || ...
            timing.CONTROL_RATE_BPS <= 0
        error('mmw_timing_config:BadRate', ...
            'The mmWave data and control rates must be positive scalars.');
    end
    if timing.DIFS_SLOTS ~= timing.SIFS_SLOTS + 2
        error('mmw_timing_config:BadDIFS', ...
            'DIFS must equal SIFS plus two mmWave slots.');
    end

    timing.PHY_HEADER_US = timing.PHY_HEADER_SLOTS * timing.SLOT_US;
    timing.SIFS_US = timing.SIFS_SLOTS * timing.SLOT_US;
    timing.DIFS_US = timing.DIFS_SLOTS * timing.SLOT_US;
    timing.RTS_US = timing.RTS_SLOTS * timing.SLOT_US;
    timing.CTS_US = timing.CTS_SLOTS * timing.SLOT_US;
    timing.CONN_SLOT_SLOTS = timing.RTS_SLOTS + timing.SIFS_SLOTS + ...
        timing.N_SECTORS * timing.CTS_SLOTS + timing.SIFS_SLOTS;
    % Legacy integer-slot reference (22 slots x 9 us = 198 us).  Saturation
    % throughput must use scenario.MMW_REAL.CONN_OVERHEAD_US (162.5 us)
    % everywhere; do NOT use CONN_SLOT_US for saturation frame length.
    timing.CONN_SLOT_US = timing.CONN_SLOT_SLOTS * timing.SLOT_US;
end

function value = scalar_field(cfg, name, fallback)
    value = fallback;
    if isstruct(cfg) && isfield(cfg, name) && ~isempty(cfg.(name))
        value = double(cfg.(name));
    end
end
