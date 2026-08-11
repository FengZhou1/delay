d = 'results_v2/saturation/20260810_212454_4b69aebf1b98/checkpoints';
fs = dir(fullfile(d, '*.mat'));
prot = {}; Mv = []; thru = []; Tp = [];
for i = 1:length(fs)
    try
        c = load(fullfile(d, fs(i).name));
        row = c.condition.row;
        prot{end+1} = char(row.protocol);
        Mv(end+1) = row.M;
        thru(end+1) = row.effective_payload_fraction_mean;
        Tp(end+1) = row.Tp_us;
    catch
    end
end
T = table(prot', Mv', thru', Tp', 'VariableNames', {'protocol','M','S_max','Tp_us'});
T = sortrows(T, {'protocol','M'});
[uprot,~,g] = unique(T.protocol);
fprintf('M=1:6:\n');
fprintf('%-12s','Protocol');
for mm=1:6, fprintf('%8s',sprintf('M=%d',mm)); end
fprintf('\n');
fprintf('%-12s','------------');
for mm=1:6, fprintf('%8s','----'); end
fprintf('\n');
for p = 1:length(uprot)
    fprintf('%-12s',uprot{p});
    idx = g==p;
    sub = T(idx,:);
    for mm=1:6
        r = find(abs(sub.M - mm) < 0.001, 1);
        if ~isempty(r)
            fprintf('%8.4f', sub.S_max(r));
        else
            fprintf('%8s','-');
        end
    end
    fprintf('\n');
end
writetable(T, 'tmp_sat_212454.csv');
fprintf('\nSaved to tmp_sat_212454.csv\n');
