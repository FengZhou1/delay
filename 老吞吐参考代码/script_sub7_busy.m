function script_sub7_busy()
    utils = sim_utils();
    [~, ~, ~, ~, ~] = utils.get_common_params();

    Q_RANGE_MLD = [0.0001:0.0001:0.001, 0.001:0.002:0.02, 0.025:0.01:0.2];
    factory = @(SYS, MMW, SUB7, ~, ~, ~) ...
        @(steps, q) proto_sub7(steps, SYS.N_MLO, SUB7.N_SLO_BUSY, q, SUB7);

    run_protocol_sweeps('sub_7G_assisted_busy', factory, true, Q_RANGE_MLD);
end
