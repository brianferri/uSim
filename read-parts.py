import csv
import math
import matplotlib.pyplot as plt


def read_csv_data(filename: str):
    with open(filename, 'r') as file:
        reader = csv.reader(file)
        columns = next(reader)
        data = {col: [] for col in columns}
        for row in reader:
            for i, col in enumerate(columns):
                data[col].append(float(
                    row[i]) if '.' in row[i] or 'e' in row[i].lower() else int(row[i]))
    return data, columns


def plot_data(data: dict[str, list], x_col: str, y_cols: list[str]):
    x_data = data[x_col]
    n = len(y_cols)
    cols = min(3, n)
    rows = math.ceil(n / cols)

    fig, axes = plt.subplots(rows, cols, figsize=(
        5 * cols, 3.5 * rows), sharex=True)
    axes = axes.flatten()
    colors = plt.rcParams['axes.prop_cycle'].by_key()['color']

    for i, y_col in enumerate(y_cols):
        ax = axes[i]
        color = colors[i % len(colors)]
        ax.plot(x_data, data[y_col], color=color, marker='o', linestyle='-')
        ax.set_ylabel(y_col, color=color)
        ax.tick_params(axis='y', labelcolor=color)
        ax.grid(True, linestyle='--', alpha=0.5)

    for i in range(len(y_cols), len(axes)):
        fig.delaxes(axes[i])

    axes[min(len(y_cols) - 1, len(axes) - 1)].set_xlabel(x_col)
    plt.tight_layout(rect=[0, 0.03, 1, 0.95])
    plt.show()


data, columns = read_csv_data('zig-out/parts.csv')
plot_data(data, columns[0], columns[1:])
