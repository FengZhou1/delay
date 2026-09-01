function cfg = validate_saturation_config(cfg)
%VALIDATE_SATURATION_CONFIG Validate and normalize saturation-study config.

    required = {'protocols','M_values','n_nodes','n_sectors','warmup_us', ...
        'measure_us','n_tune_runs','n_eval_runs','q_fine_points', ...
        'protocol_q_grids','results_root','resume','parallel','n_workers'};
    for i = 1:numel(required)
        if ~isfield(cfg,required{i})
            error('validate_saturation_config:MissingField', ...
                'cfg.%s is required.',required{i});
        end
    end

    if ~isfield(cfg,'study_type') || ...
            ~strcmpi(char(cfg.study_type),'saturation_throughput')
        error('validate_saturation_config:StudyType', ...
            'cfg.study_type must be saturation_throughput.');
    end
    if ~isfield(cfg,'traffic_mode') || ...
            ~strcmpi(char(cfg.traffic_mode),'saturation')
        error('validate_saturation_config:TrafficMode', ...
            'cfg.traffic_mode must be saturation.');
    end

    allowed = {'sf_cf','sf_cb','sb_cf','sb_cb','s7_clean','s7_busy','unslotted'};
    cfg.protocols = cellstr(string(cfg.protocols(:).'));
    if isempty(cfg.protocols) || any(~ismember(cfg.protocols,allowed))
        error('validate_saturation_config:Protocols', ...
            'cfg.protocols contains an unsupported protocol.');
    end

    cfg.M_values = unique(double(cfg.M_values(:).'),'stable');
    if isempty(cfg.M_values) || any(~isfinite(cfg.M_values)) || ...
            any(cfg.M_values <= 0)
        error('validate_saturation_config:MValues', ...
            'Saturation M values must be finite positive numbers.');
    end
    if cfg.n_nodes < 1 || cfg.n_nodes ~= round(cfg.n_nodes) || ...
            cfg.n_sectors < 1 || cfg.n_sectors ~= round(cfg.n_sectors) || ...
            mod(cfg.n_nodes,cfg.n_sectors) ~= 0
        error('validate_saturation_config:Topology', ...
            'n_nodes must be positive and divisible by n_sectors.');
    end
    if cfg.warmup_us < 0 || cfg.measure_us <= 0
        error('validate_saturation_config:Horizon', ...
            'warmup_us must be nonnegative and measure_us positive.');
    end

    integer_positive = {'n_tune_runs','n_eval_runs','q_fine_points','n_workers'};
    for i = 1:numel(integer_positive)
        value = cfg.(integer_positive{i});
        if ~isscalar(value) || ~isfinite(value) || value < 1 || ...
                value ~= round(value)
            error('validate_saturation_config:IntegerField', ...
                'cfg.%s must be a positive integer.',integer_positive{i});
        end
    end
    if cfg.q_fine_points < 3
        error('validate_saturation_config:FinePoints', ...
            'q_fine_points must be at least three.');
    end

    for i = 1:numel(allowed)
        protocol = allowed{i};
        if ~isfield(cfg.protocol_q_grids,protocol)
            error('validate_saturation_config:QGrid', ...
                'Missing q grid for %s.',protocol);
        end
        q = unique(double(cfg.protocol_q_grids.(protocol)(:).'));
        if isempty(q) || any(~isfinite(q) | q <= 0 | q > 1)
            error('validate_saturation_config:QGrid', ...
                'Invalid q grid for %s.',protocol);
        end
        cfg.protocol_q_grids.(protocol) = q;
    end

    logical_fields = {'resume','parallel','collect_packet_log', ...
        'collect_diagnostics','collect_debug_trace','run_preflight_tests'};
    for i = 1:numel(logical_fields)
        field = logical_fields{i};
        if isfield(cfg,field)
            cfg.(field) = logical(cfg.(field));
        end
    end
    if ~isfield(cfg,'condition_filter') || isempty(cfg.condition_filter)
        cfg.condition_filter = {};
    else
        cfg.condition_filter = cellstr(string(cfg.condition_filter(:).'));
    end

    % Reuse the current timing/PHY validation, then restore the saturation
    % horizon which deliberately has no arrival drain.
    delay_cfg = cfg;
    % validate_experiment_config deliberately keeps the non-saturated delay
    % axis at integer M>=1.  Validate the shared PHY/timing with a neutral
    % integer here without weakening the delay-study contract.
    delay_cfg.M_values = 1;
    delay_cfg.lambda_values = 0;
    delay_cfg.load_modes = {'fixed_packet'};
    delay_cfg.q_coarse = cfg.protocol_q_grids.sf_cf;
    delay_cfg.drain_max_us = 0;
    delay_cfg.tune_warmup_us = cfg.warmup_us;
    delay_cfg.tune_measure_us = cfg.measure_us;
    delay_cfg.tune_drain_max_us = 0;
    delay_cfg.n_tune_runs = cfg.n_tune_runs;
    delay_cfg.n_eval_runs = cfg.n_eval_runs;
    delay_cfg.q_refine_points = max(0,cfg.q_fine_points);
    delay_cfg = validate_experiment_config(delay_cfg);

    derived_fields = {'mmw_conn_slot_slots','mmw_conn_slot_us'};
    for i = 1:numel(derived_fields)
        cfg.(derived_fields{i}) = delay_cfg.(derived_fields{i});
    end
    cfg.arrival_end_us = cfg.warmup_us + cfg.measure_us;
    cfg.sim_hard_end_us = cfg.arrival_end_us;
    cfg.drain_max_us = 0;
end
