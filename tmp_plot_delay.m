d = 'results_v2/20260810_233451_c63db4ca6e91/checkpoints';
fs = dir(fullfile(d, '*.mat'));
prot = {}; Mv = []; delay = [];
for i = 1:length(fs)
    try
        c = load(fullfile(d, fs(i).name));
        row = c.condition.row;
        if ~row.q_validation_passed, continue; end
        if row.lambda_effective ~= 5, continue; end
        if row.M > 5, continue; end
        prot{end+1} = char(row.protocol);
        Mv(end+1) = row.M;
        delay(end+1) = row.mean_delay_us / 1e3;
    catch
    end
end
T = table(prot', Mv', delay', 'VariableNames', {'protocol','M','delay_ms'});
T = sortrows(T, {'protocol','M'});
disp(T);

% Plot
figure('Position',[100 100 900 500]);
protocols = unique(T.protocol);
colors = lines(length(protocols));
hold on;
leg = {};
for p = 1:length(protocols)
    idx = strcmp(T.protocol, protocols{p});
    plot(T.M(idx), T.delay_ms(idx), 'o-', 'Color', colors(p,:), 'LineWidth', 1.5);
    leg{end+1} = protocols{p};
end
xlabel('M (DATA = M x 162.5us)');
ylabel('Mean E2E Delay (ms)');
title('Delay Comparison, lambda=5 pkt/STA/s');
legend(leg, 'Location', 'northwest');
grid on;
saveas(gcf, 'tmp_delay_lam5.png');
fprintf('Saved to tmp_delay_lam5.png\n');
