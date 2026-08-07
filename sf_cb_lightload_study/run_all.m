function run_all(profile)
%RUN_ALL Run the full four-protocol light-load study.
%   run_all                % smoke profile (fast end-to-end check)
%   run_all('analysis')    % full study (delay takes hours, throughput 10-20 min)
%
% Sequence: self-checks, non-saturated delay comparison, saturated
% throughput comparison.  Results are written under
% sf_cb_lightload_study/results/ (delay_data.mat, throughput_data.mat,
% delay_comparison.png, throughput_comparison.png and q tables).

    if nargin < 1 || isempty(profile)
        profile = 'smoke';
    end
    profile = lower(char(profile));
    if ~ismember(profile, {'smoke','analysis'})
        error('run_all:BadProfile', ...
            'Expected profile smoke or analysis.');
    end

    fprintf('=== run_all: profile=%s ===\n', profile);
    run_lightload_study_tests();

    if strcmp(profile,'analysis') && cfg_parallel_available()
        start_parpool_if_needed();
    end

    cfg_delay = default_lightload_sfcb_config(profile,'delay');
    run_delay_comparison(cfg_delay);

    cfg_sat = default_lightload_sfcb_config(profile,'saturation');
    run_throughput_comparison(cfg_sat);

    fprintf('=== run_all: done ===\n');
end

function ok = cfg_parallel_available()
    ok = license('test','Distrib_Computing_Toolbox') && ...
        ~isempty(ver('parallel'));
end

function start_parpool_if_needed()
    if isempty(gcp('nocreate'))
        try
            p = parpool('local');
            fprintf('parpool started with %d workers\n', p.NumWorkers);
        catch ME
            fprintf('parpool failed to start (%s); running serial\n', ...
                ME.message);
        end
    end
end