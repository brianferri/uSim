import csv
import math
import matplotlib.pyplot as plt


def read_csv_data(filename: str):
    with open(filename, 'r') as file:
        reader = csv.reader(file)
        headers = next(reader)
        data = {header: [] for header in headers}

        for row in reader:
            for i, header in enumerate(headers):
                try:
                    value = float(
                        row[i]) if '.' in row[i] or 'e' in row[i].lower() else int(row[i])
                except ValueError:
                    value = row[i]
                data[header].append(value)

    return data, headers


def plot_data(
    data: dict[str, list],
    x_col: str,
    y_cols: list[str],
    use_subplots: bool = False,
    colors: list[str] = None
):
    if colors is None:
        colors = plt.rcParams['axes.prop_cycle'].by_key()['color']

    x_data = data[x_col]

    if use_subplots:
        n = len(y_cols)
        cols = min(3, n)
        rows = math.ceil(n / cols)

        fig, axes = plt.subplots(rows, cols, figsize=(
            5 * cols, 3.5 * rows), sharex=True)
        axes = axes.flatten()

        for i, y_col in enumerate(y_cols):
            ax = axes[i]
            color = colors[i % len(colors)]

            ax.plot(x_data, data[y_col], color=color,
                    marker='o', linestyle='-')
            ax.set_ylabel("Value", color=color)
            ax.tick_params(axis='y', labelcolor=color)
            ax.grid(True, linestyle='--', alpha=0.5)

            # Add label on the right side
            y_max = max(data[y_col])
            y_min = min(data[y_col])
            y_mid = y_min + (y_max - y_min) * 0.5
            ax.annotate(
                y_col,
                xy=(1.01, y_mid),
                xycoords=('axes fraction', 'data'),
                va='center',
                ha='left',
                fontsize=9,
                color=color
            )

        for i in range(len(y_cols), len(axes)):
            fig.delaxes(axes[i])

        axes[min(len(y_cols) - 1, len(axes) - 1)].set_xlabel(x_col)
        plt.tight_layout(rect=[0, 0.03, 1, 0.95])
        plt.show()

    else:
        # Multi-y-axis style
        fig, ax1 = plt.subplots()
        ax1.set_xlabel(x_col)
        ax1.grid(True, linestyle='--', alpha=0.6)
        axes = [ax1]

        for i, y_col in enumerate(y_cols):
            ax = ax1 if i == 0 else ax1.twinx()
            ax.spines['right'].set_position(('outward', i * 60))
            color = colors[i % len(colors)]

            ax.plot(x_data, data[y_col], color=color,
                    marker='o', linestyle='-', label=y_col)
            ax.set_ylabel(y_col, color=color)
            ax.tick_params(axis='y', labelcolor=color)
            axes.append(ax)

        fig.tight_layout()

        handles, labels = [], []
        for ax in axes:
            h, l = ax.get_legend_handles_labels()
            handles += h
            labels += l

        fig.legend(handles, labels, loc='upper left')
        plt.show()


data, columns = read_csv_data('zig-out/parts.csv')
x_column = columns[0]
y_columns = columns[1:]

plot_data(data, x_column, y_columns, use_subplots=True)
