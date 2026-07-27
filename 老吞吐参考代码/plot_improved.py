import matplotlib.pyplot as plt
import numpy as np
import scipy.io as sio
from scipy.interpolate import PchipInterpolator
from scipy.optimize import brentq
import os
from datetime import datetime
from matplotlib.ticker import MultipleLocator
from matplotlib.lines import Line2D


# ===================== 全局学术绘图风格（改字体前那一版） =====================
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

timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')

data_dir = os.path.dirname(os.path.abspath(__file__))
results_dir = os.path.join(data_dir, 'results')

protocols = [
    'sensing_free_connection_free',
    'sensing_free_connection_based',
    'sensing_based_connection_free',
    'sensing_based_connection_based',
    'sub_7G_assisted_clean',
    'sub_7G_assisted_busy'
]

display_names = [
    'SF-CF',
    'SF-CB',
    'SB-CF',
    'SB-CB',
    'S7-AS ($n_{S}=0$)',
    'S7-AS ($n_{S}=10$)'
]

# ----------------------------------------------------------------------
# ★ 科研低饱和度配色（向参考图靠拢、加深版）
# ----------------------------------------------------------------------
SCIENTIFIC_COLORS = {
    'cf_purple':  '#7FB3D1',
    'cb_red':     '#E8A14C',
    's7_green':   '#5E9C5E',
    'annot_gray': '#8C8C8C',
    'text_dark':  '#262626',
}

# ★ 严格控制 14 个标记
TARGET_MARKERS = 14
INTERP_POINTS  = (TARGET_MARKERS + 1) * 15
MARK_EVERY     = 15

# ★ 视觉强调（海报级放大）
LINE_WIDTH     = 4.5     # 原 3.6
MARKER_SIZE    = 12.0    # 原 10.0
MARKER_EDGE    = 1.8     # 原 1.5


def get_protocol_style(proto):
    if 'sub_7G_assisted' in proto:
        return {
            'color':     SCIENTIFIC_COLORS['s7_green'],
            'marker':    '^',
            'linestyle': '-' if 'clean' in proto else ':'
        }

    is_sf = 'sensing_free' in proto
    is_cf = 'connection_free' in proto

    if is_cf:
        linestyle = '-'
    elif is_sf:
        linestyle = '--'
    else:
        linestyle = ':'

    return {
        'color':     SCIENTIFIC_COLORS['cf_purple'] if is_cf else SCIENTIFIC_COLORS['cb_red'],
        'marker':    'o' if is_sf else 's',
        'linestyle': linestyle,
    }


def load_mat_safe(filepath, *var_names):
    if not os.path.isfile(filepath):
        return None
    data = sio.loadmat(filepath, squeeze_me=True, struct_as_record=False)
    result = {}
    for v in var_names:
        if v in data:
            result[v] = data[v]
        else:
            result[v] = None
    return result


def extract_field(obj, field_name):
    if obj is None:
        return None

    if isinstance(obj, dict):
        return obj.get(field_name, None)

    if isinstance(obj, np.void):
        try:
            return obj[field_name]
        except Exception:
            return None

    if hasattr(obj, field_name):
        return getattr(obj, field_name)

    if isinstance(obj, tuple):
        if field_name == 'th' and len(obj) >= 1:
            return obj[0]
        return None

    if isinstance(obj, np.ndarray):
        if obj.dtype.names and field_name in obj.dtype.names:
            return obj[field_name]
        if obj.size == 1:
            try:
                return extract_field(obj.item(), field_name)
            except Exception:
                return None

    if hasattr(obj, 'item'):
        try:
            return extract_field(obj.item(), field_name)
        except Exception:
            return None

    return None


def smooth_curve(x, y, points=INTERP_POINTS):
    x = np.asarray(x).flatten()
    y = np.asarray(y).flatten()

    valid = np.isfinite(x) & np.isfinite(y)
    x = x[valid]
    y = y[valid]

    if x.size < 3:
        return x, y, None

    order = np.argsort(x)
    x_sorted = x[order]
    y_sorted = y[order]

    x_unique, idx = np.unique(x_sorted, return_index=True)
    y_unique = y_sorted[idx]

    if x_unique.size < 3:
        return x_unique, y_unique, None

    x_new = np.linspace(x_unique.min(), x_unique.max(), points)
    interp = PchipInterpolator(x_unique, y_unique)
    y_new = interp(x_new)
    return x_new, y_new, interp


# =========================================================================
# Throughput vs Tp only (with CF/CB intersection annotation)
# =========================================================================
fig, ax = plt.subplots(1, 1, figsize=(8, 5))

legend_entries = []
throughput_interps = {}

for i, proto in enumerate(protocols):
    filepath = os.path.join(results_dir, f'res_M_{proto}.mat')
    if not os.path.isfile(filepath):
        filepath = os.path.join(data_dir, f'res_M_{proto}.mat')
    loaded = load_mat_safe(filepath, 'res_M', 'M_VALUES')
    if loaded is None:
        continue

    res_M = loaded['res_M']
    M_VALUES = np.atleast_1d(loaded['M_VALUES']).flatten()

    th = extract_field(res_M, 'th')
    if th is None:
        continue

    th = np.atleast_1d(th).flatten()
    T_p_VALUES = M_VALUES * 200
    style = get_protocol_style(proto)

    x_th, y_th, interp_func = smooth_curve(T_p_VALUES, th)

    if interp_func is not None:
        throughput_interps[proto] = interp_func

    ax.plot(x_th, y_th,
            linestyle=style['linestyle'],
            marker=style['marker'],
            color=style['color'],
            linewidth=LINE_WIDTH,
            markersize=MARKER_SIZE,
            markeredgewidth=MARKER_EDGE,
            markerfacecolor='white',
            markeredgecolor=style['color'],
            markevery=MARK_EVERY)

    legend_entries.append(display_names[i])

# ================= CF 与 CB 曲线交点标注 =================
purples = ['sensing_free_connection_free', 'sensing_based_connection_free']
reds    = ['sensing_free_connection_based', 'sensing_based_connection_based']

intersection_points = []

for p_proto, r_proto in zip(purples, reds):
    if p_proto in throughput_interps and r_proto in throughput_interps:
        f_p = throughput_interps[p_proto]
        f_r = throughput_interps[r_proto]

        x_eval = np.linspace(50, 4000, 2000)
        diff = f_p(x_eval) - f_r(x_eval)
        sign_changes = np.where(np.diff(np.sign(diff)))[0]

        for idx in sign_changes:
            a, b = x_eval[idx], x_eval[idx+1]
            try:
                root = brentq(lambda x: f_p(x) - f_r(x), a, b)
                y_val = f_p(root)
                intersection_points.append((root, y_val))
            except ValueError:
                pass

intersection_points.sort(key=lambda item: item[0])
label_offsets = [-70, 80]

for idx, (x_int, y_int) in enumerate(intersection_points):
    x_offset = label_offsets[idx % len(label_offsets)]

    ax.scatter(x_int, y_int, color=SCIENTIFIC_COLORS['annot_gray'],
               s=30, zorder=5)
    ax.plot([x_int, x_int], [0, y_int],
            color=SCIENTIFIC_COLORS['annot_gray'],
            linestyle='--', linewidth=1.2, zorder=2)

    label_x = x_int + x_offset
    label_y = -0.08
    ax.text(label_x, label_y, f'{int(x_int)}',
            color=SCIENTIFIC_COLORS['text_dark'], ha='center', va='top',
            fontsize=13, zorder=6, clip_on=False)

    ax.annotate('', xy=(x_int, 0), xytext=(label_x, label_y),
                arrowprops=dict(arrowstyle='->', color='black', lw=1.0,
                                connectionstyle='arc3,rad=0'))

ax.set_xlabel(r"$T_p$ ($\mu$s)")
ax.set_ylabel("Maximum Throughput")
ax.set_xlim(0, 4000)
ax.set_ylim(0, 1)
ax.xaxis.set_major_locator(MultipleLocator(1000))
ax.grid(False)

# ================= 自定义图例（修复虚线显示问题） =================
if legend_entries:
    custom_handles = []
    for i, proto in enumerate(protocols):
        if i >= len(legend_entries):
            break
        style = get_protocol_style(proto)

        handle = Line2D(
            [0], [0],
            color=style['color'],
            linestyle=style['linestyle'],
            linewidth=LINE_WIDTH,
            marker=style['marker'],
            markersize=MARKER_SIZE,
            markerfacecolor='white',
            markeredgecolor=style['color'],
            markeredgewidth=MARKER_EDGE,
        )
        if style['linestyle'] == '--':
            handle.set_dashes([3, 2])
        elif style['linestyle'] == ':':
            handle.set_dashes([1, 1.5])

        custom_handles.append(handle)

    ax.legend(
        custom_handles,
        legend_entries,
        loc='lower right',
        bbox_to_anchor=(0.995, 0.04),
        borderaxespad=0.25,
        fontsize=13,
        handlelength=2.8,
        handletextpad=0.8,
        labelspacing=0.4,
        ncol=1,
    )
else:
    ax.text(0.5, 0.5, 'No valid res_M_*.mat data found',
            transform=ax.transAxes, ha='center', va='center', fontsize=13)

plt.tight_layout(pad=1.2)
plt.savefig(os.path.join(data_dir, f"throughput_vs_Tp_{timestamp}.pdf"))
plt.savefig(os.path.join(data_dir, f"throughput_vs_Tp_{timestamp}.png"))
plt.close()

print(f"Throughput plot saved (with CF/CB intersections). Timestamp: {timestamp}")
