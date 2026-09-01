function check_txop_modes()
    dirs = {
        'results_v2/smoke_merged_ready'
        'results_v2/R9_merged_logic1'
        'results_v2/R9_merged'
        'results_v2/smoke_merged_batch'
        'results_v2/R9_merged_batch_M_lambda30'
        'results_v2/merged_final'
        'results_v2/lambda_sweep_20260814_060540_597e78800cf0'
    };
    for i=1:numel(dirs)
        f = fullfile(dirs{i},'config.mat');
        if ~isfile(f), fprintf('%-60s 无config\n', dirs{i}); continue; end
        d = load(f,'cfg');
        cfg = d.cfg;
        tm = '?';
        if isfield(cfg,'txop_mode'), tm = cfg.txop_mode; end
        mv = '?'; if isfield(cfg,'M_values'), mv = mat2str(cfg.M_values); end
        lv = '?'; if isfield(cfg,'lambda_values'), lv = mat2str(cfg.lambda_values); end
        fprintf('%-60s txop_mode=%-12s M=%-18s lam=%s\n', dirs{i}, tm, mv, lv);
    end
end
