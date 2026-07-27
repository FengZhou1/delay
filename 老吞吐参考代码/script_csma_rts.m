function script_csma_rts()
    utils = sim_utils();
    [~, ~, ~, ~, ~] = utils.get_common_params();

    Q_RANGE = [0.00001:0.00002:0.001, 0.001:0.002:0.01];
    factory = @(SYS, MMW, ~, PHY, sectors, n_sect) ...
        @(steps, q) proto_csma_rts(steps, SYS.N_MLO, q, MMW, PHY, sectors, n_sect);

    run_protocol_sweeps('sensing_based_connection_based', factory, false, Q_RANGE);
end
