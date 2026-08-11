addpath('C:\Users\Administrator\Documents\delay');
addpath('C:\Users\Administrator\Documents\delay\sf_cb_lightload_study');
p = load('C:\Users\Administrator\Documents\delay\sf_cb_lightload_study\results\20260810_193408\delay_partial_analysis.mat');
fprintf('Done cells: %d\n', numel(p.keys_save));
if ~isempty(p.keys_save)
    fprintf('Keys:\n');
    for i = 1:numel(p.keys_save)
        fprintf('  %2d: %s\n', i, p.keys_save{i});
    end
end
