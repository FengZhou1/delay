function w = build_ula_awv(kind, theta_deg, N, freq, taper)
%BUILD_ULA_AWV Build a normalized 4-element ULA antenna weight vector.
%   kind: 'mrt' for uniform-amplitude conjugate matching, or 'qo' for a
%   broadened tapered beam.  theta_deg is the steering angle.

    if nargin < 5 || isempty(taper)
        taper = [1, 3, 3, 1];
    end
    if numel(taper) ~= N
        error('build_ula_awv:BadTaper','taper length must equal N.');
    end

    lambda = 3e8 / freq;
    d = lambda / 2;
    pos = ((0:N-1) - (N-1)/2) * d;
    k = 2*pi/lambda;
    phase = exp(-1j*k*pos*sin(deg2rad(theta_deg))).';

    switch lower(char(kind))
        case 'mrt'
            amplitude = ones(N,1);
        case 'qo'
            amplitude = double(taper(:));
        otherwise
            error('build_ula_awv:BadKind','kind must be mrt or qo.');
    end

    w = amplitude .* phase;
    w = w / norm(w);
end
