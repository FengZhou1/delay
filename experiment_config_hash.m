function [hash,code_fingerprint] = experiment_config_hash(cfg)
%EXPERIMENT_CONFIG_HASH Hash scientific config plus simulator source code.
% Runtime placement/execution controls are excluded so an interrupted run
% can be resumed by supplying its output_dir without changing the identity.
    canonical=cfg;
    runtime_fields={'output_dir','results_root','resume','parallel','n_workers', ...
        'condition_timeout_s','run_preflight_tests'};
    removable=intersect(fieldnames(canonical),runtime_fields);
    if ~isempty(removable), canonical=rmfield(canonical,removable); end

    source_files={ ...
        'experiment_config_hash.m','default_experiment_config.m', ...
        'validate_experiment_config.m', ...
        'generate_arrival_trace.m','generate_boundary_arrival_trace.m', ...
        'make_manual_arrival_trace.m','prepare_scenario_v2.m', ...
        'sim_utils.m','mmw_timing_config.m','interval_overlap_us.m', ...
        'select_best_q_v2.m','build_refined_q_grid.m', ...
        'experiment_arrival_seed.m', ...
        'finalize_sim_result.m','simulate_aloha_v2.m','simulate_sb_cf_v2.m', ...
        'simulate_sb_cb_v2.m','simulate_s7_v2.m','run_protocol_v2.m', ...
        'run_experiment.m','run_v2_tests.m','validate_aloha_theory_v2.m'};
    source_payload='';
    root=fileparts(mfilename('fullpath'));
    for i=1:numel(source_files)
        path=fullfile(root,source_files{i});
        if exist(path,'file')
            contents=fileread(path);
        else
            contents='<missing>';
        end
        source_payload=[source_payload newline source_files{i} newline contents]; %#ok<AGROW>
    end
    code_fingerprint=sha256_short(source_payload,16);
    payload=struct('configuration',orderfields(canonical), ...
                   'code_fingerprint',code_fingerprint);
    hash=sha256_short(jsonencode(payload),12);
end

function value=sha256_short(text,n_chars)
    md=java.security.MessageDigest.getInstance('SHA-256');
    md.update(uint8(unicode2native(text,'UTF-8')));
    bytes=typecast(md.digest(),'uint8');
    hex=lower(reshape(dec2hex(bytes,2).',1,[]));
    value=hex(1:n_chars);
end
