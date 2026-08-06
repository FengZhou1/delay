function timing = protocol_timing(cfg)
%PROTOCOL_TIMING Real-time (us) protocol timing per plan document section 2.
% The new timings (RTS=14.5, SIFS=16, DIFS=34, CTS=14.7) are NOT integer
% multiples of the 9 us mmWave slot, so the shared tick-based v2 simulators
% cannot be reused.  This function is the single source of truth inside the
% light-load study and intentionally does not touch mmw_timing_config.m.
% Derived values (n_sectors=8): CTS sweep = 117.6 us, conn-slot = 164.1 us,
% CTS timeout = 133.6 us, DATA = M * conn-slot.

    if nargin < 1 || isempty(cfg)
        cfg = struct();
    end
    n_sectors = 8;
    if isfield(cfg,'n_sectors') && ~isempty(cfg.n_sectors)
        n_sectors = double(cfg.n_sectors);
    end

    timing.SLOT_US = 9;                        % sensing / arrival granularity
    timing.RTS_US = 14.5;
    timing.SIFS_US = 16;
    timing.DIFS_US = 34;
    timing.CTS_US = 14.7;
    timing.N_SECTORS = n_sectors;
    timing.CTS_SWEEP_US = n_sectors * timing.CTS_US;               % 117.6
    timing.CONN_SLOT_US = timing.RTS_US + timing.SIFS_US + ...
        timing.CTS_SWEEP_US + timing.SIFS_US;                     % 164.1
    timing.CTS_TIMEOUT_US = timing.SIFS_US + timing.CTS_SWEEP_US; % 133.6
    timing.DIFS_TICKS = ceil(timing.DIFS_US / timing.SLOT_US);    % 4
    if isfield(cfg,'timing_override') && ~isempty(cfg.timing_override)
        t = cfg.timing_override;
        timing.RTS_US = double(t.rts_us);
        timing.SIFS_US = double(t.sifs_us);
        timing.DIFS_US = double(t.difs_us);
        timing.CTS_US = double(t.cts_us);
        timing.CTS_SWEEP_US = n_sectors * timing.CTS_US;
        timing.CONN_SLOT_US = timing.RTS_US + timing.SIFS_US + ...
            timing.CTS_SWEEP_US + timing.SIFS_US;
        timing.CTS_TIMEOUT_US = timing.SIFS_US + timing.CTS_SWEEP_US;
        timing.DIFS_TICKS = ceil(timing.DIFS_US / timing.SLOT_US);
    end
end
