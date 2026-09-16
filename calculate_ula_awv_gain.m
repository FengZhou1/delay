function gain_db = calculate_ula_awv_gain(w, target_deg, N, freq)
%CALCULATE_ULA_AWV_GAIN Array gain for a supplied ULA AWV.
%   The AWV produced by build_ula_awv already contains the conjugate
%   steering phase (w = conj(a(theta_0))/norm(w)), so the array response
%   must be evaluated WITHOUT conjugating w again: gain = |sum(w_i a_i)|.
%   This matches calculate_ula_mrt_gain, whose beam also peaks exactly at
%   the requested direction.

    if numel(w) ~= N
        error('calculate_ula_awv_gain:BadWeightLength', ...
            'weight vector length must equal N.');
    end
    lambda = 3e8 / freq;
    d = lambda / 2;
    pos = ((0:N-1) - (N-1)/2) * d;
    k = 2*pi/lambda;
    a = exp(1j*k*pos*sin(deg2rad(target_deg))).';
    gain_db = 20*log10(abs(w(:).' * a) + 1e-15);
end
