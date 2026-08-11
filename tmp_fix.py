for fname in ['run_delay_comparison.m', 'run_throughput_comparison.m']:
    with open(fname, 'r') as f:
        content = f.read()
    old = 'datestr(now, yyyymmdd_HHMMSS)'
    new = "datestr(now, 'yyyymmdd_HHMMSS')"
    content = content.replace(old, new)
    with open(fname, 'w') as f:
        f.write(content)
    print(f'{fname}: fixed')
