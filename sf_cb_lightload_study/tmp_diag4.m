addpath('C:\Users\Administrator\Documents\delay');
addpath('C:\Users\Administrator\Documents\delay\sf_cb_lightload_study');

data = load('C:\Users\Administrator\Documents\delay\sf_cb_lightload_study\results\delay_data.mat');
d = data.data;
r = d.results;
fprintf('results type: %s, size: %s\n', class(r), mat2str(size(r)));
if iscell(r)
    for i = 1:numel(r)
        if isstruct(r{i})
            s = r{i}.summary;
            fprintf('[%d] proto=%s lambda=%.1f M=%d delay=%.3f q=%.4f comp_ratio=%.4f\n', ...
                i, s.protocol, s.lambda_per_node, s.M, s.mean_delay_us, s.q, s.completion_ratio);
        end
    end
elseif isstruct(r)
    for i = 1:numel(r)
        s = r(i).summary;
        fprintf('[%d] proto=%s lambda=%.1f M=%d delay=%.3f q=%.4f comp_ratio=%.4f\n', ...
            i, s.protocol, s.lambda_per_node, s.M, s.mean_delay_us, s.q, s.completion_ratio);
    end
end
