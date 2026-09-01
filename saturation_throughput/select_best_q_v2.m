function [best_q,best_idx,meta] = select_best_q_v2(grid, ...
        require_stable_neighbors,fallback_self_stable,preferred_neighbor_radius)
%SELECT_BEST_Q_V2 Select a delay-optimal q inside a stable local basin.
%   A grid point is self-stable only when every tuning run was stable and
%   its steady-state mean delay is finite.  When neighbor protection is
%   enabled, the preferred point has PREFERRED_NEIGHBOR_RADIUS stable points
%   on both sides. If that wide basin is unavailable, selection falls back
%   to one stable neighbor on each side and only then to a self-stable point.

    if nargin < 2 || isempty(require_stable_neighbors)
        require_stable_neighbors = false;
    end
    if nargin < 3 || isempty(fallback_self_stable)
        fallback_self_stable = true;
    end
    if nargin < 4 || isempty(preferred_neighbor_radius)
        preferred_neighbor_radius = 1;
    end
    if preferred_neighbor_radius < 1 || ...
            preferred_neighbor_radius ~= round(preferred_neighbor_radius)
        error('select_best_q_v2:BadNeighborRadius', ...
            'preferred_neighbor_radius must be a positive integer.');
    end

    meta = empty_meta();
    meta.preferred_neighbor_radius = preferred_neighbor_radius;
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
    neighbor_stable = stable_with_radius(stable,1);
    preferred_stable = stable_with_radius(stable,preferred_neighbor_radius);

    preferred_indices = find(preferred_stable);
    neighbor_indices = find(neighbor_stable & ~preferred_stable);
    self_indices = find(stable & ~neighbor_stable);
    if require_stable_neighbors
        ranked = [ ...
            rank_candidate_indices(grid,q,preferred_indices), ...
            rank_candidate_indices(grid,q,neighbor_indices), ...
            rank_candidate_indices(grid,q,self_indices)];
    else
        ranked = rank_candidate_indices(grid,q,find(stable));
    end
    meta.ranked_candidate_q = q(ranked);

    if require_stable_neighbors && any(preferred_stable)
        eligible = preferred_stable;
        meta.neighbor_radius_used = preferred_neighbor_radius;
        if preferred_neighbor_radius == 1
            meta.selection_mode = "neighbor_stable";
        else
            meta.selection_mode = "wide_neighbor_stable";
        end
    elseif require_stable_neighbors && any(neighbor_stable)
        eligible = neighbor_stable;
        meta.neighbor_radius_used = 1;
        meta.selection_mode = "neighbor_stable_fallback";
    elseif any(stable) && (~require_stable_neighbors || fallback_self_stable)
        eligible = stable;
        if require_stable_neighbors
            meta.selection_mode = "self_stable_fallback";
        else
            meta.selection_mode = "self_stable";
        end
        meta.neighbor_radius_used = 0;
    else
        meta.selection_mode = "no_stable_q";
        meta.n_self_stable = nnz(stable);
        meta.n_neighbor_stable = nnz(neighbor_stable);
        meta.n_preferred_neighbor_stable = nnz(preferred_stable);
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
    ranked = [candidate,ranked(ranked~=candidate)];
    meta.ranked_candidate_q = q(ranked);
    meta.selected_sorted_index = candidate;
    meta.n_self_stable = nnz(stable);
    meta.n_neighbor_stable = nnz(neighbor_stable);
    meta.n_preferred_neighbor_stable = nnz(preferred_stable);
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

function mask = stable_with_radius(stable,radius)
    mask = false(size(stable));
    for i = 1+radius:numel(stable)-radius
        mask(i) = all(stable(i-radius:i+radius));
    end
end

function ranked = rank_candidate_indices(grid,q,indices)
    if isempty(indices)
        ranked = zeros(1,0);
        return;
    end
    means = double([grid(indices).mean_delay_us]);
    p95 = double([grid(indices).mean_p95_us]);
    waste = double([grid(indices).mean_collision_waste_us]);
    means(~isfinite(means)) = inf;
    p95(~isfinite(p95)) = inf;
    waste(~isfinite(waste)) = inf;
    q_values = q(indices);
    score = [means(:),p95(:),waste(:),q_values(:)];
    [~,order] = sortrows(score,[1 2 3 4]);
    ranked = indices(order);
end

function meta = empty_meta()
    meta = struct( ...
        'selection_mode',"no_stable_q", ...
        'stable_basin_left_q',NaN, ...
        'stable_basin_right_q',NaN, ...
        'q_search_boundary_hit',false, ...
        'selected_sorted_index',NaN, ...
        'n_self_stable',0, ...
        'n_neighbor_stable',0, ...
        'n_preferred_neighbor_stable',0, ...
        'preferred_neighbor_radius',1, ...
        'neighbor_radius_used',0, ...
        'ranked_candidate_q',zeros(1,0));
end



