d = 'results_v2/saturation/20260808_143553_1c39fccf09ef/checkpoints';
fs = dir(fullfile(d, '*.mat'));
prot = {}; Mv = []; thru = [];
for i = 1:length(fs)
    try
        c = load(fullfile(d, fs(i).name));
        row = c.condition.row;
        prot{end+1} = char(row.protocol);
        Mv(end+1) = row.M;
        thru(end+1) = row.effective_payload_fraction_mean;
    catch
    end
end
T = table(prot', Mv', thru', 'VariableNames', {'protocol','M','S_max'});
T = sortrows(T, {'protocol','M'});
[uprot,~,g] = unique(T.protocol);
for p = 1:length(uprot)
    idx = g == p;
    fprintf('\n=== %s ===\n', uprot{p});
    sub = T(idx,:);
    for r = 1:height(sub)
        fprintf('  M=%-4g  S_max=%.4f\n', sub.M(r), sub.S_max(r));
    end
end
