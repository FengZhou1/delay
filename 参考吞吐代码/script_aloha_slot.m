function script_aloha_slot()
    utils = sim_utils();
    [SYS_BASE, ~, ~, ~, ~] = utils.get_common_params();

    N_MLO = SYS_BASE.N_SECTORS * 5;
    Q_RANGE = 1 / N_MLO;

    factory = @(SYS, MMW, ~, ~, ~, ~) ...
        @(steps, q) proto_aloha_slot(steps, SYS.N_MLO, q, MMW);

    run_protocol_sweeps('sensing_free_connection_free', factory, false, Q_RANGE);
end
