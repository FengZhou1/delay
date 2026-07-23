"""
plot_delay.py - 绘制各协议时延曲线（按 λ 汇总到同一张图）

按 λ 读取 results/res_delay_<proto>_lambda_<λ>.mat 各协议分文件，
把同一 λ 下所有协议的曲线合并到一张图。每个指标一张图：
  mean_queue_delay / mean_access_delay / mean_delay

用法:
  python plot_delay.py                 # 自动检测 results/ 下所有 λ，逐个绘图
  python plot_delay.py 5               # 只绘 λ=5
  python plot_delay.py 5 15 30         # 绘多个 λ

输出（覆盖，无时间戳）:
  delay/mean_queue_delay_lam<λ>.png
  delay/mean_access_delay_lam<λ>.png
  delay/mean_delay_lam<λ>.png

说明: 各协议结果可单独改动（重跑某协议即覆盖其分文件），
      再次运行本脚本即可把最新结果合并到大图中。
"""

import os
import sys
import glob
import re

import numpy as np
import scipy.io as sio
from scipy.interpolate import interp1d
import matplotlib
matplotlib.use('Agg')   # 无显示/受限环境也可靠保存图片（不弹窗）
import matplotlib.pyplot as plt
import matplotlib.ticker as ticker


# ===================== 全局学术绘图样式（与吞吐图统一） =====================
plt.rcParams.update({
    'font.family':        ['Arial', 'SimSun'],
    'mathtext.fontset':   'stix',
    'axes.unicode_minus': False,
    'axes.linewidth':     1.2,
    'axes.labelsize':     18,
    'axes.titlesize':     18,
    'xtick.labelsize':    15,
    'ytick.labelsize':    15,
    'xtick.direction':    'in',
    'ytick.direction':    'in',
    'xtick.major.width':  1.0,
    'ytick.major.width':  1.0,
    'xtick.major.size':   5,
    'ytick.major.size':   5,
    'xtick.minor.visible': True,
    'ytick.minor.visible': True,
    'xtick.minor.size':   2.5,
    'ytick.minor.size':   2.5,
    'xtick.top':          True,
    'ytick.right':        True,
    'legend.fontsize':    15,
    'legend.frameon':     True,
    'legend.edgecolor':   '0.6',
    'legend.framealpha':  0.9,
    'legend.fancybox':    False,
    'figure.dpi':         150,
    'savefig.dpi':        600,
    'savefig.bbox':       'tight',
})

# 协议视觉编码（与吞吐图统一）
PROTO_LABELS = {
    'sensing_free_connection_free':   'SF-CF',
    'sensing_free_connection_based':  'SF-CB',
    'sensing_based_connection_free':  'SB-CF',
    'sensing_based_connection_based': 'SB-CB',
    'sub_7G_assisted_clean':          r'S7-AS ($n_{S}=0$)',
    'sub_7G_assisted_busy':           r'S7-AS ($n_{S}=10$)',
}

PROTO_COLORS = {
    'cf_purple':  '#7FB3D1',
    'cb_red':     '#E8A14C',
    's7_green':   '#5E9C5E',
    'annot_gray': '#8C8C8C',
}

LINE_WIDTH  = 3.0
MARKER_SIZE = 8.5
MARKER_EDGE = 1.2

# 固定绘制顺序：mmWave 四协议 + sub7 两协议
PROTO_ORDER = [
    'sensing_free_connection_free',
    'sensing_free_connection_based',
    'sensing_based_connection_free',
    'sensing_based_connection_based',
    'sub_7G_assisted_clean',
    'sub_7G_assisted_busy',
]

METRICS = [
    ('mean_qd',    'mean_queue_delay',  r'Mean Queue Delay ($\mu$s)'),
    ('mean_ad',    'mean_access_delay', r'Mean Access Delay ($\mu$s)'),
    ('mean_delay', 'mean_delay',        r'Mean Delay ($\mu$s)'),
]


def get_protocol_style(proto):
    if 'sub_7G_assisted' in proto:
        return {
            'color':     PROTO_COLORS['s7_green'],
            'marker':    '^',
            'linestyle': (0, (3, 2)) if 'busy' in proto else '-'
        }
    is_sf = 'sensing_free' in proto
    is_cf = 'connection_free' in proto
    if is_cf:
        return {
            'color':     PROTO_COLORS['cf_purple'],
            'marker':    'o' if is_sf else 's',
            'linestyle': '-'
        }
    else:
        return {
            'color':     PROTO_COLORS['cb_red'],
            'marker':    'o' if is_sf else 's',
            'linestyle': (0, (4, 2)) if is_sf else (0, (2, 2))
        }


def get_markevery_indices(x_array, x_max, target=14):
    if len(x_array) == 0:
        return []
    valid_idx = np.where(x_array <= x_max)[0]
    if len(valid_idx) == 0:
        return [0]
    k = min(max(2, target), len(valid_idx))
    idx = np.linspace(valid_idx[0], valid_idx[-1], num=k, dtype=int)
    return np.unique(idx).tolist()


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
            elif v.size == 1:
                out.append(str(v.item()))
            else:
                out.append(str(v))
        else:
            out.append(str(v))
    return out


def _find_intersection_x(x1, y1, x2, y2):
    x_min = max(np.min(x1), np.min(x2))
    x_max = min(np.max(x1), np.max(x2))
    if x_min >= x_max:
        return None
    logx1, logx2 = np.log10(x1), np.log10(x2)
    logy1, logy2 = np.log10(np.maximum(y1, 1e-6)), np.log10(np.maximum(y2, 1e-6))
    x_fine = np.logspace(np.log10(x_min), np.log10(x_max), 800)
    logx_fine = np.log10(x_fine)
    f1 = interp1d(logx1, logy1, kind='linear', bounds_error=False, fill_value=np.nan)
    f2 = interp1d(logx2, logy2, kind='linear', bounds_error=False, fill_value=np.nan)
    diff = f1(logx_fine) - f2(logx_fine)
    if np.all(np.isnan(diff)):
        return None
    sign = np.sign(diff)
    cross_idx = np.where(np.diff(sign) != 0)[0]
    if len(cross_idx) == 0:
        return None
    return x_fine[cross_idx[0]]


def _is_decade(t):
    if t <= 0:
        return False
    n = np.log10(t)
    return abs(n - round(n)) < 1e-6


def _finalize_axis(ax, which, lo, hi, extras=None):
    extras = extras or {}
    set_lim = ax.set_xlim if which == 'x' else ax.set_ylim
    axis = ax.xaxis if which == 'x' else ax.yaxis

    log_lo, log_hi = np.log10(lo), np.log10(hi)
    span = max(log_hi - log_lo, 1e-9)
    margin = 0.03 * span
    v_lo, v_hi = 10 ** (log_lo - margin), 10 ** (log_hi + margin)
    set_lim(v_lo, v_hi)

    specials = [float(lo), float(hi)] + [float(t) for t in extras]

    ticks = {float(lo), float(hi)}
    n_lo = int(np.floor(np.log10(v_lo)))
    n_hi = int(np.ceil(np.log10(v_hi)))
    for n in range(n_lo, n_hi + 1):
        dec = 10.0 ** n
        if all(abs(np.log10(dec) - np.log10(s)) > np.log10(1.3)
               for s in specials if s > 0):
            ticks.add(dec)
    for t in extras:
        ticks.add(float(t))

    sorted_ticks = sorted(t for t in ticks
                          if v_lo * 0.999 <= t <= v_hi * 1.001)

    labels = []
    for t in sorted_ticks:
        matched = None
        for et, el in extras.items():
            if abs(t - float(et)) <= 1e-6:
                matched = el
                break
        if matched is not None:
            labels.append(matched)
        elif _is_decade(t):
            labels.append(rf'$10^{{{int(round(np.log10(t)))}}}$')
        else:
            labels.append(f'{t:g}')

    axis.set_major_locator(ticker.FixedLocator(sorted_ticks))
    axis.set_major_formatter(ticker.FixedFormatter(labels))


def plot_metric(ax, proto_records, metric_key):
    """proto_records: list of dict {proto, Tp, vals}，按 PROTO_ORDER 排序后绘制。"""
    order = {p: i for i, p in enumerate(PROTO_ORDER)}
    proto_records = sorted(proto_records, key=lambda r: order.get(r['proto'], 99))

    x_max = max((np.max(r['Tp']) for r in proto_records), default=1.0)

    for rec in proto_records:
        proto = rec['proto']
        style = get_protocol_style(proto)
        label = PROTO_LABELS.get(proto, proto)
        x = np.atleast_1d(rec['Tp']).astype(float)
        y = np.atleast_1d(rec['vals']).astype(float)
        mask = np.isfinite(y)
        if not np.any(mask):
            continue
        x_plot, y_plot = x[mask], y[mask]
        me = get_markevery_indices(x_plot, x_max=x_plot[-1])
        ax.plot(x_plot, y_plot,
                linestyle=style['linestyle'], color=style['color'],
                linewidth=LINE_WIDTH,
                marker=style['marker'], markersize=MARKER_SIZE,
                markerfacecolor='white', markeredgecolor=style['color'],
                markeredgewidth=MARKER_EDGE, markevery=me, label=label)

    ax.set_xscale('log')

    all_y = np.concatenate([np.atleast_1d(r['vals']) for r in proto_records])
    all_y = all_y[np.isfinite(all_y)]
    if all_y.size == 0:
        return
    all_y_pos = all_y[all_y > 0]
    if all_y_pos.size == 0:
        # 该指标无正值（如低负载下排队时延恒为 0），用线性轴避免 log(0)
        ax.set_yscale('linear')
        y_lo, y_hi = float(np.min(all_y)), float(np.max(all_y))
        if y_lo == y_hi:
            y_lo, y_hi = 0.0, max(y_hi, 1.0)
        pad = 0.05 * (y_hi - y_lo) + 1e-9
        ax.set_ylim(y_lo - pad, y_hi + pad)
    else:
        ax.set_yscale('log')
        y_lo, y_hi = float(np.min(all_y_pos)), float(np.max(all_y_pos))
        if y_lo == y_hi:
            y_lo = y_lo / 2 if y_lo > 0 else 1e-3
        _finalize_axis(ax, 'y', y_lo, y_hi)
    ax.set_autoscaley_on(False)
    ax.set_autoscalex_on(False)

    # CF vs CB 交点标注
    intersections = {}
    for (cf_name, cb_name) in [
        ('sensing_free_connection_free', 'sensing_free_connection_based'),
        ('sensing_based_connection_free', 'sensing_based_connection_based'),
    ]:
        rec_cf = next((r for r in proto_records if r['proto'] == cf_name), None)
        rec_cb = next((r for r in proto_records if r['proto'] == cb_name), None)
        if rec_cf is None or rec_cb is None:
            continue
        xc = find_intersection_for(rec_cf, rec_cb)
        if xc is None:
            continue
        y_cross = interp_logval(rec_cf['Tp'], rec_cf['vals'], xc)
        if y_cross is None or not np.isfinite(y_cross):
            continue
        ax.plot(xc, y_cross, marker='o',
                color=PROTO_COLORS['annot_gray'], markersize=8,
                markerfacecolor=PROTO_COLORS['annot_gray'],
                markeredgewidth=0, zorder=10)
        y_bot = ax.get_ylim()[0]
        ax.plot([xc, xc], [y_cross, y_bot],
                color=PROTO_COLORS['annot_gray'],
                linestyle=(0, (3, 3)), linewidth=1.0, alpha=0.8, zorder=1)
        intersections[round(float(xc), 4)] = f'{xc:.0f}'
        print(f'  Intersection [{PROTO_LABELS[cf_name]} x {PROTO_LABELS[cb_name]}]: Tp={xc:.1f} us')

    x_lo = min((np.min(r['Tp']) for r in proto_records), default=1.0)
    _finalize_axis(ax, 'x', x_lo, x_max, extras=intersections)

    ax.set_xlabel(r'$T_p$ ($\mu$s)')


def find_intersection_for(rec_cf, rec_cb):
    x1, y1 = np.atleast_1d(rec_cf['Tp']).astype(float), np.atleast_1d(rec_cf['vals']).astype(float)
    x2, y2 = np.atleast_1d(rec_cb['Tp']).astype(float), np.atleast_1d(rec_cb['vals']).astype(float)
    mask = np.isfinite(y1) & np.isfinite(y2)
    if np.sum(mask) < 2:
        return None
    return _find_intersection_x(x1[mask], y1[mask], x2[mask], y2[mask])


def interp_logval(x, y, xq):
    x, y = np.atleast_1d(x).astype(float), np.atleast_1d(y).astype(float)
    mask = np.isfinite(y)
    if np.sum(mask) < 2:
        return None
    f = interp1d(np.log10(x[mask]), np.log10(y[mask]), kind='linear',
                 bounds_error=False, fill_value=np.nan)
    return 10 ** f(np.log10(xq))


def load_proto_file(path):
    data = sio.loadmat(path, squeeze_me=True, struct_as_record=False)
    proto = _to_str_list(data.get('proto_name', []))
    proto = proto[0] if proto else os.path.basename(path)
    Tp = np.atleast_1d(data.get('Tp_values_us', np.array([]))).astype(float).flatten()
    rec = {'proto': proto, 'Tp': Tp}
    for key, _, _ in METRICS:
        rec[key] = np.atleast_1d(data.get(key, np.array([]))).astype(float).flatten()
    return rec


def find_lambdas(results_dir):
    """扫描 results/ 下所有 res_delay_<proto>_lambda_<λ>.mat，返回去重排序的 λ 列表。"""
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


def plot_lambda(lambda_val, results_dir, delay_dir):
    files = glob.glob(os.path.join(results_dir, f'res_delay_*_lambda_{lambda_val:g}.mat'))
    if not files:
        print(f'  λ={lambda_val}: 无结果文件，跳过')
        return

    records = [load_proto_file(f) for f in files]
    print(f'  λ={lambda_val}: 找到 {len(records)} 个协议 -> {[r["proto"] for r in records]}')

    for key, fname, ylabel in METRICS:
        fig, ax = plt.subplots(1, 1, figsize=(8, 5))
        proto_records = [{'proto': r['proto'], 'Tp': r['Tp'], 'vals': r[key]} for r in records]
        plot_metric(ax, proto_records, key)
        ax.set_ylabel(ylabel)
        ax.grid(True, which='major', linestyle='-', alpha=0.25, linewidth=0.6)
        ax.grid(True, which='minor', linestyle=':', alpha=0.15, linewidth=0.4)
        ax.legend(loc='best')
        fig.tight_layout(pad=1.5)
        out = os.path.join(delay_dir, f'{fname}_lam{lambda_val:g}.png')
        fig.savefig(out)
        plt.close(fig)
        print(f'    -> {out}')


def main():
    data_dir = os.path.dirname(os.path.abspath(__file__))
    results_dir = os.path.join(data_dir, 'results')
    delay_dir = os.path.join(data_dir, 'delay')
    if not os.path.exists(delay_dir):
        os.makedirs(delay_dir)

    arg_lambdas = [float(a) for a in sys.argv[1:] if _is_num(a)]
    if arg_lambdas:
        lambdas = arg_lambdas
    else:
        lambdas = find_lambdas(results_dir)
        if not lambdas:
            print('未在 results/ 找到任何 res_delay_*_lambda_*.mat 文件')
            sys.exit(1)

    print(f'将绘制 λ = {lambdas}')
    for lv in lambdas:
        plot_lambda(lv, results_dir, delay_dir)
    print('\n完成。图片保存在 delay/ 目录。')


def _is_num(s):
    try:
        float(s)
        return True
    except ValueError:
        return False


if __name__ == '__main__':
    main()
