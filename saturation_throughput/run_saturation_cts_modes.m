function outputs = run_saturation_cts_modes(data_failure_mode, protocols, mode_ids, ...
                                          qo_iso_gains_db)
%RUN_SATURATION_CTS_MODES Run the requested saturation CTS studies.
%   Default mode list is [1 2 4 5]; mode 3 stays available on request.
%   qo_iso_gains_db are the quasi-omni peak gains of mode 5 (default -9 dB).

    if nargin < 1 || isempty(data_failure_mode)
        data_failure_mode = 'txop';
    end
    if nargin < 2
        protocols = {};
    end
    if nargin < 3 || isempty(mode_ids)
        mode_ids = [1 2 4 5];
    end
    if nargin < 4
        qo_iso_gains_db = [];
    end
    mode_ids = double(mode_ids(:).');
    if any(~ismember(mode_ids,1:5))
        error('run_saturation_cts_modes:BadModes', ...
            'mode_ids must be within 1:5.');
    end
    outputs = cell(numel(mode_ids),1);
    this_dir = fileparts(mfilename('fullpath'));
    stamp = char(datetime('now','Format','yyyyMMdd_HHmmss'));
    output_root = fullfile(this_dir,'results_R10_cts',stamp);
    fprintf('Saturation CTS run directory: %s\n',output_root);
    for ii = 1:numel(mode_ids)
        mode_id = mode_ids(ii);
        fprintf('\n######## Saturation CTS mode %d ########\n',mode_id);
        outputs{ii} = run_saturation_cts_mode( ...
            mode_id,data_failure_mode,protocols,output_root, ...
            qo_iso_gains_db);
    end
    fprintf('\n===== SATURATION CTS MODES COMPLETE =====\n');
end
