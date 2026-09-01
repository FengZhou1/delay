function figs = plot_delay_m_comparison(summary, out_dir)
%PLOT_DELAY_M_COMPARISON Plot delay-vs-M curves with fixed-M CF baselines.

    figs = {};
    if isempty(summary)
        return;
    end
    if ~isfolder(out_dir)
        mkdir(out_dir);
    end
    protocols = unique(string(summary.protocol),'stable');
    lambdas = unique(double(summary.lambda_base),'stable');
    colors = lines(max(numel(protocols),1));
    names = containers.Map({'sf_cf','sf_cb','sb_cf','sb_cb', ...
        's7_clean','s7_busy','unslotted'}, ...
        {'SF-CF','SF-CB','SB-CF','SB-CB','S7-Clean','S7-Busy','Unslotted'});

    metrics = {'mean_delay_us','mean_queue_delay_us','mean_access_delay_us'};
    for mi = 1:numel(metrics)
        metric = metrics{mi};
        for li = 1:numel(lambdas)
            lam = lambdas(li);
            fig = figure('Visible','off','Color','w','Position',[100 100 900 560]);
            cleanup = onCleanup(@() close(fig));
            ax = axes(fig); hold(ax,'on'); grid(ax,'on'); box(ax,'on');
            for pi = 1:numel(protocols)
                proto = char(protocols(pi));
                rows = summary(string(summary.protocol)==proto & ...
                    double(summary.lambda_base)==lam,:);
                if isempty(rows)
                    continue;
                end
                is_fixed = ismember('fixed_M_baseline',rows.Properties.VariableNames) && ...
                    all(logical(rows.fixed_M_baseline));
                x = double(rows.M);
                y = double(rows.(metric));
                [x,ord] = sort(x); y = y(ord);
                if is_fixed
                    if isempty(x) || ~isfinite(y(1))
                        continue;
                    end
                    plot(ax,1:6,repmat(y(1),1,6),'--','LineWidth',1.2, ...
                        'Color',colors(pi,:),'DisplayName', ...
                        [names(proto) ' (fixed M=1)']);
                else
                    plot(ax,x,y,'-o','LineWidth',1.25,'MarkerSize',4, ...
                        'Color',colors(pi,:),'DisplayName',names(proto));
                end
            end
            xlabel(ax,'M (TXOP length in conn-slots)');
            ylabel(ax,strrep(metric,'_',' '));
            title(ax,sprintf('%s, \\lambda = %g pkt/STA/s',strrep(metric,'_',' '),lam), ...
                'Interpreter','tex');
            xticks(ax,1:6);
            if strcmp(metric,'mean_delay_us')
                set(ax,'YScale','log');
            end
            legend(ax,'Location','best','Interpreter','none');
            path = fullfile(out_dir,sprintf('%s_lam%g.png',metric,lam));
            exportgraphics(fig,path,'Resolution',180);
            figs{end+1} = path; %#ok<AGROW>
        end
    end
end
