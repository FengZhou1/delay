function rerun_missing_q()
%RERUN_MISSING_Q 独立补跑缺失时延的条件
%   只重跑 stable_fraction<1 或 best_q=NaN 的条件
%   使用新回退逻辑（run_experiment.m 已更新）
%   输出到独立目录，不碰正在运行的进程
%
%   用法: matlab -batch "rerun_missing_q"

    root = fullfile(pwd, '0819_R9_results');
    rerun_root = fullfile(pwd, 'rerun_missing', datestr(now,'yyyymmdd_HHMMSS'));
    if ~isfolder(rerun_root), mkdir(rerun_root); end

    % ===== 定义需要补跑的条件 =====
    % 结构: {old_summary_path, protocol, lambda_base, M}
    jobs = {
        fullfile('results_v2','20260819_162657_0e9b2bf9c602','summary.csv'), 'unslotted', 15, 1
        fullfile('results_v2','20260819_162657_0e9b2bf9c602','summary.csv'), 'unslotted', 45, 5
        fullfile('results_v2','20260819_162657_0e9b2bf9c602','summary.csv'), 's7_clean', 45, 5
        fullfile('results_v2','20260819_202504_079a12a5cc1b','summary.csv'), 'sf_cf', 30, 1
        fullfile('results_v2','20260819_202504_079a12a5cc1b','summary.csv'), 'sf_cf', 45, 1
        fullfile('results_v2','20260819_211902_f4ddfa116f71','summary.csv'), 'unslotted', 15, 1
    };

    % 按旧 summary 分组
    groups = containers.Map('KeyType','char','ValueType','any');
    for i = 1:size(jobs,1)
        old_path = jobs{i,1};
        if ~isKey(groups, old_path)
            groups(old_path) = struct('path',old_path,'jobs',{{}});
        end
        g = groups(old_path);
        g.jobs{end+1} = struct('protocol',jobs{i,2}, 'lambda',jobs{i,3}, 'M',jobs{i,4});
        groups(old_path) = g;
    end

    map_keys = keys(groups);
    for k = 1:numel(map_keys)
        g = groups(map_keys{k});
        fprintf('\n===== 处理组: %s =====\n', g.path);

        % 从旧 summary 所在目录找 config
        old_dir = fileparts(g.path);
        config_path = fullfile(old_dir, 'config.mat');
        if ~isfile(config_path)
            warning('缺少 config.mat: %s，跳过该组', config_path);
            continue;
        end
        old_cfg = load(config_path, 'cfg');
        cfg = old_cfg.cfg;

        % 关键：清空 output_dir 让它生成新目录（避免 hash 校验失败）
        cfg.output_dir = [];
        cfg.resume = false;   % 全新跑
        cfg.run_preflight_tests = false;
        cfg.n_eval_runs = 3;
        cfg.parallel = false;  % 单 worker，避免内存问题
        cfg.n_workers = 1;
        cfg.condition_timeout_s = 1800;

        % 构造 condition_filter
        tags = cell(1, numel(g.jobs));
        for j = 1:numel(g.jobs)
            tags{j} = sprintf('%s_fixed_packet_lam%d_M%d', ...
                g.jobs{j}.protocol, g.jobs{j}.lambda, g.jobs{j}.M);
        end
        cfg.condition_filter = tags;
        fprintf('重跑 %d 个条件: %s\n', numel(tags), strjoin(tags, ', '));

        % 跑
        try
            exp = run_experiment(cfg);
            new_summary_path = fullfile(exp.output_dir,'summary.csv');
            fprintf('完成: %s\n', new_summary_path);

            % 合并回旧 summary
            merge_back(g.path, new_summary_path, tags);
        catch ME
            fprintf('组 %s 运行失败: %s\n', g.path, ME.message);
            for si = 1:numel(ME.stack)
                fprintf('   at %s line %d\n', ME.stack(si).name, ME.stack(si).line);
            end
        end
    end

    fprintf('\n===== 补跑完成 =====\n');
end

function merge_back(old_path, new_path, tags)
%MERGE_BACK 用新结果替换旧 summary 中对应条件的行
    old = readtable(old_path, 'VariableNamingRule', 'preserve');
    new = readtable(new_path, 'VariableNamingRule', 'preserve');

    if isempty(new)
        warning('新结果为空，无法合并');
        return;
    end

    % 备份旧 summary
    backup_path = [old_path '.bak_missingq_' datestr(now,'yyyymmdd_HHMMSS')];
    copyfile(old_path, backup_path);
    fprintf('旧 summary 备份: %s\n', backup_path);

    replaced = 0;
    for i = 1:numel(tags)
        % 解析 tag
        parts = regexp(tags{i}, '^(.*)_fixed_packet_lam(\d+)_M(\d+)$', 'tokens');
        if isempty(parts), continue; end
        proto = parts{1}{1};
        lam = str2double(parts{1}{2});
        M = str2double(parts{1}{3});

        % 在新 summary 中找
        new_mask = string(new.protocol)==string(proto) & ...
                   double(new.lambda_base)==lam & ...
                   double(new.M)==M;
        new_rows = new(new_mask,:);
        if isempty(new_rows)
            fprintf('  新结果中未找到 %s\n', tags{i});
            continue;
        end

        % 在旧 summary 中找
        old_mask = string(old.protocol)==string(proto) & ...
                   double(old.lambda_base)==lam & ...
                   double(old.M)==M;
        if sum(old_mask) ~= 1
            fprintf('  旧 summary 中匹配 %d 行，跳过 %s\n', sum(old_mask), tags{i});
            continue;
        end

        % 替换（保证列一致）
        if ~isequal(old.Properties.VariableNames, new_rows.Properties.VariableNames)
            warning('列名不一致: %s，跳过', tags{i});
            continue;
        end
        old(old_mask,:) = new_rows(1,:);
        replaced = replaced + 1;
        fprintf('  已替换 %s\n', tags{i});
    end

    if replaced > 0
        writetable(old, old_path);
        fprintf('已写回 %s（替换 %d 行）\n', old_path, replaced);
    else
        fprintf('无替换发生，未写回\n');
    end
end
