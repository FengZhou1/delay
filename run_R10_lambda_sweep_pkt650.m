function run_R10_lambda_sweep_pkt650()
%RUN_R10_LAMBDA_SWEEP_PKT650 R10 delay sweep with a 650 us data packet.
%   Same protocol/M/load matrix as R10, but each data packet lasts 650 us.
%   Reservation/control timing is unchanged:
%   RTS 14.5 + SIFS 16 + 8-sector CTS 116 + SIFS 16 = 162.5 us.

    root = fullfile(pwd,'R10_results');
    raw_root = fullfile(root,'raw_pkt650');
    out_dir = fullfile(root,'lambda_sweep_pkt650');
    if ~isfolder(root), mkdir(root); end
    if ~isfolder(raw_root), mkdir(raw_root); end
    if ~isfolder(out_dir), mkdir(out_dir); end

    n_sta = 40;
    pkt_us = 650;
    loads = [0.1, 0.2, 0.3, 0.5, 0.6];   % keep in sync with run_R10_cts_mode
    lambda_values = loads / (n_sta * pkt_us * 1e-6);

    cb_protocols = {'sf_cb','sb_cb','unslotted','s7_clean','s7_busy'};
    cf_protocols = {'sf_cf','sb_cf'};

    fprintf('===== R10 pkt650 CB protocols (M=1,20) =====\n');
    cfg_cb = make_cfg(raw_root,'ready_queue',cb_protocols,[1 20], ...
        lambda_values,pkt_us);
    conn_slot_us = double(cfg_cb.mmw_real_conn_slot_us);
    exp_cb = run_experiment(cfg_cb);

    fprintf('===== R10 pkt650 CF protocols (M=1) =====\n');
    cfg_cf = make_cfg(raw_root,'ready_queue',cf_protocols,1, ...
        lambda_values,pkt_us);
    exp_cf = run_experiment(cfg_cf);

    s_cb = readtable(fullfile(exp_cb.output_dir,'summary.csv'), ...
        'VariableNamingRule','preserve');
    s_cf = readtable(fullfile(exp_cf.output_dir,'summary.csv'), ...
        'VariableNamingRule','preserve');
    s_cb.total_load = double(s_cb.lambda_base) * n_sta * pkt_us * 1e-6;
    s_cf.total_load = double(s_cf.lambda_base) * n_sta * pkt_us * 1e-6;
    merged = [s_cb; s_cf];
    merged.packet_duration_us = repmat(pkt_us,height(merged),1);
    merged.conn_slot_us = repmat(conn_slot_us,height(merged),1);
    writetable(merged, fullfile(out_dir,'summary.csv'));

    plot_R10_lambda_results(out_dir,'R10 pkt=650us');
    write_readme(out_dir,loads,pkt_us,conn_slot_us);
    fprintf('\n===== R10 pkt650 ALL DONE =====\n');
    fprintf('Merged summary: %s\n', fullfile(out_dir,'summary.csv'));
end

function cfg = make_cfg(raw_root, txop_mode, protocols, M_values, ...
                        lambda_values,pkt_us)
    cfg = default_experiment_config('analysis');
    cfg.txop_mode = txop_mode;
    cfg.protocols = protocols;
    cfg.M_values = M_values;
    cfg.lambda_values = lambda_values;
    cfg.load_modes = {'fixed_packet'};
    cfg.mmw_data_slot_us = pkt_us;
    cfg.results_root = raw_root;
    cfg.resume = true;
    cfg.run_preflight_tests = false;
    cfg.n_eval_runs = 3;
    cfg.condition_timeout_s = 1800;
    cfg.n_workers = 2;
    cfg.q_multi_basin_tuning = true;
    qgrid = build_piecewise_q_grid(NaN);
    cfg.q_coarse = qgrid;
    cfg.protocol_q_grids_enabled = true;
    all_protocols = {'sf_cf','sf_cb','sb_cf','sb_cb', ...
        's7_clean','s7_busy','unslotted'};
    for p = 1:numel(all_protocols)
        cfg.protocol_q_grids.(all_protocols{p}) = qgrid;
    end
    cfg.stability_rate_tolerance = 0.05;
    cfg.stability_censor_tolerance = 0.01;
    cfg.stability_slope_fraction = 0.05;
    cfg.stability_require_slope = true;
end

function write_readme(out_dir,loads,pkt_us,conn_slot_us)
    path = fullfile(out_dir,'README.md');
    fid = fopen(path,'w');
    if fid < 0, return; end
    cleanup = onCleanup(@() fclose(fid));
    fprintf(fid,'# R10 delay sweep with packet duration = %g us\n\n',pkt_us);
    fprintf(fid,'- Packet duration (data airtime per packet): %g us\n',pkt_us);
    fprintf(fid,'- Reservation/conn-slot unchanged: %g us\n',conn_slot_us);
    fprintf(fid,'- TXOP: Real TXOP = min(queue, M); CF M=1, CB M=1/20\n');
    fprintf(fid,'- Total offered loads: %s\n',mat2str(loads));
    fprintf(fid,'- lambda = load / (40 x %g us)\n',pkt_us);
    fprintf(fid,'- Mean delay, access delay and queue delay are plotted with a log y axis.\n');
    fprintf(fid,'- Hollow markers: conditions that could not find a stable q.\n');
end
