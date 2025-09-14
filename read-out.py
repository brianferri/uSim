import matplotlib.pyplot as plt
import csv

def read_csv_data(filename: str):
    with open(filename, 'r') as file:
        reader = csv.reader(file)
        columns = next(reader)
        data = {col: [] for col in columns}
        for row in reader:
            for i, col in enumerate(columns):
                data[col].append(int(row[i]) if col != "iter_time" else float(row[i]))
    return data, columns

def plot_data(data: dict[str, list], x_col: str, y_cols: list[str], colors: list[str]):
    fig, ax1 = plt.subplots()
    ax1.set_xlabel(x_col)
    ax1.grid(True, linestyle='--', alpha=0.6)
    axes = [ax1]
    for i, (y_col, color) in enumerate(zip(y_cols, colors)):
        ax = ax1 if i == 0 else ax1.twinx()
        ax.spines['right'].set_position(('outward', i * 60))
        ax.set_ylabel(y_col, color=color)
        ax.plot(data[x_col], data[y_col], marker='o', linestyle='-', color=color, label=y_col)
        ax.tick_params(axis='y', labelcolor=color)
        axes.append(ax)
    plt.title("Metrics Comparison")
    fig.tight_layout()
    plt.legend(loc='upper left')
    plt.show()

data, columns = read_csv_data('zig-out/out.csv')
plot_data(data, columns[0], columns[1:], ['tab:red', 'tab:blue', 'tab:green', 'tab:purple'])
