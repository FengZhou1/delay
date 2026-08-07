p = load('C:/Users/Administrator/Documents/delay/sf_cb_lightload_study/results/delay_partial_smoke.mat');
disp(fieldnames(p));
fprintf('keys: %d rows: %d qrows: %d\n', numel(p.keys_save), numel(p.rows_save), numel(p.qrows_save));
