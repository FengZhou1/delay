function [fine_q,meta] = build_refined_q_grid(coarse_q,center_index, ...
        n_points,scale_mode,q_floor)
%BUILD_REFINED_Q_GRID Build a bounded local q grid around a coarse point.
%   Interior points use their immediate coarse neighbors as the bracket.
%   A coarse boundary hit expands geometrically by one coarse-grid ratio.
%   AUTO uses linear spacing for q>=0.05 and log spacing otherwise.

    if nargin < 3 || isempty(n_points)
        n_points = 5;
    end
    if nargin < 4 || isempty(scale_mode)
        scale_mode = 'auto';
    end
    if nargin < 5 || isempty(q_floor)
        q_floor = 1e-7;
    end

    coarse_q = unique(double(coarse_q(:).'));
    if numel(coarse_q) < 2
        error('build_refined_q_grid:TooFewCoarsePoints', ...
            'At least two distinct coarse q values are required.');
    end
    if center_index < 1 || center_index > numel(coarse_q) || ...
            center_index ~= round(center_index)
        error('build_refined_q_grid:BadCenter', ...
            'center_index must select one coarse-grid point.');
    end
    if n_points < 3 || n_points ~= round(n_points)
        error('build_refined_q_grid:BadPointCount', ...
            'n_points must be an integer greater than or equal to three.');
    end
    if any(~isfinite(coarse_q) | coarse_q <= 0 | coarse_q > 1)
        error('build_refined_q_grid:BadQ', ...
            'coarse_q must lie in the interval (0,1].');
    end

    center_q = coarse_q(center_index);
    expanded_lower = false;
    expanded_upper = false;
    if center_index == 1
        ratio = coarse_q(2)/coarse_q(1);
        lo = max(q_floor,coarse_q(1)/ratio);
        hi = coarse_q(2);
        expanded_lower = lo < center_q;
    elseif center_index == numel(coarse_q)
        ratio = coarse_q(end)/coarse_q(end-1);
        lo = coarse_q(end-1);
        hi = min(1,coarse_q(end)*ratio);
        expanded_upper = hi > center_q;
    else
        lo = coarse_q(center_index-1);
        hi = coarse_q(center_index+1);
    end

    mode = lower(char(scale_mode));
    if strcmp(mode,'auto')
        if lo >= 0.05
            mode = 'linear';
        else
            mode = 'log';
        end
    end
    switch mode
        case 'linear'
            base = linspace(lo,hi,n_points);
        case 'log'
            base = logspace(log10(lo),log10(hi),n_points);
        otherwise
            error('build_refined_q_grid:BadScale', ...
                'scale_mode must be auto, linear, or log.');
    end

    % Retain the coarse center even when it is not exactly one of the
    % equally-spaced values.  This adds at most one point.
    fine_q = unique([base center_q]);
    fine_q = fine_q(fine_q >= q_floor & fine_q <= 1);
    meta = struct( ...
        'center_q',center_q, ...
        'bracket_left_q',lo, ...
        'bracket_right_q',hi, ...
        'scale_mode',string(mode), ...
        'expanded_lower',expanded_lower, ...
        'expanded_upper',expanded_upper);
end
