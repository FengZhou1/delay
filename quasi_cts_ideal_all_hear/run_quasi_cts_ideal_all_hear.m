function run_quasi_cts_ideal_all_hear()
%RUN_QUASI_CTS_IDEAL_ALL_HEAR Quasi-omni CTS study for affected protocols.
%   This folder contains local overrides for SB-CB and the shared unslotted
%   engine.  The original delay-folder code is not modified.

    this_dir = fileparts(mfilename('fullpath'));
    project_root = fileparts(this_dir);
    old_dir = cd(this_dir);
    cleanup = onCleanup(@() cd(old_dir));
    addpath(project_root);

    out_root = fullfile(project_root,'R10_results', ...
        'quasi_cts_ideal_all_hear');
    raw_root = fullfile(out_root,'raw');
    fig_dir = fullfile(out_root,'figures');
    if ~isfolder(out_root), mkdir(out_root); end
    if ~isfolder(raw_root), mkdir(raw_root); end
    if ~isfolder(fig_dir), mkdir(fig_dir); end

    loads = [0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.8];
    packet_durations_us = [162.5, 650];
    affected_protocols = {'sf_cb','sb_cb','unslotted'};
    reference_protocols = {'sf_cf','sb_cf','s7_clean','s7_busy'};

    for ip = 1:numel(packet_durations_us)
        pkt_us = packet_durations_us(ip);
        fprintf('\n===== Quasi-omni CTS ideal all-hear, pkt=%.1f us =====\n', ...
            pkt_us);

        cfg = make_quasi_cfg(raw_root,pkt_us,loads,affected_protocols);
        experiment = run_experiment(cfg);

        affected = readtable(fullfile(experiment.output_dir,'summary.csv'), ...
            'VariableNamingRule','preserve');
        affected = attach_load_metadata(affected,cfg,pkt_us, ...
            "quasi_omni_ideal_all_hear");

        reference_path = reference_summary_path(project_root,pkt_us);
        reference = readtable(reference_path,'VariableNamingRule','preserve');
        reference = reference(ismember(string(reference.protocol), ...
            string(reference_protocols)),:);
        if ~ismember('total_load',reference.Properties.VariableNames)
            reference.total_load = double(reference.lambda_base) * ...
                cfg.n_nodes * pkt_us * 1e-6;
        end
        reference.packet_duration_us = repmat(pkt_us,height(reference),1);
        reference.cts_mode = repmat("reference",height(reference),1);

        common_vars = intersect(affected.Properties.VariableNames, ...
            reference.Properties.VariableNames,'stable');
        combined = [affected(:,common_vars); reference(:,common_vars)];
        writetable(combined,fullfile(out_root, ...
            sprintf('combined_summary_pkt%g.csv',pkt_us)));

        plot_all_protocols(combined,pkt_us,fullfile(fig_dir, ...
            sprintf('all_protocols_delay_pkt%g.png',pkt_us)));
    end

    append_readme(out_root);
    fprintf('\n===== QUASI CTS IDEAL ALL-HEAR DONE =====\n');
    fprintf('Results: %s\n',out_root);
end

function cfg = make_quasi_cfg(raw_root,pkt_us,loads,protocols)
    n_sta = 40;
    cfg = default_experiment_config('analysis');
    cfg.txop_mode = 'ready_queue';
    cfg.protocols = protocols;
    cfg.M_values = [1 20];
    cfg.lambda_values = loads / (n_sta * pkt_us * 1e-6);
    cfg.load_modes = {'fixed_packet'};
    cfg.n_nodes = n_sta;

    % Decoupled packet duration and ideal quasi-omni CTS timing.
    cfg.mmw_data_slot_us = pkt_us;
    cfg.cts_mode = 'quasi_omni_ideal';
    cfg.mmw_real_cts_sweep_us = 14.5;
    cfg.mmw_real_cts_timeout_us = 16 + 14.5;
    cfg.mmw_real_conn_slot_us = 14.5 + 16 + 14.5 + 16;

    cfg.results_root = raw_root;
    cfg.output_dir = fullfile(raw_root,sprintf('pkt%g',pkt_us));
    cfg.resume = true;
    cfg.run_preflight_tests = false;
    cfg.n_eval_runs = 3;
    cfg.condition_timeout_s = 1800;
    cfg.n_workers = 2;
    cfg.q_multi_basin_tuning = true;
    qgrid = build_piecewise_q_grid(NaN);
    cfg.q_coarse = qgrid;
    cfg.protocol_q_grids_enabled = true;
    cfg.protocol_q_grids.sf_cb = qgrid;
    cfg.protocol_q_grids.sb_cb = qgrid;
    cfg.protocol_q_grids.unslotted = qgrid;
    cfg.stability_rate_tolerance = 0.05;
    cfg.stability_censor_tolerance = 0.01;
    cfg.stability_slope_fraction = 0.05;
    cfg.stability_require_slope = true;
end

function t = attach_load_metadata(t,cfg,pkt_us,cts_mode)
    t.total_load = double(t.lambda_base) * cfg.n_nodes * pkt_us * 1e-6;
    t.packet_duration_us = repmat(pkt_us,height(t),1);
    t.cts_mode = repmat(cts_mode,height(t),1);
end

function path = reference_summary_path(project_root,pkt_us)
    if abs(pkt_us-162.5) < 1e-9
        path = fullfile(project_root,'R10_results','lambda_sweep', ...
            'summary.csv');
    elseif abs(pkt_us-650) < 1e-9
        path = fullfile(project_root,'R10_results', ...
            'lambda_sweep_pkt650','summary.csv');
    else
        error('run_quasi_cts_ideal_all_hear:NoReference', ...
            'No reference summary is defined for pkt=%g us.',pkt_us);
    end
end

function plot_all_protocols(data,pkt_us,path)
    proto_order = {'sf_cf','sf_cb','sb_cf','sb_cb', ...
        'unslotted','s7_clean','s7_busy'};
    fig = figure('Visible','off','Color','white','Units','pixels', ...
        'Position',[100 100 1350 620]);
    hold on;
    for i = 1:numel(proto_order)
        protocol = proto_order{i};
        keep_p = string(data.protocol) == protocol;
        if ~any(keep_p), continue; end
        Ms = unique(double(data.M(keep_p)));
        for j = 1:numel(Ms)
            M = Ms(j);
            sub = data(keep_p & abs(double(data.M)-M) < 1e-9,:);
            if isempty(sub), continue; end
            x = double(sub.total_load);
            y = double(sub.mean_delay_us);
            stable = double(sub.stable_fraction) >= 1-1e-12 & ...
                double(sub.completion_ratio) >= 0.99 & isfinite(y);
            [x,order] = sort(x);
            y = y(order);
            stable = stable(order);
            color = protocol_color(protocol);
            marker = protocol_marker(protocol);
            line_style = '--';
            if abs(M-1) < 1e-9, line_style = '-'; end
            if any(stable)
                plot(x(stable),y(stable),'Color',color, ...
                    'LineStyle',line_style,'Marker',marker, ...
                    'LineWidth',1.6,'MarkerSize',5, ...
                    'MarkerFaceColor',color, ...
                    'DisplayName',display_protocol(protocol,M));
            end
            if any(~stable)
                plot(x(~stable),y(~stable),'Color',color, ...
                    'LineStyle','none','Marker',marker, ...
                    'MarkerSize',5,'MarkerFaceColor','none', ...
                    'HandleVisibility','off');
            end
        end
    end
    hold off;
    grid on; box on;
    xlabel('Total offered load');
    ylabel('Mean end-to-end delay (\mus)');
    title(sprintf(['Delay vs total load: affected protocols use quasi-omni ' ...
        'CTS (pkt=%g us)'],pkt_us));
    set(gca,'YScale','log');
    xlim([0 0.85]);
    legend('Location','eastoutside','Interpreter','none','FontSize',10);
    drawnow;
    print(fig,path,'-dpng','-r300');
    close(fig);
end

function color = protocol_color(protocol)
    switch protocol
        case 'sf_cf', color = [0.00 0.35 0.75];
        case 'sb_cf', color = [0.30 0.75 0.93];
        case 'sf_cb', color = [0.75 0.05 0.15];
        case 'sb_cb', color = [0.95 0.50 0.10];
        case 'unslotted', color = [0.20 0.60 0.20];
        case 's7_clean', color = [0.60 0.20 0.80];
        case 's7_busy', color = [0.00 0.65 0.65];
        otherwise, color = [0.3 0.3 0.3];
    end
end

function marker = protocol_marker(protocol)
    switch protocol
        case 'sf_cf', marker = 'o';
        case 'sb_cf', marker = 's';
        case 'sf_cb', marker = '^';
        case 'sb_cb', marker = 'd';
        case 'unslotted', marker = 'v';
        case 's7_clean', marker = 'p';
        case 's7_busy', marker = 'h';
        otherwise, marker = 'o';
    end
end

function label = display_protocol(protocol,M)
    switch protocol
        case 'sf_cf', base = 'SF-CF';
        case 'sf_cb', base = 'SF-CB';
        case 'sb_cf', base = 'SB-CF';
        case 'sb_cb', base = 'SB-CB';
        case 'unslotted', base = 'Unslotted';
        case 's7_clean', base = 'S7-AN(nS=0)';
        case 's7_busy', base = 'S7-AN(nS=10)';
        otherwise, base = protocol;
    end
    label = sprintf('%s(M=%g)',base,M);
end

function append_readme(out_root)
    path = fullfile(out_root,'README.md');
    fid = fopen(path,'w');
    if fid < 0, return; end
    cleanup = onCleanup(@() fclose(fid));
    fprintf(fid,'# Quasi-omni CTS with ideal all-hear assumption\n\n');
    fprintf(fid,'- Affected protocols rerun: sf_cb, sb_cb, unslotted\n');
    fprintf(fid,'- Reference protocols reused: sf_cf, sb_cf, s7_clean, s7_busy\n');
    fprintf(fid,'- CTS: one 14.5 us quasi-omni CTS\n');
    fprintf(fid,'- CTS assumption: every non-transmitting STA decodes CTS and sets NAV\n');
    fprintf(fid,'- Reservation conn-slot: 61 us\n');
    fprintf(fid,'- Packet durations: 162.5 us and 650 us\n');
    fprintf(fid,'- M: 1 and 20\n');
    fprintf(fid,'- Total offered loads: 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.8\n');
end
