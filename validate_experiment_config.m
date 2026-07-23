function cfg = validate_experiment_config(cfg)
%VALIDATE_EXPERIMENT_CONFIG Validate and normalize a v2 experiment config.

    required = {'protocols','lambda_values','M_values','load_modes', ...
                'n_nodes','n_sectors','arrival_tick_us','warmup_us', ...
                'measure_us','drain_max_us','q_coarse'};
    for i = 1:numel(required)
        if ~isfield(cfg, required{i})
            error('validate_experiment_config:MissingField', ...
                  'Missing configuration field: %s', required{i});
        end
    end

    % A hand-written config only needs to specify the scientific axes and
    % durations above. All optional execution, PHY, statistics, ablation,
    % and seed fields receive the constructor's explicit defaults.
    profile = 'smoke';
    if isfield(cfg,'profile') && ~isempty(cfg.profile)
        profile = lower(char(cfg.profile));
    end
    defaults = default_experiment_config(profile);
    names = fieldnames(defaults);
    for i = 1:numel(names)
        name = names{i};
        if ~isfield(cfg,name)
            cfg.(name) = defaults.(name);
        end
    end

    if any(cfg.M_values < 1) || any(cfg.M_values ~= round(cfg.M_values))
        error('validate_experiment_config:BadM', ...
              'M_values must contain integers greater than or equal to one.');
    end
    extended_M = [double(cfg.ablation_M_values(:)); ...
                  double(cfg.robustness_M_values(:))];
    if any(extended_M < 1) || any(extended_M ~= round(extended_M))
        error('validate_experiment_config:BadExtendedM', ...
              'Ablation and robustness M values must be integers >= 1.');
    end
    if any(cfg.lambda_values < 0)
        error('validate_experiment_config:BadLambda', ...
              'lambda_values must be non-negative.');
    end
    if any(cfg.ablation_lambda_values < 0) || ...
            any(cfg.robustness_lambda_values < 0)
        error('validate_experiment_config:BadExtendedLambda', ...
              'Ablation and robustness lambda values must be non-negative.');
    end
    if cfg.measure_us <= 0 || cfg.warmup_us < 0 || cfg.drain_max_us < 0
        error('validate_experiment_config:BadDuration', ...
              'warmup, measurement, and drain durations are invalid.');
    end
    if cfg.tune_measure_us<=0 || cfg.tune_warmup_us<0 || ...
            cfg.tune_drain_max_us<0
        error('validate_experiment_config:BadTuneDuration', ...
              'Tuning warmup, measurement, and drain durations are invalid.');
    end
    if cfg.arrival_tick_us <= 0 || cfg.arrival_tick_us ~= round(cfg.arrival_tick_us)
        error('validate_experiment_config:BadArrivalTick', ...
              'arrival_tick_us must be a positive integer.');
    end
    if cfg.n_nodes < 1 || cfg.n_nodes ~= round(cfg.n_nodes) || ...
            cfg.n_sectors < 1 || cfg.n_sectors ~= round(cfg.n_sectors) || ...
            mod(cfg.n_nodes,cfg.n_sectors) ~= 0
        error('validate_experiment_config:BadTopologySize', ...
              'n_nodes must be a positive multiple of n_sectors.');
    end
    if cfg.n_tune_runs < 1 || cfg.n_tune_runs ~= round(cfg.n_tune_runs) || ...
            cfg.n_eval_runs < 1 || cfg.n_eval_runs ~= round(cfg.n_eval_runs)
        error('validate_experiment_config:BadRunCount', ...
              'n_tune_runs and n_eval_runs must be positive integers.');
    end
    if cfg.n_ablation_runs < 1 || cfg.n_ablation_runs ~= round(cfg.n_ablation_runs) || ...
            cfg.n_robustness_runs < 1 || cfg.n_robustness_runs ~= round(cfg.n_robustness_runs)
        error('validate_experiment_config:BadExtendedRunCount', ...
              'Ablation and robustness run counts must be positive integers.');
    end
    if cfg.q_refine_points < 0 || cfg.q_refine_points ~= round(cfg.q_refine_points)
        error('validate_experiment_config:BadRefineCount', ...
              'q_refine_points must be a non-negative integer.');
    end
    if cfg.n_workers < 1 || cfg.n_workers ~= round(cfg.n_workers)
        error('validate_experiment_config:BadWorkerCount', ...
              'n_workers must be a positive integer.');
    end
    if ~ismember(lower(char(cfg.cca_mode)),{'directional','oracle','disabled'})
        error('validate_experiment_config:BadCcaMode', ...
              'cca_mode must be directional, oracle, or disabled.');
    end
    if cfg.stats_sample_us <= 0 || cfg.stats_sample_us ~= round(cfg.stats_sample_us)
        error('validate_experiment_config:BadStatsSample', ...
              'stats_sample_us must be a positive integer number of microseconds.');
    end
    logical_fields = {'parallel','resume','collect_packet_log','collect_diagnostics', ...
        'collect_debug_trace','run_preflight_tests','run_cca_ablation', ...
        'run_topology_robustness','stability_require_slope', ...
        'tuning_rate_screen','protocol_q_grids_enabled'};
    for i=1:numel(logical_fields)
        name=logical_fields{i};
        value=cfg.(name);
        if ~isscalar(value) || ~(islogical(value) || ...
                (isnumeric(value) && isfinite(value) && ismember(value,[0 1])))
            error('validate_experiment_config:BadLogicalField', ...
                  'cfg.%s must be a logical scalar.',name);
        end
        cfg.(name)=logical(value);
    end
    if ~(isscalar(cfg.payload_bits_M1) && (isnan(cfg.payload_bits_M1) || ...
            (isfinite(cfg.payload_bits_M1) && cfg.payload_bits_M1 > 0)))
        error('validate_experiment_config:BadPayloadBits', ...
              'payload_bits_M1 must be NaN or a positive finite scalar.');
    end

    cfg.protocols = cellstr(string(cfg.protocols(:).'));
    cfg.load_modes = cellstr(string(cfg.load_modes(:).'));
    cfg.robustness_protocols = cellstr(string(cfg.robustness_protocols(:).'));
    cfg.cca_mode = lower(char(cfg.cca_mode));

    allowed_protocols = {'sf_cf','sf_cb','sb_cf','sb_cb','s7_clean','s7_busy'};
    if any(~ismember(cfg.protocols, allowed_protocols))
        error('validate_experiment_config:BadProtocol', ...
              'Unsupported protocol in cfg.protocols.');
    end
    if any(~ismember(cfg.robustness_protocols, allowed_protocols))
        error('validate_experiment_config:BadRobustnessProtocol', ...
              'Unsupported protocol in cfg.robustness_protocols.');
    end
    allowed_loads = {'fixed_packet','fixed_payload'};
    if any(~ismember(cfg.load_modes, allowed_loads))
        error('validate_experiment_config:BadLoadMode', ...
              'load_modes must contain fixed_packet and/or fixed_payload.');
    end
    cfg.ablation_load_modes = cellstr(string(cfg.ablation_load_modes(:).'));
    if any(~ismember(cfg.ablation_load_modes,allowed_loads))
        error('validate_experiment_config:BadAblationLoadMode', ...
              'Unsupported load mode in cfg.ablation_load_modes.');
    end
    cfg.cca_ablation_modes = cellstr(string(cfg.cca_ablation_modes(:).'));
    if any(~ismember(cfg.cca_ablation_modes,{'directional','oracle','disabled'}))
        error('validate_experiment_config:BadAblationCcaMode', ...
              'Unsupported CCA mode in cfg.cca_ablation_modes.');
    end

    cfg.M_values = unique(double(cfg.M_values(:).'));
    cfg.lambda_values = unique(double(cfg.lambda_values(:).'));
    cfg.ablation_M_values = unique(double(cfg.ablation_M_values(:).'));
    cfg.robustness_M_values = unique(double(cfg.robustness_M_values(:).'));
    cfg.ablation_lambda_values = unique(double(cfg.ablation_lambda_values(:).'));
    cfg.robustness_lambda_values = unique(double(cfg.robustness_lambda_values(:).'));
    cfg.q_coarse = unique(double(cfg.q_coarse(:).'));
    cfg.q_coarse = cfg.q_coarse(cfg.q_coarse > 0 & cfg.q_coarse <= 1);
    if isempty(cfg.q_coarse)
        error('validate_experiment_config:EmptyQ', 'q_coarse has no valid q values.');
    end
    if ~isstruct(cfg.protocol_q_grids)
        error('validate_experiment_config:BadProtocolQGrids', ...
              'cfg.protocol_q_grids must be a struct.');
    end
    for i = 1:numel(allowed_protocols)
        protocol = allowed_protocols{i};
        if ~isfield(cfg.protocol_q_grids,protocol)
            error('validate_experiment_config:MissingProtocolQGrid', ...
                  'Missing protocol q grid: %s.',protocol);
        end
        values = unique(double(cfg.protocol_q_grids.(protocol)(:).'));
        if cfg.protocol_q_grids_enabled && ...
                (isempty(values) || any(~isfinite(values) | values<=0 | values>=1))
            error('validate_experiment_config:BadProtocolQGrid', ...
                  ['Enabled protocol q grid %s must contain finite values ', ...
                   'strictly between zero and one.'],protocol);
        end
        cfg.protocol_q_grids.(protocol) = values;
    end

    cfg.condition_filter = cellstr(string(cfg.condition_filter(:).'));
    cfg.condition_filter = unique(cfg.condition_filter,'stable');
    if ~isempty(cfg.condition_filter)
        valid_tags = cell(0,1);
        for li = 1:numel(cfg.load_modes)
            for bi = 1:numel(cfg.lambda_values)
                for mi = 1:numel(cfg.M_values)
                    for pi = 1:numel(cfg.protocols)
                        valid_tags{end+1,1} = sprintf('%s_%s_lam%g_M%d', ... %#ok<AGROW>
                            cfg.protocols{pi},cfg.load_modes{li}, ...
                            cfg.lambda_values(bi),cfg.M_values(mi));
                    end
                end
            end
        end
        unknown = setdiff(cfg.condition_filter,valid_tags);
        if ~isempty(unknown)
            error('validate_experiment_config:BadConditionFilter', ...
                  'Unknown condition tag in cfg.condition_filter: %s.',unknown{1});
        end
    end

    cfg.arrival_end_us = cfg.warmup_us + cfg.measure_us;
    cfg.sim_hard_end_us = cfg.arrival_end_us + cfg.drain_max_us;
end
