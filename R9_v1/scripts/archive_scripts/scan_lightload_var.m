function scan_lightload_var()
% 临时：扫描轻载所有 checkpoint，找 eval 种子高方差点
    ckpt_dir = fullfile('results_v2','R9_lightload_sweep','checkpoints');
    d = dir(fullfile(ckpt_dir,'*.mat'));
    fprintf('%-38s %-8s %-10s %-12s %-10s %-10s\n', ...
        '条件','best_q','tune_delay','eval_delays','mean','CV');
    fprintf('%s\n', repmat('-',1,100));
    for i=1:numel(d)
        f = fullfile(ckpt_dir, d(i).name);
        try
            s = load(f,'condition'); c = s.condition;
        catch
            continue;
        end
        if isempty(c.evaluation), continue; end
        ev = cellfun(@(x) x.summary.mean_delay_us, c.evaluation);
        ev = ev(isfinite(ev));
        if isempty(ev), continue; end
        m = mean(ev);
        sd = std(ev);
        cv = sd/m;
        % tune delay
        td = NaN;
        if isfield(c.tuning,'grid') && ~isempty(c.tuning.grid)
            gq = [c.tuning.grid.q]; gd = [c.tuning.grid.mean_delay_us];
            mm = abs(gq - c.tuning.best_q) <= 1e-9*max(1,abs(c.tuning.best_q));
            if any(mm)
                v = gd(mm); v = v(isfinite(v));
                if ~isempty(v), td = mean(v); end
            end
        end
        tag = strrep(d(i).name,'.mat','');
        fprintf('%-38s %-8.4g %-10.1f %-12s %-10.1f %-10.2f\n', ...
            tag, c.tuning.best_q, td, mat2str(round(ev,1)), m, cv);
    end
end
