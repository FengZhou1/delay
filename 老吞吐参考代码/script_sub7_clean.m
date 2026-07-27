function script_sub7_clean()
    utils = sim_utils();
    [~, ~, ~, ~, ~] = utils.get_common_params();

    Q_RANGE = [0.001:0.002:0.02, 0.025:0.01:0.15, 0.2:0.2:1.0];

    factory = @(SYS, MMW, SUB7, ~, ~, ~) ...
        @(steps, q) proto_sub7(steps, SYS.N_MLO, SUB7.N_SLO_CLEAN, q, SUB7);

    run_protocol_sweeps('sub_7G_assisted_clean', factory, true, Q_RANGE);
end
