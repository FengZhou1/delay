function value = interval_overlap_us(a, b, left, right)
%INTERVAL_OVERLAP_US Length of [a,b) intersected with [left,right).
    value = max(0, min(b, right) - max(a, left));
end
