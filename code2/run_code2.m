function result = run_code2()
%RUN_CODE2 Ideal quasi-omni CTS delay experiment.
    root = fileparts(fileparts(mfilename('fullpath')));
    addpath(root);
    result = run_R10_cts_mode(2);
end
