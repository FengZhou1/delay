function outputs = run_R10_cts_mode(mode_id, data_failure_mode, protocols, ...
                        output_root, packet_durations_us, qo_iso_gains_db)
%RUN_R10_CTS_MODE Run one of the four CTS experiments for delay.

    if nargin < 1 || isempty(mode_id)
        error('run_R10_cts_mode:MissingMode','mode_id is required.');
    end
    mode_id = double(mode_id);
    if ~ismember(mode_id,1:5)
        error('run_R10_cts_mode:BadMode', ...
            'mode_id must be 1, 2, 3, 4, or 5.');
    end
    if nargin < 2 || isempty(data_failure_mode)
        data_failure_mode = 'txop';
    end
    data_failure_mode = lower(char(data_failure_mode));
    if ~ismember(data_failure_mode,{'txop','packet'})
        error('run_R10_cts_mode:BadFailureMode', ...
            'data_failure_mode must be txop or packet.');
    end
    all_protocols = {'sf_cb','sb_cf','sb_cb','unslotted'};
    % SB-CF, SF-CF and S7-AN never read a CTS parameter, so their
    % results are identical in all four modes.  SB-CF is therefore
    % simulated only in mode 1, where it also produces the M=20 rows
    % that modes 2-4 reuse as the common reference.  SF-CF and S7-AN
    % are never simulated here; they always come from the references.
    % Unslotted stays in all_protocols (it can still be requested
    % explicitly) but is no longer part of the default runs or figures.
    default_protocols = {'sf_cb','sb_cf','sb_cb'};
    if mode_id ~= 1
        default_protocols = {'sf_cb','sb_cb'};
    end
    if nargin < 3 || isempty(protocols)
        protocols = default_protocols;
    else
        protocols = cellstr(string(protocols(:).'));
        if any(~ismember(protocols,all_protocols))
            error('run_R10_cts_mode:BadProtocol', ...
                'protocols must be a subset of sf_cb, sb_cf, sb_cb, unslotted.');
        end
    end

    project_root = fileparts(mfilename('fullpath'));
    old_dir = cd(project_root);
    cleanup = onCleanup(@() cd(old_dir));

    if nargin < 4 || isempty(output_root)
        stamp = char(datetime('now','Format','yyyyMMdd_HHmmss'));
        result_root = fullfile(project_root,'R10_results',stamp);
    else
        result_root = char(output_root);
    end
    if ~isfolder(result_root), mkdir(result_root); end
    if nargin < 5 || isempty(packet_durations_us)
        packet_durations_us = [162.5,650];
    else
        packet_durations_us = double(packet_durations_us(:).');
        if any(~ismember(packet_durations_us,[162.5,650]))
            error('run_R10_cts_mode:BadPacketDuration', ...
                'packet_durations_us must be a subset of [162.5, 650].');
        end
    end
    if nargin < 6 || isempty(qo_iso_gains_db)
        qo_iso_gains_db = -9;      % 方案5 默认只跑 -9 dB
    else
        qo_iso_gains_db = double(qo_iso_gains_db(:).');
        if any(~isfinite(qo_iso_gains_db))
            error('run_R10_cts_mode:BadQoIsoGain', ...
                'qo_iso_gains_db must be finite.');
        end
    end
    loads = [0.1,0.2,0.3,0.5,0.6];
    % Protocols that may appear in a merged summary / figure.
    kept_protocols = {'sf_cf','sf_cb','sb_cf','sb_cb','s7_clean','s7_busy'};

    result_dirs = {};
    if mode_id == 3
        gain_values = 0;
    elseif mode_id == 5
        gain_values = qo_iso_gains_db;
    else
        gain_values = NaN;
    end

    for gi = 1:numel(gain_values)
        qo_gain = 0;
        report_gain = NaN;
        if mode_id == 3
            variant = sprintf('qo_%gdB',gain_values(gi));
            result_dir = fullfile(result_root,'result3',variant);
            cts_mode = 'quasi_omni_physical';
            qo_gain = gain_values(gi);
            report_gain = qo_gain;
            label = sprintf('R10 result3 (%s)',variant);
        elseif mode_id == 5
            variant = sprintf('qo_iso_%gdB',gain_values(gi));
            result_dir = fullfile(result_root,'result5',variant);
            cts_mode = 'quasi_omni_isotropic';
            qo_gain = gain_values(gi);
            report_gain = qo_gain;
            label = sprintf('R10 result5 (%s)',variant);
        else
            result_dir = fullfile(result_root,sprintf('result%d',mode_id));
            switch mode_id
                case 1
                    cts_mode = 'sector_sweep';
                    label = 'R10 result1';
                case 2
                    cts_mode = 'quasi_omni_ideal';
                    label = 'R10 result2';
                case 4
                    cts_mode = 'directional_winner';
                    label = 'R10 result4';
            end
        end
        if ~isfolder(result_dir), mkdir(result_dir); end
        fig_dir = fullfile(result_dir,'figures');
        if ~isfolder(fig_dir), mkdir(fig_dir); end

        for ip = 1:numel(packet_durations_us)
            pkt_us = packet_durations_us(ip);
            fprintf('\n===== %s, packet=%.1f us =====\n',label,pkt_us);
            cfg = make_cfg(result_dir,cts_mode,qo_gain,pkt_us,loads, ...
                protocols,data_failure_mode);
            [cfg_hash,~] = experiment_config_hash(cfg);
            cfg.output_dir = fullfile(cfg.results_root, ...
                sprintf('pkt%g_%s',pkt_us,cfg_hash));
            affected_path = find_existing_raw_summary( ...
                cfg.results_root,pkt_us,cfg_hash,cfg);
            if isempty(affected_path)
                experiment = run_experiment(cfg);
                affected_path = fullfile(experiment.output_dir,'summary.csv');
            else
                fprintf('Reusing completed raw summary: %s\n',affected_path);
            end
            affected = readtable(affected_path,'VariableNamingRule','preserve');
            expected_conditions = numel(protocols) * numel(cfg.M_values) * ...
                numel(cfg.lambda_values);
            if height(affected) ~= expected_conditions
                error('run_R10_cts_mode:IncompleteRawSummary', ...
                    ['Raw summary contains %d conditions; expected %d. ' ...
                     'Delete or complete that raw run before resuming.'], ...
                    height(affected),expected_conditions);
            end
            affected.total_load = double(affected.lambda_base) * cfg.n_nodes * ...
                pkt_us * 1e-6;
            affected.packet_duration_us = repmat(pkt_us,height(affected),1);
            affected.cts_mode = repmat(string(cts_mode),height(affected),1);
            if isfinite(report_gain)
                affected.qo_peak_gain_db = repmat(report_gain,height(affected),1);
            else
                affected.qo_peak_gain_db = nan(height(affected),1);
            end

            if mode_id == 1
                reference = load_legacy_reference_summary(project_root,pkt_us);
            else
                reference = load_reference_summary(result_root,pkt_us);
            end
            reference = reference(~ismember(string(reference.protocol), ...
                string(protocols)),:);
            summary_path = fullfile(result_dir, ...
                sprintf('summary_pkt%g.csv',pkt_us));
            if isfile(summary_path)
                old = readtable(summary_path,'VariableNamingRule','preserve');
                keep_old = ~ismember(string(old.protocol),string(protocols));
                old = old(keep_old,:);
                common = intersect(old.Properties.VariableNames, ...
                    affected.Properties.VariableNames,'stable');
                combined = [old(:,common); affected(:,common)];
            else
                common = intersect(affected.Properties.VariableNames, ...
                    reference.Properties.VariableNames,'stable');
                combined = [affected(:,common); reference(:,common)];
            end
            combined = restrict_summary(combined,cfg.lambda_values, ...
                kept_protocols);
            writetable(combined,summary_path);
            plot_R10_cts_result(combined,pkt_us,fullfile(fig_dir, ...
                sprintf('mean_delay_pkt%g.png',pkt_us)),label);
        end
        write_readme(result_dir,cts_mode,qo_gain,loads,data_failure_mode, ...
            protocols);
        result_dirs{end+1,1} = result_dir; %#ok<AGROW>
    end
    outputs = struct('mode_id',mode_id,'result_root',result_root, ...
        'result_dirs',{result_dirs});
end

function cfg = make_cfg(result_dir,cts_mode,qo_gain,pkt_us,loads, ...
                        protocols,data_failure_mode)
    n_sta = 40;
    raw_root = fullfile(result_dir,'raw');
    if ~isfolder(raw_root), mkdir(raw_root); end
    cfg = default_experiment_config('analysis');
    cfg.txop_mode = 'ready_queue';
    cfg.protocols = protocols;
    cfg.M_values = [1 20];
    cfg.lambda_values = loads / (n_sta * pkt_us * 1e-6);
    cfg.load_modes = {'fixed_packet'};
    cfg.n_nodes = n_sta;
    cfg.mmw_data_slot_us = pkt_us;
    cfg.cts_mode = cts_mode;
    cfg.qo_peak_gain_db = qo_gain;
    cfg.data_failure_mode = data_failure_mode;
    if strcmp(cts_mode,'sector_sweep')
        cfg.mmw_real_cts_sweep_us = cfg.mmw_real_cts_us * cfg.n_sectors;
        cfg.mmw_real_cts_timeout_us = cfg.mmw_real_sifs_us + ...
            cfg.mmw_real_cts_sweep_us;
        cfg.mmw_real_conn_slot_us = cfg.mmw_real_rts_us + ...
            cfg.mmw_real_sifs_us + cfg.mmw_real_cts_sweep_us + ...
            cfg.mmw_real_sifs_us;
    else
        cfg.mmw_real_cts_sweep_us = cfg.mmw_real_cts_us;
        cfg.mmw_real_cts_timeout_us = cfg.mmw_real_sifs_us + ...
            cfg.mmw_real_cts_us;
        cfg.mmw_real_conn_slot_us = cfg.mmw_real_rts_us + ...
            cfg.mmw_real_sifs_us + cfg.mmw_real_cts_us + cfg.mmw_real_sifs_us;
    end
    cfg.results_root = raw_root;
    cfg.output_dir = fullfile(raw_root,sprintf('pkt%g_ctsfix',pkt_us));
    cfg.resume = true;
    cfg.run_preflight_tests = false;
    cfg.n_eval_runs = 3;
    cfg.condition_timeout_s = 1800;
    cfg.n_workers = 4;
    cfg = apply_runtime_parallel_env(cfg);
    cfg.q_multi_basin_tuning = true;
    qgrid = build_piecewise_q_grid(NaN);
    cfg.q_coarse = qgrid;
    cfg.protocol_q_grids_enabled = true;
    all_protocols = {'sf_cf','sf_cb','sb_cf','sb_cb', ...
        's7_clean','s7_busy','unslotted'};
    for p = 1:numel(all_protocols)
        cfg.protocol_q_grids.(all_protocols{p}) = qgrid;
    end
    if ismember(cts_mode,{'quasi_omni_physical','quasi_omni_isotropic', ...
            'directional_winner'})
        cfg.protocol_q_grids.sf_cb = [ ...
            0.0005,0.001,0.002,0.003,0.005,0.0075, ...
            0.01,0.0125,0.015,0.02,0.025,0.03];
    end
    cfg.stability_rate_tolerance = 0.05;
    cfg.stability_censor_tolerance = 0.01;
    cfg.stability_slope_fraction = 0.05;
    cfg.stability_require_slope = true;
end

function reference = load_reference_summary(result_root,pkt_us)
    path = fullfile(result_root,'result1', ...
        sprintf('summary_pkt%g.csv',pkt_us));
    if ~isfile(path)
        error('run_R10_cts_mode:MissingReference', ...
            ['Reference summary not found: %s. Run mode 1 first in the ' ...
             'same timestamped result directory.'],path);
    end
    data = readtable(path,'VariableNamingRule','preserve');
    keep = ismember(string(data.protocol), ...
        ["sf_cf","sb_cf","s7_clean","s7_busy"]);
    reference = data(keep,:);
    reference.total_load = double(reference.lambda_base) * 40 * pkt_us * 1e-6;
    reference.packet_duration_us = repmat(pkt_us,height(reference),1);
    reference.cts_mode = repmat("reference",height(reference),1);
    reference.qo_peak_gain_db = nan(height(reference),1);
end

function reference = load_legacy_reference_summary(project_root,pkt_us)
    if abs(pkt_us-162.5) < 1e-9
        path = fullfile(project_root,'R10_results','lambda_sweep','summary.csv');
    else
        path = fullfile(project_root,'R10_results','lambda_sweep_pkt650', ...
            'summary.csv');
    end
    if ~isfile(path)
        error('run_R10_cts_mode:MissingLegacyReference', ...
            'Legacy reference summary not found: %s.',path);
    end
    data = readtable(path,'VariableNamingRule','preserve');
    keep = ismember(string(data.protocol), ...
        ["sf_cf","sb_cf","s7_clean","s7_busy"]);
    reference = data(keep,:);
    reference.total_load = double(reference.lambda_base) * 40 * pkt_us * 1e-6;
    reference.packet_duration_us = repmat(pkt_us,height(reference),1);
    reference.cts_mode = repmat("reference",height(reference),1);
    reference.qo_peak_gain_db = nan(height(reference),1);
end

function path = find_existing_raw_summary(raw_root,pkt_us,cfg_hash,cfg)
%FIND_EXISTING_RAW_SUMMARY Locate a completed raw summary of this experiment.
%   The directory that carries the current config hash is preferred.  When
%   none exists, a raw summary of an earlier run is reused only if its
%   condition matrix (protocols, M values, loads, load modes) is exactly the
%   one requested here; otherwise it is ignored and reported, so a changed
%   protocol subset or config can never be merged by accident.
    path = '';
    if ~isfolder(raw_root)
        return;
    end
    exact = fullfile(raw_root,sprintf('pkt%g_%s',pkt_us,cfg_hash), ...
        'summary.csv');
    if isfile(exact)
        path = exact;
        return;
    end
    candidates = dir(fullfile(raw_root,sprintf('pkt%g_*',pkt_us)));
    if isempty(candidates)
        return;
    end
    [~,order] = sort([candidates.datenum],'descend');
    ignored = {};
    for ii = order
        candidate = fullfile(candidates(ii).folder,candidates(ii).name, ...
            'summary.csv');
        if ~isfile(candidate)
            continue;
        end
        if raw_summary_matches(candidate,cfg)
            fprintf(['Reusing raw summary with a different config/code ', ...
                'fingerprint (condition matrix matches): %s\n'],candidate);
            path = candidate;
            return;
        end
        ignored{end+1} = candidates(ii).name; %#ok<AGROW>
    end
    if ~isempty(ignored)
        fprintf(['Ignoring %d raw summary(ies) for pkt=%g us that were ', ...
            'produced by a different condition set: %s\n'], ...
            numel(ignored),pkt_us,strjoin(ignored,', '));
    end
end

function tf = raw_summary_matches(path,cfg)
%RAW_SUMMARY_MATCHES True when a raw summary covers exactly cfg's conditions.
    tf = false;
    try
        data = readtable(path,'VariableNamingRule','preserve');
    catch
        return;
    end
    required = {'protocol','load_mode','lambda_base','M'};
    if ~all(ismember(required,data.Properties.VariableNames))
        return;
    end
    expected = numel(cfg.protocols) * numel(cfg.M_values) * ...
        numel(cfg.lambda_values) * numel(cfg.load_modes);
    if height(data) ~= expected
        return;
    end
    proto_have = unique(string(data.protocol));
    if numel(proto_have) ~= numel(cfg.protocols) || ...
            ~all(ismember(string(cfg.protocols(:)),proto_have))
        return;
    end
    mode_have = unique(string(data.load_mode));
    if numel(mode_have) ~= numel(cfg.load_modes) || ...
            ~all(ismember(string(cfg.load_modes(:)),mode_have))
        return;
    end
    m_have = unique(double(data.M));
    if numel(m_have) ~= numel(cfg.M_values) || ...
            ~all(ismember(double(cfg.M_values(:)),m_have))
        return;
    end
    have = sort(unique(double(data.lambda_base)));
    want = sort(double(cfg.lambda_values(:)));
    if numel(have) ~= numel(want)
        return;
    end
    tolerance = 1e-9 * max(1,max(abs(want)));
    if any(abs(have-want) > tolerance)
        return;
    end
    tf = true;
end

function data = restrict_summary(data,lambda_values,kept_protocols)
%RESTRICT_SUMMARY Keep only reported protocols and the scanned load grid.
%   lambda_values is cfg.lambda_values, i.e. the per-node arrival rate that
%   is stored in the lambda_base column.  Reference rows may come from an
%   older run with a wider load grid; they are trimmed here so every merged
%   summary uses one single grid.
    keep = ismember(string(data.protocol),string(kept_protocols));
    tolerance = 1e-9 * max(1,max(abs(double(lambda_values))));
    keep = keep & any(abs(double(data.lambda_base) - double(lambda_values(:).')) ...
        <= tolerance,2);
    data = data(keep,:);
end

function write_readme(result_dir,cts_mode,qo_gain,loads,data_failure_mode, ...
                        protocols)
    path = fullfile(result_dir,'README.md');
    fid = fopen(path,'w');
    if fid < 0, return; end
    cleanup = onCleanup(@() fclose(fid));
    fprintf(fid,'# R10 CTS experiment\n\n');
    fprintf(fid,'- CTS mode: %s\n',cts_mode);
    if isfinite(qo_gain)
        fprintf(fid,'- Quasi-omni peak gain: %g dB\n',qo_gain);
    end
    fprintf(fid,'- DATA failure mode: %s\n',data_failure_mode);
    fprintf(fid,'- Packet durations: 162.5 and 650 us\n');
    fprintf(fid,'- Total offered loads: %s\n',mat2str(loads));
    fprintf(fid,'- CF protocols use M=1; CB protocols use M=1 and 20.\n');
    fprintf(fid,'- Protocols simulated in this run: %s\n', ...
        strjoin(protocols,', '));
    fprintf(fid,'- Protocols kept in the merged summary: %s\n', ...
        'sf_cf, sf_cb, sb_cf, sb_cb, s7_clean, s7_busy');
    fprintf(fid,'- SF-CF, SB-CF, and S7-AN are reused from the available R10 references when not rerun.\n');
end
function cfg = apply_runtime_parallel_env(cfg)
%APPLY_RUNTIME_PARALLEL_ENV Runtime-only parallel overrides for concurrent runs.
%   R10_N_WORKERS=<n>   use an n-worker pool (n >= 1); default stays 4.
%   R10_PARALLEL=0      run serially with no parpool at all.
%   Both settings live on the machine, not in the science: n_workers and
%   parallel are stripped from the config hash (see experiment_config_hash),
%   so the run identity and its resume behaviour are unchanged.
    workers = getenv('R10_N_WORKERS');
    if ~isempty(workers)
        n = str2double(workers);
        if isfinite(n) && n >= 1 && n == floor(n)
            cfg.n_workers = n;
        else
            warning('run_R10_cts_mode:BadWorkerEnv', ...
                'Ignoring R10_N_WORKERS=%s (expected a positive integer).', ...
                workers);
        end
    end
    flag = strtrim(getenv('R10_PARALLEL'));
    if any(strcmpi(flag,{'0','false','off','no'}))
        cfg.parallel = false;
    end
end