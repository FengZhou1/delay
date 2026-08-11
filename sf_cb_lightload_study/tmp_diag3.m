%% ===== DIAGNOSTIC 3: Inspect delay_data and check trace generation =====
addpath('C:\Users\Administrator\Documents\delay');
addpath('C:\Users\Administrator\Documents\delay\sf_cb_lightload_study');

% Check delay_data structure
data = load('C:\Users\Administrator\Documents\delay\sf_cb_lightload_study\results\delay_data.mat');
d = data.data;
fprintf('data type: %s\n', class(d));
if isstruct(d)
    fn = fieldnames(d);
    fprintf('data fields (%d): %s\n', numel(fn), strjoin(fn, ', '));
    % Try to find entries
    if isfield(d, 'summary')
        for i = 1:numel(d)
            s = d(i).summary;
            fprintf('[%d] proto=%s lambda=%.1f M=%d delay=%.3f q=%.4f\n', ...
                i, s.protocol, s.lambda_per_node, s.M, s.mean_delay_us, s.q);
        end
    end
elseif iscell(d)
    fprintf('data is cell array of length %d\n', numel(d));
    for i = 1:min(numel(d), 10)
        if isstruct(d{i})
            fn2 = fieldnames(d{i});
            fprintf('[%d] fields: %s\n', i, strjoin(fn2, ', '));
            if isfield(d{i}, 'summary')
                s = d{i}.summary;
                fprintf('  proto=%s λ=%.1f M=%d delay=%.3f q=%.4f\n', ...
                    s.protocol, s.lambda_per_node, s.M, s.mean_delay_us, s.q);
            end
        end
    end
end
