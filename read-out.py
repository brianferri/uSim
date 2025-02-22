import matplotlib.pyplot as plt
import csv

# Read data from file
data = {"iter": [], "vertices": [], "num_edges": [], "iter_time": [], "mem": []}
with open('out.csv', 'r') as file:
    reader = csv.reader(file)
    next(reader)  # Skip header
    for row in reader:
        data["iter"].append(int(row[0]))
        data["vertices"].append(int(row[1]))
        data["num_edges"].append(int(row[2]))
        data["iter_time"].append(float(row[3]))
        data["mem"].append(int(row[4]))

# Create subplots
fig, ax1 = plt.subplots()

# Plot iteration time
color = 'tab:red'
ax1.set_xlabel('Iteration')
ax1.set_ylabel('Iteration Time (ms)', color=color)
ax1.plot(data["iter"], data["iter_time"], marker='o', linestyle='-', color=color, label='Iteration Time')
ax1.tick_params(axis='y', labelcolor=color)
ax1.grid(True, linestyle='--', alpha=0.6)

# Create a second y-axis for vertices
ax2 = ax1.twinx()
color = 'tab:blue'
ax2.set_ylabel('Vertices', color=color)
ax2.plot(data["iter"], data["vertices"], marker='s', linestyle='--', color=color, label='Vertices')
ax2.tick_params(axis='y', labelcolor=color)

# Create a third y-axis for memory
ax3 = ax1.twinx()
color = 'tab:green'
ax3.spines['right'].set_position(('outward', 60))
ax3.set_ylabel('Memory', color=color)
ax3.plot(data["iter"], data["mem"], marker='s', linestyle='--', color=color, label='Memory')
ax3.tick_params(axis='y', labelcolor=color)

# Create a fourth y-axis for number of edges
ax4 = ax1.twinx()
color = 'tab:purple'
ax4.spines['right'].set_position(('outward', 120))
ax4.set_ylabel('Number of Edges', color=color)
ax4.plot(data["iter"], data["num_edges"], marker='^', linestyle='-.', color=color, label='Edges')
ax4.tick_params(axis='y', labelcolor=color)

# Add title
plt.title("Iteration vs Iteration Time, Vertices, Memory, and Edges")
fig.tight_layout()

# Show plot
plt.show()