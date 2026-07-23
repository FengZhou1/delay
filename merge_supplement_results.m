function outputs = merge_supplement_results(base_dir,rerun_dir)
%MERGE_SUPPLEMENT_RESULTS Merge a filtered rerun into a complete result set.
%   Both summaries are read back from CSV so MATLAB applies identical table
%   text-column types. The complete checkpoint set is also materialized:
%   base checkpoints are copied first and matching rerun checkpoints replace
%   them. This keeps summary plots, theory checks, and diagnostics aligned.

    base_dir = char(base_dir);
    rerun_dir = char(rerun_dir);
    base_summary_path = fullfile(base_dir,'summary.csv');
    rerun_summary_path = fullfile(rerun_dir,'summary.csv');
    if ~isfile(base_summary_path) || ~isfile(rerun_summary_path)
        error('merge_supplement_results:MissingSummary', ...
              'Both base and rerun summary.csv files are required.');
    end

    base_summary = readtable(base_summary_path, ...
        'VariableNamingRule','preserve');
    rerun_summary = readtable(rerun_summary_path, ...
        'VariableNamingRule','preserve');
    if ~isequal(base_summary.Properties.VariableNames, ...
                rerun_summary.Properties.VariableNames)
        error('merge_supplement_results:SchemaMismatch', ...
              'Base and rerun summary schemas do not match.');
    end

    base_summary.result_source = repmat("original_stable", ...
        height(base_summary),1);
    base_summary.rerun_replaced = false(height(base_summary),1);
    rerun_summary.result_source = repmat("corrected_q_rerun", ...
        height(rerun_summary),1);
    rerun_summary.rerun_replaced = true(height(rerun_summary),1);

    base_keys = summary_keys(base_summary);
    rerun_keys = summary_keys(rerun_summary);
    if numel(unique(base_keys)) ~= height(base_summary) || ...
            numel(unique(rerun_keys)) ~= height(rerun_summary)
        error('merge_supplement_results:DuplicateKey', ...
              'Summary keys must be unique within each result set.');
    end

    combined_summary = base_summary;
    for i = 1:height(rerun_summary)
        match = find(base_keys==rerun_keys(i));
        if numel(match)~=1
            error('merge_supplement_results:MergeKeyMismatch', ...
                  'Expected one base row for key %s.',rerun_keys(i));
        end
        combined_summary(match,:) = rerun_summary(i,:);
    end

    combined_path = fullfile(rerun_dir,'combined_summary.csv');
    writetable(combined_summary,combined_path);
    provenance = table(string(base_dir),string(rerun_dir), ...
        height(base_summary),height(rerun_summary), ...
        'VariableNames',{'base_dir','rerun_dir', ...
                         'base_rows','replaced_rows'});
    writetable(provenance,fullfile(rerun_dir, ...
        'supplement_provenance.csv'));

    combined_dir = fullfile(rerun_dir,'combined_view');
    if ~isfolder(combined_dir), mkdir(combined_dir); end
    writetable(combined_summary,fullfile(combined_dir,'summary.csv'));

    rerun_config_path = fullfile(rerun_dir,'config.mat');
    if isfile(rerun_config_path)
        loaded = load(rerun_config_path,'cfg');
        cfg = loaded.cfg;
        cfg.condition_filter = {};
        save(fullfile(combined_dir,'config.mat'),'cfg');
    end

    merge_checkpoint_directory( ...
        fullfile(base_dir,'checkpoints'), ...
        fullfile(rerun_dir,'checkpoints'), ...
        fullfile(combined_dir,'checkpoints'));

    base_verification = fullfile(base_dir,'verification');
    combined_verification = fullfile(combined_dir,'verification');
    if isfolder(base_verification) && ~isfolder(combined_verification)
        copyfile(base_verification,combined_verification);
    end

    analysis = analyze_experiment_v2(combined_dir);
    outputs = struct( ...
        'combined_summary_path',combined_path, ...
        'combined_dir',combined_dir, ...
        'analysis',analysis);
end

function keys = summary_keys(summary)
    keys = string(summary.protocol) + "|" + ...
        string(summary.load_mode) + "|" + ...
        compose("%.15g",double(summary.lambda_base)) + "|" + ...
        compose("%.15g",double(summary.M));
end

function merge_checkpoint_directory(base_dir,rerun_dir,dest_dir)
    if ~isfolder(base_dir) || ~isfolder(rerun_dir)
        error('merge_supplement_results:MissingCheckpoints', ...
              'Base and rerun checkpoint directories are required.');
    end
    if ~isfolder(dest_dir), mkdir(dest_dir); end

    base_files = dir(fullfile(base_dir,'*.mat'));
    rerun_files = dir(fullfile(rerun_dir,'*.mat'));
    base_names = string({base_files.name});
    rerun_names = string({rerun_files.name});
    if any(~ismember(rerun_names,base_names))
        error('merge_supplement_results:UnknownCheckpoint', ...
              'Every rerun checkpoint must replace a base checkpoint.');
    end

    existing = dir(fullfile(dest_dir,'*.mat'));
    existing_names = string({existing.name});
    if any(~ismember(existing_names,base_names))
        error('merge_supplement_results:UnexpectedDestinationFile', ...
              'Combined checkpoint directory contains unexpected files.');
    end

    copy_named_files(base_dir,dest_dir,base_files);
    copy_named_files(rerun_dir,dest_dir,rerun_files);
    merged_files = dir(fullfile(dest_dir,'*.mat'));
    if numel(merged_files) ~= numel(base_files)
        error('merge_supplement_results:CheckpointCountMismatch', ...
              'Combined checkpoint count does not match the base set.');
    end
end

function copy_named_files(source_dir,dest_dir,files)
    for i = 1:numel(files)
        copyfile(fullfile(source_dir,files(i).name), ...
                 fullfile(dest_dir,files(i).name),'f');
    end
end
