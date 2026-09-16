function mat = precalc_ap_cts_tx_power_mmw(pos, phy, cts_mode, qo_peak_gain_db, taper)
%PRECALC_AP_CTS_TX_POWER_MMW AP CTS received power for each winner/STA pair.
%   mat(winner, sta) is the received CTS power at sta when the AP steers its
%   CTS toward winner.  The QO pattern is normalized so its main-lobe peak
%   equals qo_peak_gain_db; the directional mode uses the MRT AWV.

    if nargin < 4 || isempty(qo_peak_gain_db)
        qo_peak_gain_db = 0;
    end
    if nargin < 5 || isempty(taper)
        taper = [1, 3, 3, 1];
    end

    n = size(pos,1);
    mat = zeros(n,n);
    mode = lower(char(cts_mode));
    if ~ismember(mode,{'quasi_omni_physical','quasi_omni_isotropic', ...
            'directional_winner'})
        error('precalc_ap_cts_tx_power_mmw:BadMode', ...
            'Unsupported CTS mode: %s.', mode);
    end

    ang_ap_to_sta = zeros(n,1);
    d_ap = zeros(n,1);
    for i = 1:n
        delta = pos(i,:) - phy.AP_POS;
        d_ap(i) = norm(delta);
        ang_ap_to_sta(i) = mod(atan2d(delta(2),delta(1)),360);
    end

    for winner = 1:n
        theta0 = ang_ap_to_sta(winner);
        if strcmp(mode,'quasi_omni_isotropic')
            w = ones(phy.Nt,1)/sqrt(phy.Nt);   % unused for the isotropic pattern
            raw_peak_db = 0;
            peak_db = 0;
        elseif strcmp(mode,'directional_winner')
            w = build_ula_awv('mrt',theta0,phy.Nt,phy.FREQ);
            raw_peak_db = 10*log10(phy.Nt);
            peak_db = raw_peak_db;
        else
            w = build_ula_awv('qo',theta0,phy.Nt,phy.FREQ,taper);
            raw_gain = zeros(n,1);
            for sta = 1:n
                raw_gain(sta) = calculate_ula_awv_gain( ...
                    w,ang_ap_to_sta(sta),phy.Nt,phy.FREQ);
            end
            raw_peak_db = max(raw_gain);
            peak_db = qo_peak_gain_db;
        end

        for sta = 1:n
            if strcmp(mode,'quasi_omni_isotropic')
                g_ap_tx = qo_peak_gain_db;   % same gain in every direction
            else
                g_ap_tx = calculate_ula_awv_gain( ...
                    w,ang_ap_to_sta(sta),phy.Nt,phy.FREQ);
                g_ap_tx = g_ap_tx - raw_peak_db + peak_db;
            end
            pl = 20*log10(max(d_ap(sta),1e-3)) + ...
                20*log10(phy.FREQ/1e9) + 32.44;
            pwr_dbm = phy.TX_POWER_DBM + g_ap_tx - pl;
            mat(winner,sta) = 10^((pwr_dbm - 30)/10);
        end
    end
end
