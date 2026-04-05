# Visualizations (`vlib`)

Build-time package root: **`visualizations/dispatch.zig`** (`@import("vlib")`).

## Layout

| Path | Role |
|------|------|
| **`dispatch.zig`** | `Active`, `frame_ctx`, embedding cache, `ParticlesLayer`, pick, bounds, help text. |
| **`relational/main.zig`** | Force-directed embedding + draw for generic `Particle.Graph`. |
| **`clusters/main.zig`** | Weak-component / hadron-style draw; uses model helpers on `Particle`. |

## Model coupling (today)

Stock modes **`@import("ulib")`** for vertex payload and graph type (`Particle`, `Particle.Graph`) and **`@import("usim")`** for **`RelationalLayout`**, **`Widgets`**, and graph utilities. That import edge is the **only** supported way a mode sees the model: do not add parallel globals or cached simulation state in `vlib`.

The host sets **`frame_ctx`** each frame (`graph`, `allocator`, `highlight_keys`, toggles). **`relational_frame_emb`** is rebuilt when the host calls **`beginRelationalFrameEmbedding`**; it must not outlive the displayed graph snapshot.

## Interfaces / vtables

3D layers use **`usim.Widgets.Renderer.Layer`**: a small vtable with **`draw`**. Visualization code stays functional (Zig modules + pointers), not class hierarchies.

## Adding a mode

1. Add a submodule under **`visualizations/<name>/`**.  
2. Import it from **`dispatch.zig`** and extend **`Active`**.  
3. Keep **`ulib`** usage limited to types and hooks the model already exports; push model-specific branching into **`ulib`**, not into `dispatch` conditionals on model name.
