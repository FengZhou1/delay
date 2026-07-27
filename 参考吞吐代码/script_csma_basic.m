function script_csma_basic()
    utils = sim_utils();
    [~, ~, ~, ~, ~] = utils.get_common_params();

    Q_RANGE = [0.00001:0.00002:0.001, 0.001:0.002:0.03];
    factory = @(SYS, MMW, ~, PHY, ~, ~) ...
        @(steps, q) proto_csma_basic(steps, SYS.N_MLO, q, MMW, PHY);

    run_protocol_sweeps('sensing_based_connection_free', factory, false, Q_RANGE);
end
