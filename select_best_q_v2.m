function [best_q,best_idx,meta] = select_best_q_v2(grid, ...
        require_stable_neighbors,fallback_self_stable)
%SELECT_BEST_Q_V2 Select a delay-optimal q inside a stable local basin.
%   A grid point is self-stable only when every tuning run was stable and
%   its steady-state mean delay is finite.  When neighbor protection is
%   enabled, an eligible point must also have stable immediate neighbors on
%   both sides.  If no such interior point exists, the caller may explicitly
%   fall back to the legacy self-stable rule.

    if nargin < 2 || isempty(require_stable_neighbors)
        require_stable_neighbors = false;
    end
    if nargin < 3 || isempty(fallback_self_stable)
        fallback_self_stable = true;
    end

    meta = empty_meta();
    best_q = NaN;
    best_idx = NaN;
    if isempty(grid)
        return;
    end

    q = double([grid.q]);
    [q,order] = sort(q);
    grid = grid(order);
    stable = double([grid.stable_fraction]) >= 1-1e-12 & ...
             isfinite(double([grid.mean_delay_us]));
    neighbor_stable = false(size(stable));
    for i = 2:numel(stable)-1
        neighbor_stable(i) = all(stable(i-1:i+1));
    end

    if require_stable_neighbors && any(neighbor_stable)
        eligible = neighbor_stable;
        meta.selection_mode = "neighbor_stable";
    elseif any(stable) && (~require_stable_neighbors || fallback_self_stable)
        eligible = stable;
        if require_stable_neighbors
            meta.selection_mode = "self_stable_fallback";
        else
            meta.selection_mode = "self_stable";
        end
    else
        meta.selection_mode = "no_stable_q";
        meta.n_self_stable = nnz(stable);
        meta.n_neighbor_stable = nnz(neighbor_stable);
        return;
    end

    idx = find(eligible);
    means = double([grid(idx).mean_delay_us]);
    [~,local] = min(means);
    candidate = idx(local);
    candidate_se = double(grid(candidate).se_delay_us);
    if ~isfinite(candidate_se)
        candidate_se = 0;
    end
    threshold = double(grid(candidate).mean_delay_us) + max(0,candidate_se);
    tied = idx(double([grid(idx).mean_delay_us]) <= threshold);

    if numel(tied) > 1
        p95 = double([grid(tied).mean_p95_us]);
        finite_p95 = isfinite(p95);
        if any(finite_p95)
            min_p95 = min(p95(finite_p95));
            tied = tied(finite_p95 & abs(p95-min_p95) <= ...
                max(eps(min_p95),1e-12));
        end
    end
    if numel(tied) > 1
        waste = double([grid(tied).mean_collision_waste_us]);
        finite_waste = isfinite(waste);
        if any(finite_waste)
            min_waste = min(waste(finite_waste));
            tied = tied(finite_waste & abs(waste-min_waste) <= ...
                max(eps(min_waste),1e-12));
        end
    end
    if numel(tied) > 1
        % Within one standard error and with equal tail/collision evidence,
        % prefer the less aggressive access probability.
        [~,k] = min(q(tied));
        candidate = tied(k);
    else
        candidate = tied(1);
    end

    best_q = q(candidate);
    best_idx = order(candidate);
    meta.selected_sorted_index = candidate;
    meta.n_self_stable = nnz(stable);
    meta.n_neighbor_stable = nnz(neighbor_stable);
    meta.q_search_boundary_hit = candidate == 1 || candidate == numel(q);

    left = candidate;
    while left > 1 && stable(left-1)
        left = left-1;
    end
    right = candidate;
    while right < numel(q) && stable(right+1)
        right = right+1;
    end
    meta.stable_basin_left_q = q(left);
    meta.stable_basin_right_q = q(right);
end

function meta = empty_meta()
    meta = struct( ...
        'selection_mode',"no_stable_q", ...
        'stable_basin_left_q',NaN, ...
        'stable_basin_right_q',NaN, ...
        'q_search_boundary_hit',false, ...
        'selected_sorted_index',NaN, ...
        'n_self_stable',0, ...
        'n_neighbor_stable',0);
end
