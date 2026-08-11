addpath('C:\Users\Administrator\Documents\delay');
addpath('C:\Users\Administrator\Documents\delay\sf_cb_lightload_study');

data = load('C:\Users\Administrator\Documents\delay\sf_cb_lightload_study\results\delay_data.mat');
d = data.data;
r = d.results;
fprintf('results type: %s, size: %s\n', class(r), mat2str(size(r)));
fprintf('fields: %s\n', strjoin(fieldnames(r), ', '));
% Show first entry fields
fn = fieldnames(r);
for i = 1:numel(fn)
    val = r(1).(fn{i});
    if ischar(val) || (isnumeric(val) && isscalar(val))
        fprintf('  %s = %s\n', fn{i}, mat2str(val));
    else
        fprintf('  %s = [%s]\n', fn{i}, mat2str(size(val)));
    end
end
