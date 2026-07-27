import matplotlib.pyplot as plt
import numpy as np
import scipy.io as sio
from scipy.interpolate import PchipInterpolator
import os
from datetime import datetime

# ===================== 全局学术绘图风格 =====================
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


def get_protocol_style(proto):
    if 'sub_7G_assisted' in proto:
        return {
            'color': '#009E73',
            'marker': '^',
            'linestyle': '-.' if 'clean' in proto else ':'
        }

    is_sf = 'sensing_free' in proto
    is_cf = 'connection_free' in proto

    return {
        'color': '#6A3D9A' if is_cf else '#D62728',
        'marker': 'o' if is_sf else 's',
        'linestyle': '-' if is_sf else '--'
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


def smooth_curve(x, y, points=300):
    x = np.asarray(x).flatten()
    y = np.asarray(y).flatten()

    valid = np.isfinite(x) & np.isfinite(y)
    x = x[valid]
    y = y[valid]

    if x.size < 3:
        return x, y

    order = np.argsort(x)
    x_sorted = x[order]
    y_sorted = y[order]

    x_unique, idx = np.unique(x_sorted, return_index=True)
    y_unique = y_sorted[idx]

    if x_unique.size < 3:
        return x_unique, y_unique

    x_new = np.linspace(x_unique.min(), x_unique.max(), points)
    interp = PchipInterpolator(x_unique, y_unique)
    y_new = interp(x_new)
    return x_new, y_new


# =========================================================================
# Throughput vs Tp only
# =========================================================================
fig, ax = plt.subplots(1, 1, figsize=(8, 5))

legend_entries = []

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

    x_th, y_th = smooth_curve(T_p_VALUES, th, points=300)
    ax.plot(x_th, y_th, linestyle=style['linestyle'], marker=style['marker'],
            color=style['color'], linewidth=1.8, markersize=7,
            markeredgewidth=1.3, markerfacecolor='white', markevery=15)

    legend_entries.append(display_names[i])

ax.set_xlabel(r"$T_p$ ($\mu$s)")
ax.set_ylabel("Maximum Throughput")
ax.set_xlim(0, 4000)
ax.set_ylim(0, 1)
ax.grid(False)

if legend_entries:
    ax.legend(
        legend_entries,
        loc='lower right',
        bbox_to_anchor=(0.995, 0.04),
        borderaxespad=0.25,
        fontsize=13,
        handlelength=2.0,
        labelspacing=0.4
    )
else:
    ax.text(0.5, 0.5, 'No valid res_M_*.mat data found',
            transform=ax.transAxes, ha='center', va='center', fontsize=13)

plt.tight_layout(pad=1.2)
plt.savefig(os.path.join(data_dir, f"throughput_vs_Tp_{timestamp}.pdf"))
plt.savefig(os.path.join(data_dir, f"throughput_vs_Tp_{timestamp}.png"))
plt.close()

print(f"Throughput plot saved. Timestamp: {timestamp}")
