function summary_path = run_delay_m_analysis(txop_mode, merged_name, include_cf, cfg_override)
%RUN_DELAY_M_ANALYSIS Run the M=1:6 delay sweep for one TXOP admission mode.
%   CF protocols are run only at M=1 and plotted as fixed baselines.
%   The batch_M mode excludes CF protocols entirely and uses M-packet
%   request queues with structural tail censoring.

    if nargin < 1 || isempty(txop_mode)
        txop_mode = 'ready_queue';
    end
    if nargin < 2 || isempty(merged_name)
        merged_name = 'R9_merged_logic1';
    end
    if nargin < 3 || isempty(include_cf)
        include_cf = true;
    end
    txop_mode = char(txop_mode);
    if strcmp(txop_mode, 'batch_m')
        txop_mode = 'batch_M';
    end

    cfg = default_experiment_config('analysis');
    cfg.txop_mode = txop_mode;
    cfg.protocols = {'sf_cb','sb_cb','unslotted','s7_clean','s7_busy'};
    cfg.M_values = 1:6;
    cfg.lambda_values = [16, 30];
    cfg.load_modes = {'fixed_packet'};
    cfg.resume = false;
    cfg.run_preflight_tests = false;
    cfg.n_eval_runs = 3;
    cfg.condition_timeout_s = 1800;
    cfg.n_workers = 4;

    % Piecewise ten-points-per-decade coarse grid plus local multi-basin
    % refinement.  Keep one coarse seed, validate the top candidates with
    % three seeds, and use independent three-seed evaluation.
    qgrid = build_piecewise_q_grid(NaN);
    cfg.q_coarse = qgrid;
    cfg.protocol_q_grids_enabled = true;
    cfg.q_multi_basin_tuning = true;
    cfg.q_coarse_seed_count = 1;
    cfg.q_refine_windows = 3;
    cfg.q_refine_points_per_window = 7;
    cfg.q_candidate_seed_count = 3;
    for p = 1:numel(cfg.protocols)
        cfg.protocol_q_grids.(cfg.protocols{p}) = qgrid;
    end
    cfg.protocol_q_grids.sf_cf = qgrid;
    cfg.protocol_q_grids.sb_cf = qgrid;

    cfg.stability_rate_tolerance = 0.05;
    cfg.stability_censor_tolerance = 0.01;
    cfg.stability_slope_fraction = 0.05;
    cfg.stability_require_slope = true;
    cf_output_dir = [];
    if nargin >= 4 && isstruct(cfg_override)
        names = fieldnames(cfg_override);
        for i = 1:numel(names)
            if strcmp(names{i},'cf_output_dir')
                cf_output_dir = cfg_override.(names{i});
            else
                cfg.(names{i}) = cfg_override.(names{i});
            end
        end
    end

    fprintf('=== M sweep: txop_mode=%s, output=%s ===\n', txop_mode, merged_name);
    scan_experiment = run_experiment(cfg);
    scan_dir = scan_experiment.output_dir;
    scan_summary = readtable(fullfile(scan_dir,'summary.csv'), ...
        'VariableNamingRule','preserve');
    scan_summary.fixed_M_baseline = false(height(scan_summary),1);

    cf_summary = table();
    if include_cf
        cf_cfg = cfg;
        cf_cfg.protocols = {'sf_cf','sb_cf'};
        cf_cfg.M_values = 1;
        cf_cfg.txop_mode = 'ready_queue';
        cf_cfg.q_multi_basin_tuning = true;
        cf_cfg.q_refine_windows = 3;
        if ~isempty(cf_output_dir)
            cf_cfg.output_dir = cf_output_dir;
        elseif isfield(cf_cfg,'output_dir') && ~isempty(cf_cfg.output_dir)
            cf_cfg = rmfield(cf_cfg,'output_dir');
        end
        cf_experiment = run_experiment(cf_cfg);
        cf_dir = cf_experiment.output_dir;
        cf_summary = readtable(fullfile(cf_dir,'summary.csv'), ...
            'VariableNamingRule','preserve');
        cf_summary.fixed_M_baseline = true(height(cf_summary),1);
        fprintf('CF baseline experiment: %s\n', cf_dir);
    end

    if is_absolute_path(char(merged_name))
        merged_dir = char(merged_name);
    else
        merged_dir = fullfile('results_v2',merged_name);
    end
    if ~isfolder(merged_dir)
        mkdir(merged_dir);
    end
    if isempty(cf_summary)
        merged = scan_summary;
    else
        merged = [scan_summary; cf_summary];
    end
    summary_path = fullfile(merged_dir,'summary.csv');
    writetable(merged,summary_path);

    copyfile(fullfile(scan_dir,'config.mat'), fullfile(merged_dir,'config.mat'),'f');
    if isfile(fullfile(scan_dir,'scenario.mat'))
        copyfile(fullfile(scan_dir,'scenario.mat'), fullfile(merged_dir,'scenario.mat'),'f');
    end

    figs = plot_delay_m_comparison(merged,merged_dir);
    write_m_analysis_readme(merged_dir,scan_dir,txop_mode,include_cf,numel(figs));
    fprintf('Merged summary: %s\n', summary_path);
end

function write_m_analysis_readme(out_dir,scan_dir,txop_mode,include_cf,n_figs)
    path = fullfile(out_dir,'README.md');
    fid = fopen(path,'w');
    if fid < 0
        return;
    end
    cleanup = onCleanup(@() fclose(fid));
    fprintf(fid,'# %s\n\n',out_dir);
    fprintf(fid,'- TXOP admission mode: `%s`\n',txop_mode);
    fprintf(fid,'- Scan protocols: `sf_cb`, `sb_cb`, `unslotted`, `s7_clean`, `s7_busy`\n');
    if include_cf
        fprintf(fid,'- CF baselines: `sf_cf`, `sb_cf` fixed at `M=1`\n');
    end
    fprintf(fid,'- M values: 1:6, lambda values: [16, 30]\n');
    fprintf(fid,'- q scan: piecewise 10 points/decade, 3 refined basins, top candidates 3 seeds, final eval 3 seeds\n');
    fprintf(fid,'- Raw scan experiment: `%s`\n',scan_dir);
    fprintf(fid,'- Figures generated: %d\n',n_figs);
end

function tf = is_absolute_path(p)
%IS_ABSOLUTE_PATH 判断路径是否为绝对路径（Windows 盘符或 UNC / 根路径）
    tf = false;
    if ~ischar(p) && ~isstring(p), return; end
    p = char(p);
    if ispc && numel(p) >= 2 && p(2) == ':' && ~isempty(regexp(p(1),'[A-Za-z]','once'))
        tf = true;
    elseif startsWith(p,'\') || startsWith(p,'/')
        tf = true;
    end
end