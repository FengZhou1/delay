v = ver;
names = cellfun(@(x) char(x), {v.Name}, 'UniformOutput', false);
disp(names);
lic = license('test','Distrib_Computing_Toolbox');
disp(['ParallelToolboxLicense: ' num2str(lic)]);
