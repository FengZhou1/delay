function out = merge_r9_boundary(r9_dir, out_dir)
%MERGE_R9_BOUNDARY Merge boundary-supplement results into R9 and plot.
%
%   Reads the R9 summary.csv, replaces the boundary-hit rows with the
%   supplement evals saved by run_boundary_q_supplement.m, then writes the
%   merged table and delay figures into OUT_DIR (default results_v2/R9_merged).

    if nargin < 1 || isempty(r9_dir)
        r9_dir = fullfile('results_v2','20260813_003419_e174efb1074f');
    end
    if nargin < 2 || isempty(out_dir)
        out_dir = fullfile('results_v2','R9_merged');
    end
    if ~isfolder(out_dir), mkdir(out_dir); end

    sup_dirs = {'supplement_work','supplement_work_pointfix','supplement_work_unsl30','supplement_work_unsl_orig'};
    infos = {};
    found_any = false;
    for di = 1:numel(sup_dirs)
        sup_path = fullfile(out_dir,sup_dirs{di},'supplement_results.mat');
        if ~isfile(sup_path)
            continue;
        end
        sup = load(sup_path,'info');
        infos{end+1} = sup.info; %#ok<AGROW>
        found_any = true;
    end
    if ~found_any
        error('merge_r9_boundary:NoSupplement', ...
            'No supplement results found under %s (run run_boundary_q_supplement.m first).', ...
            out_dir);
    end

    summary = readtable(fullfile(r9_dir,'summary.csv'),'VariableNamingRule','preserve');
    n_replaced = 0;
    reports = [];
    for ii = 1:numel(infos)
        info = infos{ii};
        new_rows = info.new_rows;
        if ~isempty(new_rows)
            for i = 1:height(new_rows)
                proto = string(new_rows.protocol(i));
                lm = string(new_rows.load_mode(i));
                lb = double(new_rows.lambda_base(i));
                mv = double(new_rows.M(i));
                mask = string(summary.protocol)==proto & ...
                       string(summary.load_mode)==lm & ...
                       double(summary.lambda_base)==lb & ...
                       double(summary.M)==mv;
                idx = find(mask);
                if isempty(idx)
                    warning('merge_r9_boundary:RowNotFound', ...
                        'No R9 row for %s lam%g M%d; appending.',proto,lb,mv);
                    summary = [summary; new_rows(i,:)]; %#ok<AGROW>
                else
                    summary(idx,:) = new_rows(i,:);
                end
                n_replaced = n_replaced + 1;
            end
        end
        if isfield(info,'report') && ~isempty(info.report)
            if isempty(reports)
                reports = info.report;
            else
                reports = [reports; info.report]; %#ok<AGROW>
            end
        end
    end
    writetable(summary, fullfile(out_dir,'summary.csv'));

    % Normalize Tp_us to real conn_slot (162.5 us) regardless of source data
    if ismember('Tp_us', summary.Properties.VariableNames) && ismember('M', summary.Properties.VariableNames)
        cfg_file = fullfile(out_dir, 'config.mat');
        if isfile(cfg_file)
            cfg_data = load(cfg_file, 'cfg');
            if isfield(cfg_data, 'cfg')
                conn_slot = real_conn_slot_us(cfg_data.cfg);
            else
                conn_slot = 162.5;
            end
        else
            conn_slot = 162.5;
        end
        summary.Tp_us = conn_slot * double(summary.M);
        writetable(summary, fullfile(out_dir,'summary.csv'));
        fprintf('  Tp_us normalized to %.1f * M\n', conn_slot);
    end
    copyfile(fullfile(r9_dir,'config.mat'), fullfile(out_dir,'config.mat'),'f');
    if isfile(fullfile(r9_dir,'scenario.mat'))
        copyfile(fullfile(r9_dir,'scenario.mat'), fullfile(out_dir,'scenario.mat'),'f');
    end
    if ~isempty(reports)
        writetable(reports, fullfile(out_dir,'boundary_supplement_report.csv'));
    end

    fig_dir = fullfile(out_dir,'figures');
    if ~isfolder(fig_dir), mkdir(fig_dir); end
    figs = plot_merged(summary, fig_dir);

    write_readme(out_dir, r9_dir, infos, n_replaced);

    out = struct('out_dir',out_dir,'n_replaced',n_replaced, ...
        'figure_paths',{figs});
    fprintf('=== R9_merged ready: %d rows replaced, %d figures -> %s ===\n', ...
        n_replaced, numel(figs), out_dir);
end

function figs = plot_merged(summary, fig_dir)
    figs = {};
    protocols = unique(string(summary.protocol),'stable');
    lambdas = unique(double(summary.lambda_base),'stable');
    colors = lines(max(numel(protocols),1));
    names = protocol_display_names();

    metrics = {'mean_delay_us','mean_queue_delay_us','mean_access_delay_us'};
    for mi = 1:numel(metrics)
        metric = metrics{mi};
        for li = 1:numel(lambdas)
            lam = lambdas(li);
            fig = figure('Visible','off','Color','w', ...
                'Position',[100 100 900 560]);
            cleanup = onCleanup(@() close(fig));
            ax = axes(fig); hold(ax,'on'); grid(ax,'on'); box(ax,'on');
            for pi = 1:numel(protocols)
                mask = string(summary.protocol)==protocols(pi) & ...
                       double(summary.lambda_base)==lam;
                x = double(summary.M(mask));
                y = double(summary.(metric)(mask));
                [x,ord] = sort(x); y = y(ord);
                if isempty(x), continue; end
                plot(ax,x,y,'-o','LineWidth',1.25,'MarkerSize',4, ...
                    'Color',colors(pi,:),'DisplayName',names(protocols(pi)));
            end
            xlabel(ax,'M (TXOP length in conn-slots)');
            ylabel(ax,metric_label(metric));
            title(ax,sprintf('%s, \\lambda = %g pkt/STA/s',metric_title(metric),lam), ...
                'Interpreter','tex');
            xticks(ax,unique(double(summary.M)));
            if strcmp(metric,'mean_delay_us')
                set(ax,'YScale','log');
            end
            legend(ax,'Location','best','Interpreter','none');
            path = fullfile(fig_dir,sprintf('%s_lam%g.png',metric,lam));
            exportgraphics(fig,path,'Resolution',180);
            figs{end+1} = path; %#ok<AGROW>
        end
    end

    % combined tiled figure for mean delay (both lambdas, R9 style)
    fig = figure('Visible','off','Color','w','Position',[100 100 1200 560]);
    cleanup = onCleanup(@() close(fig));
    t = tiledlayout(fig,1,numel(lambdas),'TileSpacing','compact','Padding','compact');
    for li = 1:numel(lambdas)
        lam = lambdas(li);
        ax = nexttile(t); hold(ax,'on'); grid(ax,'on'); box(ax,'on');
        for pi = 1:numel(protocols)
            mask = string(summary.protocol)==protocols(pi) & ...
                   double(summary.lambda_base)==lam;
            x = double(summary.M(mask));
            y = double(summary.mean_delay_us(mask));
            [x,ord] = sort(x); y = y(ord);
            if isempty(x), continue; end
            plot(ax,x,y,'-o','LineWidth',1.25,'MarkerSize',4, ...
                'Color',colors(pi,:),'DisplayName',names(protocols(pi)));
        end
        set(ax,'YScale','log');
        xlabel(ax,'M'); ylabel(ax,'Mean end-to-end delay (us)');
        title(ax,sprintf('\\lambda = %g pkt/STA/s',lam),'Interpreter','tex');
        xticks(ax,unique(double(summary.M)));
        if li==1, legend(ax,'Location','best','Interpreter','none'); end
    end
    title(t,'R9 merged: mean end-to-end delay vs M (boundary points re-scanned)');
    path = fullfile(fig_dir,'delay_by_M.png');
    exportgraphics(fig,path,'Resolution',180);
    figs{end+1} = path; %#ok<AGROW>
end

function names = protocol_display_names()
    names = containers.Map({'sf_cf','sf_cb','sb_cf','sb_cb', ...
        's7_clean','s7_busy','unslotted'}, ...
        {'SF-CF','SF-CB','SB-CF','SB-CB','S7-Clean','S7-Busy','Unslotted'});
end

function label = metric_label(metric)
    switch metric
        case 'mean_delay_us', label = 'Mean end-to-end delay (us)';
        case 'mean_queue_delay_us', label = 'Mean queue delay (us)';
        case 'mean_access_delay_us', label = 'Mean access delay (us)';
        otherwise, label = metric;
    end
end

function title_str = metric_title(metric)
    switch metric
        case 'mean_delay_us', title_str = 'Mean end-to-end delay';
        case 'mean_queue_delay_us', title_str = 'Mean queue delay';
        case 'mean_access_delay_us', title_str = 'Mean access delay';
        otherwise, title_str = metric;
    end
end

function write_readme(out_dir, r9_dir, infos, n_replaced)
    fid = fopen(fullfile(out_dir,'README.md'),'w');
    if fid < 0, return; end
    cleanup = onCleanup(@() fclose(fid));
    fprintf(fid,'# R9_merged\n\n');
    fprintf(fid,'Merged delay results: R9 (`%s`) plus boundary-q supplement re-runs.\n\n', ...
        r9_dir);
    n_targets = 0;
    for ii = 1:numel(infos)
        if isfield(infos{ii},'n_targets')
            n_targets = n_targets + infos{ii}.n_targets;
        end
    end
    fprintf(fid,'- Supplement target conditions: %d\n', n_targets);
    fprintf(fid,'- Rows replaced by supplement evals: %d\n', n_replaced);
    fprintf(fid,'- Supplement scan: 3 seeds x 3 tune runs, a q counts as stable only\n');
    fprintf(fid,'  when all 3 seeds are stable; eval accepts completion>=0.95 and\n');
    fprintf(fid,'  stable; otherwise falls back to the next stable q to the left.\n\n');
    fprintf(fid,'## Files\n\n');
    fprintf(fid,'- `summary.csv`: merged condition table (supplement rows updated)\n');
    fprintf(fid,'- `boundary_supplement_report.csv`: old vs new q/delay per re-tuned point\n');
    fprintf(fid,'- `figures/`: delay-by-M curves for both lambda values\n');
    fprintf(fid,'- `supplement_work/supplement_results.mat`: boundary supplement data\n');
    fprintf(fid,'- `supplement_work_pointfix/supplement_results.mat`: point-fix data\n');
    fprintf(fid,'- `supplement_work_unsl30/supplement_results.mat`: unslotted lam30 point-fix\n');
    fprintf(fid,'- `supplement_work_unsl_orig/supplement_results.mat`: unslotted original-flow re-run\n');
end
