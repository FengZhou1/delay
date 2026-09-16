function output = run_saturation_cts_mode(mode_id, data_failure_mode, protocols, ...
                        output_root, qo_iso_gains_db)
%RUN_SATURATION_CTS_MODE Run one CTS mode for saturated throughput.

    if nargin < 1 || isempty(mode_id)
        error('run_saturation_cts_mode:MissingMode','mode_id is required.');
    end
    mode_id = double(mode_id);
    if ~ismember(mode_id,1:5)
        error('run_saturation_cts_mode:BadMode', ...
            'mode_id must be 1,2,3,4,5.');
    end
    if nargin < 2 || isempty(data_failure_mode)
        data_failure_mode = 'txop';
    end
    data_failure_mode = lower(char(data_failure_mode));
    if ~ismember(data_failure_mode,{'txop','packet'})
        error('run_saturation_cts_mode:BadFailureMode', ...
            'data_failure_mode must be txop or packet.');
    end
    all_protocols = {'sf_cf','sf_cb','sb_cf','sb_cb', ...
        's7_clean','s7_busy','unslotted'};
    if nargin < 3 || isempty(protocols)
        protocols = all_protocols;
    else
        protocols = cellstr(string(protocols(:).'));
        if any(~ismember(protocols,all_protocols))
            error('run_saturation_cts_mode:BadProtocol', ...
                'protocols contains an unsupported protocol.');
        end
    end

    if nargin < 5 || isempty(qo_iso_gains_db)
        qo_iso_gains_db = -9;      % mode 5 default: -9 dB only
    else
        qo_iso_gains_db = double(qo_iso_gains_db(:).');
    end
    this_dir = fileparts(mfilename('fullpath'));
    old_dir = cd(this_dir);
    cleanup = onCleanup(@() cd(old_dir));

    if nargin < 4 || isempty(output_root)
        stamp = char(datetime('now','Format','yyyyMMdd_HHmmss'));
        result_root = fullfile(this_dir,'results_R10_cts',stamp);
    else
        result_root = char(output_root);
    end
    if mode_id == 1
        result_dir = fullfile(result_root,'result1');
        cts_mode = 'sector_sweep';
        gains = NaN;
    elseif mode_id == 2
        result_dir = fullfile(result_root,'result2');
        cts_mode = 'quasi_omni_ideal';
        gains = NaN;
    elseif mode_id == 3
        result_dir = fullfile(result_root,'result3');
        cts_mode = 'quasi_omni_physical';
        gains = 0;
    elseif mode_id == 4
        result_dir = fullfile(result_root,'result4');
        cts_mode = 'directional_winner';
        gains = NaN;
    else
        result_dir = fullfile(result_root,'result5');
        cts_mode = 'quasi_omni_isotropic';
        gains = qo_iso_gains_db;
    end
    if ~isfolder(result_dir), mkdir(result_dir); end
    new_data = table();
    for gi = 1:numel(gains)
        if isnan(gains(gi))
            variant = sprintf('result%d',mode_id);
            gain = -3;
        elseif mode_id == 5
            variant = sprintf('qo_iso_%gdB',gains(gi));
            gain = gains(gi);
        else
            variant = sprintf('qo_%gdB',gains(gi));
            gain = gains(gi);
        end
        fprintf('\n===== Saturation CTS %s =====\n',variant);
        cfg = make_cfg(result_dir,cts_mode,gain,variant, ...
            data_failure_mode,protocols);
        [cfg_hash,~] = experiment_config_hash(cfg);
        cfg.output_dir = fullfile(cfg.results_root, ...
            sprintf('%s_%s',variant,cfg_hash));
        experiment = run_saturation_experiment(cfg);
        part = readtable(fullfile(experiment.output_dir, ...
            'saturation_summary.csv'),'VariableNamingRule','preserve');
        part.cts_mode = repmat(string(cts_mode),height(part),1);
        if isfinite(gain)
            part.qo_peak_gain_db = repmat(gain,height(part),1);
        else
            part.qo_peak_gain_db = nan(height(part),1);
        end
        part.cts_variant = repmat(string(variant),height(part),1);
        new_data = [new_data; part]; %#ok<AGROW>
    end
    summary_path = fullfile(result_dir,'saturation_summary.csv');
    % CTS mode only affects the CB protocols.  For a partial run, merge the
    % newly simulated protocols with the unchanged reference rows from
    % result1.  Refresh the references on every partial run so an existing
    % stale summary cannot leave the final figure with only the CB curves.
    run_variants = unique(string(new_data.cts_variant),'stable');
    combined = new_data;
    if ~isequal(sort(string(protocols)),sort(string(all_protocols)))
        if isfile(summary_path)
            old = readtable(summary_path,'VariableNamingRule','preserve');
            if ~ismember('cts_variant',old.Properties.VariableNames)
                old.cts_variant = repmat("",height(old),1);
            end
            old_variants = string(old.cts_variant);
            duplicate_run = ismember(string(old.protocol),string(protocols)) & ...
                ismember(old_variants,run_variants);
            old = old(~(duplicate_run | old_variants == "reference"),:);
            common = intersect(old.Properties.VariableNames, ...
                new_data.Properties.VariableNames,'stable');
            combined = [old(:,common); new_data(:,common)];
        end

        ref_path = fullfile(result_root,'result1','saturation_summary.csv');
        if isfile(ref_path)
            ref = readtable(ref_path,'VariableNamingRule','preserve');
            ref = ref(~ismember(string(ref.protocol),string(protocols)),:);
            ref.cts_mode = repmat("reference",height(ref),1);
            ref.cts_variant = repmat("reference",height(ref),1);
            if any(strcmp('qo_peak_gain_db',ref.Properties.VariableNames))
                ref.qo_peak_gain_db = nan(height(ref),1);
            end
            common = intersect(combined.Properties.VariableNames, ...
                ref.Properties.VariableNames,'stable');
            combined = [combined(:,common); ref(:,common)];
            fprintf('Merged %d reference rows from %s\n',height(ref),ref_path);
        else
            warning('run_saturation_cts_mode:MissingReference', ...
                'Reference summary not found: %s',ref_path);
        end
    end
    kept_protocols = {'sf_cf','sf_cb','sb_cf','sb_cb','s7_clean','s7_busy'};
    combined = combined(ismember(string(combined.protocol), ...
        string(kept_protocols)),:);
    writetable(combined,summary_path);
    variants = unique(string(combined.cts_variant),'stable');
    variants = variants(variants ~= "reference");
    if ismember(mode_id,[3 5])
        for vi = 1:numel(variants)
            render_original_style(result_dir,combined,variants(vi),mode_id);
        end
    else
        render_original_style(result_dir,combined,"",mode_id);
    end
    if mode_id == 3
        figure_path = fullfile(result_dir, ...
            'throughput_vs_Tp_result3_qo_0dB.png');
    elseif mode_id == 5
        figure_path = fullfile(result_dir, ...
            sprintf('throughput_vs_Tp_result5_%s.png',char(variants(end))));
    else
        figure_path = fullfile(result_dir, ...
            sprintf('throughput_vs_Tp_result%d.png',mode_id));
    end
    write_readme(result_dir,cts_mode,gains,data_failure_mode);
    output = struct('mode_id',mode_id,'result_dir',result_dir, ...
        'summary_path',summary_path,'figure_path',figure_path);
end

function render_original_style(result_dir,data,variant,mode_id)
    if strlength(variant) > 0
        data = data(string(data.cts_variant) == variant | ...
            string(data.cts_variant) == "reference",:);
    end
    plot_input_dir = fullfile(result_dir,'_plot_input');
    if isfolder(plot_input_dir)
        rmdir(plot_input_dir,'s');
    end
    mkdir(plot_input_dir);
    writetable(data,fullfile(plot_input_dir,'saturation_summary.csv'));
    plot_result = plot_saturation_throughput_v2(plot_input_dir);

    if strlength(variant) > 0
        base = sprintf('throughput_vs_Tp_result%d_%s',mode_id,char(variant));
    else
        base = sprintf('throughput_vs_Tp_result%d',mode_id);
    end
    merged_fig_dir = fullfile(result_dir,'figures');
    if ~isfolder(merged_fig_dir), mkdir(merged_fig_dir); end
    copyfile(plot_result.png_path,fullfile(result_dir,[base '.png']),'f');
    copyfile(plot_result.pdf_path,fullfile(result_dir,[base '.pdf']),'f');
    copyfile(plot_result.png_path,fullfile(merged_fig_dir,[base '.png']),'f');
    copyfile(plot_result.pdf_path,fullfile(merged_fig_dir,[base '.pdf']),'f');
    copyfile(plot_result.intersections_path, ...
        fullfile(result_dir,'intersections.csv'),'f');

    if strlength(variant) > 0
        variant_dir = char(variant);
    else
        variant_dir = sprintf('result%d',mode_id);
    end
    legacy_dir = fullfile(result_dir,'raw',variant_dir,'figures');
    if isfolder(legacy_dir)
        copyfile(plot_result.png_path, ...
            fullfile(legacy_dir,'saturation_throughput_vs_Tp.png'),'f');
        copyfile(plot_result.pdf_path, ...
            fullfile(legacy_dir,'saturation_throughput_vs_Tp.pdf'),'f');
    end
    legacy_summary = fullfile(result_dir,'raw',variant_dir, ...
        'saturation_summary.csv');
    if isfolder(fileparts(legacy_summary))
        copyfile(fullfile(plot_input_dir,'saturation_summary.csv'), ...
            legacy_summary,'f');
    end
end

function cfg = make_cfg(result_dir,cts_mode,qo_gain,variant, ...
                        data_failure_mode,protocols)
    cfg = default_saturation_config('analysis');
    cfg.protocols = protocols;
    cfg.M_values = [0.1,0.2,0.4,0.6,1:6,8,10,15,20];
    cfg.results_root = fullfile(result_dir,'raw');
    cfg.output_dir = fullfile(cfg.results_root,[variant '_ctsfix']);
    if ~isfolder(cfg.results_root), mkdir(cfg.results_root); end
    cfg.resume = true;
    cfg.parallel = true;
    cfg.n_workers = 2;
    cfg.run_preflight_tests = false;
    cfg.cts_mode = cts_mode;
    cfg.qo_peak_gain_db = qo_gain;
    cfg.data_failure_mode = data_failure_mode;
    cfg.mmw_data_slot_us = 162.5;
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
            cfg.mmw_real_sifs_us + cfg.mmw_real_cts_us + ...
            cfg.mmw_real_sifs_us;
    end
    if ismember(cts_mode,{'quasi_omni_physical','quasi_omni_isotropic', ...
            'directional_winner'})
        cfg.protocol_q_grids.sf_cb = [ ...
            0.0005,0.001,0.002,0.003,0.005,0.0075, ...
            0.01,0.0125,0.015,0.02,0.025,0.03];
    end
end

function write_readme(result_dir,cts_mode,gains,data_failure_mode)
    path = fullfile(result_dir,'README.md');
    fid = fopen(path,'w');
    if fid < 0, return; end
    cleanup = onCleanup(@() fclose(fid));
    fprintf(fid,'# Saturation throughput CTS experiment\n\n');
    fprintf(fid,'- CTS mode: %s\n',cts_mode);
    if numel(gains) > 1 || isfinite(gains(1))
        fprintf(fid,'- QO peak gains: %s dB\n',mat2str(gains));
    end
    fprintf(fid,'- TXOP sweep is unchanged from the existing saturation study.\n');
    fprintf(fid,'- DATA payload unit remains 162.5 us.\n');
    fprintf(fid,'- DATA failure mode: %s.\n',data_failure_mode);
end
