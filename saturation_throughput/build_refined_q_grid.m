function [fine_q,meta] = build_refined_q_grid(coarse_q,center_index, ...
        n_points,scale_mode,q_floor,neighbor_span)
%BUILD_REFINED_Q_GRID Build a bounded local q grid around a coarse point.
%   Interior points use NEIGHBOR_SPAN coarse points on each side as the
%   bracket. A coarse boundary hit expands geometrically by the number of
%   missing neighbors.
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
    if nargin < 6 || isempty(neighbor_span)
        neighbor_span = 1;
    end

    coarse_q = unique_q_tol(double(coarse_q(:).'));
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
    if neighbor_span < 1 || neighbor_span ~= round(neighbor_span)
        error('build_refined_q_grid:BadNeighborSpan', ...
            'neighbor_span must be a positive integer.');
    end

    center_q = coarse_q(center_index);
    left_available = center_index - 1;
    right_available = numel(coarse_q) - center_index;
    left_index = max(1,center_index-neighbor_span);
    right_index = min(numel(coarse_q),center_index+neighbor_span);
    lo = coarse_q(left_index);
    hi = coarse_q(right_index);

    missing_left = max(0,neighbor_span-left_available);
    missing_right = max(0,neighbor_span-right_available);
    expanded_lower = missing_left > 0;
    expanded_upper = missing_right > 0;
    if missing_left > 0
        ratio = coarse_q(2)/coarse_q(1);
        lo = max(q_floor,coarse_q(1)/(ratio^missing_left));
    end
    if missing_right > 0
        ratio = coarse_q(end)/coarse_q(end-1);
        hi = min(1,coarse_q(end)*(ratio^missing_right));
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
    % LOGSPACE can return (for example) 0.04999999999999999 while the
    % retained coarse centre is exactly 0.05.  Exact UNIQUE would then
    % create two numerically identical neighbours.  Besides wasting a
    % simulation, that can falsely satisfy the stable-neighbour guard.
    fine_q = unique_q_tol([base center_q]);
    fine_q = fine_q(fine_q >= q_floor & fine_q <= 1);
    meta = struct( ...
        'center_q',center_q, ...
        'bracket_left_q',lo, ...
        'bracket_right_q',hi, ...
        'scale_mode',string(mode), ...
        'expanded_lower',expanded_lower, ...
        'expanded_upper',expanded_upper, ...
        'neighbor_span',neighbor_span);
end

function q = unique_q_tol(q)
    q = sort(double(q(:).'));
    if isempty(q)
        return;
    end
    absolute_tolerance = 1e-12;
    keep = [true, diff(q) > absolute_tolerance];
    q = q(keep);
end
