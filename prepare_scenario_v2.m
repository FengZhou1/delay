function scenario = prepare_scenario_v2(cfg, topology_seed)
%PREPARE_SCENARIO_V2 Build one reusable topology and physical-layer cache.

    if nargin < 2 || isempty(topology_seed)
        topology_seed = cfg.topology_seed;
    end
    utils = sim_utils();
    [SYS, PHY, MMW, SUB7, ~] = utils.get_common_params(cfg);
    SYS.N_MLO = cfg.n_nodes;
    SYS.N_SECTORS = cfg.n_sectors;

    stream_state = rng;
    cleanup = onCleanup(@() rng(stream_state));
    rng(topology_seed, 'twister');
    [node_pos, angles, sectors] = utils.generate_topology( ...
        SYS.N_MLO, PHY.AP_POS, SYS.N_SECTORS);
    clear cleanup;

    PHY.RX_SENS_DBM = cfg.rx_sens_dbm;
    PHY.NOISE_DBM = cfg.noise_dbm;
    PHY.DATA_SINR_TH_DB = cfg.data_sinr_th_db;
    PHY.CTS_SINR_TH_DB = cfg.cts_sinr_th_db;
    PHY.CTRL_SINR_TH_DB = cfg.cts_sinr_th_db;
    PHY.Int_Matrix = utils.precalc_interference_mmw(node_pos, angles, PHY);
    PHY.AP_Rx_Matrix = utils.precalc_ap_rx_power_mmw(node_pos, PHY);
    PHY.AP_Sector_Tx_Matrix = utils.precalc_ap_sector_tx_power_mmw( ...
        node_pos, PHY, SYS.N_SECTORS);

    MMW.DIFS_US = MMW.DIFS * MMW.SLOT_TIME_US;
    MMW.SIFS_US = MMW.SIFS * MMW.SLOT_TIME_US;
    MMW.RTS_US = MMW.N_RTS * MMW.SLOT_TIME_US;
    MMW.CTS_US = MMW.N_CTS * MMW.SLOT_TIME_US;
    MMW.CONN_OVERHEAD_US = MMW.conn_overhead * MMW.SLOT_TIME_US;

    SUB7.DIFS_US = SUB7.DIFS * SUB7.SLOT_TIME_US;
    SUB7.SIFS_US = SUB7.SIFS * SUB7.SLOT_TIME_US;
    SUB7.ICF_US = SUB7.ICF * SUB7.SLOT_TIME_US;
    SUB7.ICR_US = SUB7.ICR * SUB7.SLOT_TIME_US;
    SUB7.SLO_RTS_US = SUB7.SLO_RTS_LEN * SUB7.SLOT_TIME_US;
    SUB7.SLO_CTS_US = SUB7.SLO_CTS_LEN * SUB7.SLOT_TIME_US;

    scenario = struct('SYS',SYS, 'PHY',PHY, 'MMW',MMW, 'SUB7',SUB7, ...
        'node_pos',node_pos, 'angles',angles, 'sectors',sectors, ...
        'topology_seed',topology_seed);
end
