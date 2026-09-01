function q = build_piecewise_q_grid(anchor_q)
%BUILD_PIECEWISE_Q_GRID Build the piecewise ten-point-per-decade q grid.
%   Ten uniformly spaced points are used inside each decade, so low-q
%   details such as 0.004 and the high-q region 0.1..1 are both covered.

    intervals = [1e-4, 1e-3; 1e-3, 1e-2; 1e-2, 1e-1; 1e-1, 1];
    q = zeros(0,1);
    for i = 1:size(intervals,1)
        q = [q; linspace(intervals(i,1), intervals(i,2), 10).']; %#ok<AGROW>
    end
    q = [q; 0.025];
    if nargin >= 1 && isscalar(anchor_q) && isfinite(anchor_q) && ...
            anchor_q > 0 && anchor_q <= 1
        q = [q; anchor_q];
    end
    q = unique(q);
end
