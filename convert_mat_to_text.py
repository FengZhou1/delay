"""
convert_mat_to_text.py — 将仿真 .mat 结果转换为 LLM 可读的文本文件

适配新的分文件格式 results/res_delay_<proto>_lambda_<λ>.mat：
  每个文件含单个协议、单个 λ 的结果。

用法:
  python convert_mat_to_text.py                  # 扫描 results/ 全部 λ，每个 λ 输出一份汇总
  python convert_mat_to_text.py 5                 # 只转 λ=5 的所有协议
  python convert_mat_to_text.py results/res_delay_xxx_lambda_5.mat  # 转换单个文件
  python convert_mat_to_text.py 5 -o out.txt      # 指定输出路径

输出:
  results/delay_summary_lam<λ>.txt   (按 λ 合并所有协议)
"""

import os
import sys
import glob
import re

import numpy as np
import scipy.io as sio


PROTO_LABELS = {
    'sensing_free_connection_free':    'SF-CF',
    'sensing_free_connection_based':   'SF-CB',
    'sensing_based_connection_free':   'SB-CF',
    'sensing_based_connection_based':  'SB-CB',
    'sub_7G_assisted_clean':           'S7-AS (nS=0)',
    'sub_7G_assisted_busy':            'S7-AS (nS=10)',
}

PROTO_ORDER = [
    'sensing_free_connection_free',
    'sensing_free_connection_based',
    'sensing_based_connection_free',
    'sensing_based_connection_based',
    'sub_7G_assisted_clean',
    'sub_7G_assisted_busy',
]


def _to_str_list(x):
    arr = np.atleast_1d(x)
    out = []
    for v in arr:
        if isinstance(v, bytes):
            out.append(v.decode('utf-8', errors='ignore'))
        elif isinstance(v, str):
            out.append(v)
        elif isinstance(v, np.ndarray):
            if v.dtype.kind in {'U', 'S'}:
                out.append(''.join(v.tolist()) if v.ndim > 0 else str(v.item()))
            else:
                out.append(str(v))
        else:
            out.append(str(v))
    return out


def load_proto_file(path):
    data = sio.loadmat(path, squeeze_me=True, struct_as_record=False)
    proto = _to_str_list(data.get('proto_name', []))
    proto = proto[0] if proto else os.path.basename(path)
    rec = {
        'proto':  proto,
        'lambda': float(data.get('lambda_val', np.nan)),
        'M':      np.atleast_1d(data.get('M_VALUES', np.array([]))).astype(float).flatten(),
        'Tp':     np.atleast_1d(data.get('Tp_values_us', np.array([]))).astype(float).flatten(),
        'mean_qd':    np.atleast_1d(data.get('mean_qd', np.array([]))).astype(float).flatten(),
        'mean_ad':    np.atleast_1d(data.get('mean_ad', np.array([]))).astype(float).flatten(),
        'mean_delay': np.atleast_1d(data.get('mean_delay', np.array([]))).astype(float).flatten(),
        'mean_qlen':  np.atleast_1d(data.get('mean_qlen', np.array([]))).astype(float).flatten(),
        'best_q':     np.atleast_1d(data.get('best_q', np.array([]))).astype(float).flatten(),
        'n_runs':   int(float(data.get('n_runs', 1))),
        'sim_time': float(data.get('sim_time_total_us', np.nan)),
        'p_arr':    float(data.get('p_arr', np.nan)),
        'slot_us':  float(data.get('slot_us', np.nan)),
    }
    return rec


def find_lambdas(results_dir):
    pattern = re.compile(r'res_delay_.+_lambda_(.+)\.mat$')
    lambdas = []
    for f in glob.glob(os.path.join(results_dir, 'res_delay_*_lambda_*.mat')):
        m = pattern.match(os.path.basename(f))
        if m:
            try:
                lambdas.append(float(m.group(1)))
            except ValueError:
                pass
    return sorted(set(lambdas))


def convert_lambda(records, out_lines):
    """转换同一 λ 下所有协议的记录。records: list of dict。"""
    if not records:
        return
    lv = records[0]['lambda']
    order = {p: i for i, p in enumerate(PROTO_ORDER)}
    records = sorted(records, key=lambda r: order.get(r['proto'], 99))

    rec0 = records[0]
    n_runs = rec0['n_runs']
    sim_time = rec0['sim_time']
    M = rec0['M']
    Tp = rec0['Tp']

    out_lines.append(f'λ = {lv:g} pkt/sta/s')
    out_lines.append(f'  simulation time: {sim_time:.1e} us,  averaged over {n_runs} runs')
    out_lines.append(f'  M values: {", ".join(f"{m:.2f}" for m in M)}')
    out_lines.append(f'  Tp values (us): {", ".join(f"{tp:.0f}" for tp in Tp)}')
    out_lines.append('')

    out_lines.append(f'  {"Protocol":<20} {"M":>6} {"Tp(us)":>8} {"q*":>8} '
                     f'{"MeanQ":>10} {"MeanA":>10} {"MeanD":>10} {"QLen":>10}')
    out_lines.append(f'  {"-"*20} {"-"*6} {"-"*8} {"-"*8} {"-"*10} {"-"*10} {"-"*10} {"-"*10}')
    for r in records:
        lbl = PROTO_LABELS.get(r['proto'], r['proto'])
        n_M = len(r['M'])
        for mi in range(n_M):
            v = r['mean_delay'][mi]
            line = (f'  {lbl:<20} {r["M"][mi]:>6.2f} {r["Tp"][mi]:>8.0f} '
                    f'{r["best_q"][mi]:>8.4f} ')
            if np.isfinite(v):
                line += (f'{r["mean_qd"][mi]:>10.1f} {r["mean_ad"][mi]:>10.1f} '
                         f'{v:>10.1f} {r["mean_qlen"][mi]:>10.2f}')
            else:
                line += f'{"N/A":>10} {"N/A":>10} {"N/A":>10} {"N/A":>10}'
            out_lines.append(line)
    out_lines.append('')

    out_lines.append(f'  --- Per-protocol optimal M (min mean delay) ---')
    out_lines.append(f'  {"Protocol":<20} {"M_opt":>6} {"Tp_opt(us)":>10} {"MeanD":>10} {"QLen":>10} {"q*":>8}')
    out_lines.append(f'  {"-"*20} {"-"*6} {"-"*10} {"-"*10} {"-"*10} {"-"*8}')
    for r in records:
        lbl = PROTO_LABELS.get(r['proto'], r['proto'])
        y = r['mean_delay']
        valid = np.isfinite(y)
        if np.any(valid):
            best_mi = int(np.nanargmin(y))
            out_lines.append(f'  {lbl:<20} {r["M"][best_mi]:>6.2f} {r["Tp"][best_mi]:>10.0f} '
                             f'{y[best_mi]:>10.1f} {r["mean_qlen"][best_mi]:>10.2f} '
                             f'{r["best_q"][best_mi]:>8.4f}')
        else:
            out_lines.append(f'  {lbl:<20} {"N/A":>6} {"N/A":>10} {"N/A":>10} {"N/A":>10} {"N/A":>8}')
    out_lines.append('')

    out_lines.append(f'  --- CF vs CB crossover Tp (us) ---')
    out_lines.append(f'  {"pair":<24} {"Tp_cross":>10}')
    out_lines.append(f'  {"-"*24} {"-"*10}')
    for (cf_name, cb_name) in [
        ('sensing_free_connection_free', 'sensing_free_connection_based'),
        ('sensing_based_connection_free', 'sensing_based_connection_based'),
    ]:
        rcf = next((r for r in records if r['proto'] == cf_name), None)
        rcb = next((r for r in records if r['proto'] == cb_name), None)
        tp = _find_crossover(rcf, rcb) if (rcf and rcb) else None
        pair = PROTO_LABELS.get(cf_name, cf_name) + " x " + PROTO_LABELS.get(cb_name, cb_name)
        out_lines.append(f'  {pair:<24} {f"{tp:.0f}" if tp is not None else "N/A":>10}')
    out_lines.append('')


def _find_crossover(rcf, rcb):
    Tp1, y1 = rcf['Tp'], rcf['mean_delay']
    Tp2, y2 = rcb['Tp'], rcb['mean_delay']
    if len(Tp1) != len(Tp2):
        return None
    mask = np.isfinite(y1) & np.isfinite(y2)
    if np.sum(mask) < 2:
        return None
    x, a, b = Tp1[mask], y1[mask], y2[mask]
    diff = a - b
    sign = np.sign(diff)
    cross_idx = np.where(np.diff(sign) != 0)[0]
    if len(cross_idx) == 0:
        return None
    i = cross_idx[0]
    if i + 1 >= len(x):
        return None
    t = -diff[i] / (diff[i + 1] - diff[i] + 1e-30)
    return x[i] + t * (x[i + 1] - x[i])


def main():
    data_dir = os.path.dirname(os.path.abspath(__file__))
    results_dir = os.path.join(data_dir, 'results')

    output_path = None
    target_lambda = None
    single_file = None
    for i, a in enumerate(sys.argv[1:]):
        if a == '-o' and i + 2 < len(sys.argv):
            output_path = sys.argv[i + 2]
            continue
        if _is_num(a):
            target_lambda = float(a)
        elif os.path.exists(a) or os.path.exists(os.path.join(data_dir, a)):
            single_file = a if os.path.exists(a) else os.path.join(data_dir, a)

    if single_file:
        rec = load_proto_file(single_file)
        out_lines = []
        out_lines.append(f'802.11bq Delay Results - Single File')
        out_lines.append(f'Source: {os.path.basename(single_file)}')
        out_lines.append('')
        convert_lambda([rec], out_lines)
        if output_path is None:
            output_path = os.path.join(results_dir,
                f'delay_summary_{os.path.splitext(os.path.basename(single_file))[0]}.txt')
    else:
        if target_lambda is not None:
            lambdas = [target_lambda]
        else:
            lambdas = find_lambdas(results_dir)
        if not lambdas:
            print('No res_delay_*_lambda_*.mat files found in results/')
            sys.exit(1)

        out_lines = []
        out_lines.append(f'802.11bq Channel Access Simulation - Delay Results')
        out_lines.append(f'lambda values: {", ".join(f"{lv:g}" for lv in lambdas)}')
        out_lines.append('')
        for lv in lambdas:
            files = glob.glob(os.path.join(results_dir, f'res_delay_*_lambda_{lv:g}.mat'))
            records = [load_proto_file(f) for f in files]
            if not records:
                continue
            out_lines.append(f'{"="*90}')
            convert_lambda(records, out_lines)
        if output_path is None:
            if len(lambdas) == 1:
                output_path = os.path.join(results_dir, f'delay_summary_lam{lambdas[0]:g}.txt')
            else:
                output_path = os.path.join(results_dir, 'delay_summary_all.txt')

    os.makedirs(os.path.dirname(output_path) or '.', exist_ok=True)
    with open(output_path, 'w', encoding='utf-8') as f:
        f.write('\n'.join(out_lines))
    print(f'Output: {output_path}')
    print(f'Lines: {len(out_lines)}')


def _is_num(s):
    try:
        float(s)
        return True
    except ValueError:
        return False


if __name__ == '__main__':
    main()
