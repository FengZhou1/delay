function outputs = run_R10_cts_modes(data_failure_mode, protocols, mode_ids, ...
                                   output_root, packet_durations_us, qo_iso_gains_db)
%RUN_R10_CTS_MODES Run the requested CTS modes sequentially.
%   Default mode list is [1 2 4 5]: mode 3 (physical quasi-omni, tapered AWV)
%   is no longer part of the default runs but stays available on request.
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
    mode_ids = double(mode_ids(:).');
    if any(~ismember(mode_ids,1:5))
        error('run_R10_cts_modes:BadModes','mode_ids must be within 1:5.');
    end
    outputs = cell(numel(mode_ids),1);
    project_root = fileparts(mfilename('fullpath'));
    if nargin < 4 || isempty(output_root)
        stamp = char(datetime('now','Format','yyyyMMdd_HHmmss'));
        output_root = fullfile(project_root,'R10_results',stamp);
    else
        output_root = char(output_root);
    end
    if nargin < 5 || isempty(packet_durations_us)
        packet_durations_us = [162.5,650];
    end
    if nargin < 6
        qo_iso_gains_db = [];
    end
    fprintf('R10 run directory: %s\n',output_root);
    for ii = 1:numel(mode_ids)
        mode_id = mode_ids(ii);
        fprintf('\n######## CTS mode %d ########\n',mode_id);
        outputs{ii} = run_R10_cts_mode( ...
            mode_id,data_failure_mode,protocols,output_root, ...
            packet_durations_us,qo_iso_gains_db);
    end
    fprintf('\n===== R10 CTS MODES COMPLETE =====\n');
end
