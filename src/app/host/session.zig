//! Owns the simulation timeline, dvui chrome, floating panels, and main 3D view wiring.
//! Models plug in through `ulib`; stock views through `vlib`. This module is the host boundary.
const std = @import("std");
const dvui = @import("dvui");
const uSim = @import("usim");
const Particle = @import("ulib");
const vlib = @import("vlib");

const widgets = uSim.Widgets;
const Renderer = widgets.Renderer;
const chrome = @import("chrome.zig");
const LinearTimeline = @import("timeline.zig").LinearTimeline;
const DetachedTopologyShelf = @import("detached_shelf.zig").DetachedTopologyShelf;

/// Main viewport pixel size (center column). Smaller than the window so side info tabs fit; wasm stays under `Software3D` stack guard.
const s3d_px_w: comptime_int = if (@import("builtin").cpu.arch == .wasm32) 720 else 1280;
const s3d_px_h: comptime_int = if (@import("builtin").cpu.arch == .wasm32) 405 else 720;
const s3d_aspect_w_over_h: f32 = @as(f32, @floatFromInt(s3d_px_w)) / @as(f32, @floatFromInt(s3d_px_h));

const InspectorPick = union(enum) {
    none,
    /// Single-vertex pick (relational and clusters).
    main: u64,
    edge: struct {
        from: u64,
        to: u64,
        field: Particle.EdgeField,
    },
    /// Hub pick in clusters mode; member keys live in `SimHost.cluster_pick_members`.
    cluster: struct {
        rep_min_key: u64,
        partition_match: bool,
        class_id: ?u16,
    },
    detached: struct { shelf_index: usize, key: u64 },
};

/// Per-frame pointer so `Software3D` function-pointer callbacks can reach host state without changing the widget API.
var frame_host: ?*SimHost = null;

pub const SimHost = struct {
    /// Borrowed from the exe root: do not embed a `GeneralPurposeAllocator` here; assigning `SimHost`
    /// into a global would bitwise-copy the GPA and corrupt its internal buckets (ReleaseFast segfault).
    allocator: std.mem.Allocator,
    timeline: LinearTimeline,
    detached_shelf: DetachedTopologyShelf,
    viz_active: vlib.Active = .relational,
    auto_advance_time: bool = false,
    step_slider_frac: f32 = 0,
    show_stats_window: bool = false,
    /// 0 = Pick (inspector), 1 = Shape (charts).
    info_left_tab: u8 = 0,
    show_graph_edges: bool = true,
    run_layout: bool = true,
    show_detached_topologies: bool = false,
    inspector_pick: InspectorPick = .none,
    /// Owned slice; valid when `inspector_pick == .cluster`.
    cluster_pick_members: ?[]u64 = null,
    /// Stable storage for `vlib.frame_ctx.highlight_keys` when `inspector_pick == .main` (not `simFrame` stack).
    main_pick_highlight_buf: [1]u64 = undefined,

    fn alloc(self: *SimHost) std.mem.Allocator {
        return self.allocator;
    }

    fn clearClusterPickMembers(self: *SimHost) void {
        if (self.cluster_pick_members) |sl| {
            self.alloc().free(sl);
            self.cluster_pick_members = null;
        }
    }

    /// Slice for ring highlights in the particle layer. Keeps `.main` on `SimHost` so `vlib.frame_ctx` does not point at `simFrame` stack or freed `cluster_pick_members`.
    fn highlightKeysSlice(self: *SimHost) []const u64 {
        switch (self.inspector_pick) {
            .main => |k| {
                self.main_pick_highlight_buf[0] = k;
                return self.main_pick_highlight_buf[0..];
            },
            .cluster => if (self.cluster_pick_members) |m| return m else return &[_]u64{},
            else => return &[_]u64{},
        }
    }

    fn syncFrameCtxHighlightKeys(self: *SimHost) void {
        vlib.frame_ctx.highlight_keys = self.highlightKeysSlice();
    }

    pub fn init(win: *dvui.Window, allocator: std.mem.Allocator, comptime initial_particle_count: comptime_int) !SimHost {
        const theme = switch (win.backend.preferredColorScheme() orelse .dark) {
            .light => dvui.Theme.builtin.adwaita_light,
            .dark => dvui.Theme.builtin.adwaita_dark,
        };
        win.themeSet(theme);

        var self: SimHost = .{
            .allocator = allocator,
            .timeline = undefined,
            .detached_shelf = undefined,
        };
        const a = self.alloc();
        self.detached_shelf = DetachedTopologyShelf.init(a);
        errdefer self.detached_shelf.deinit();

        var genesis = try Particle.initializeGraph(a, initial_particle_count);
        errdefer genesis.deinit();
        self.timeline = try LinearTimeline.initOwnedGenesis(a, genesis);
        return self;
    }

    pub fn deinit(self: *SimHost) void {
        self.clearClusterPickMembers();
        self.detached_shelf.deinit();
        self.timeline.deinit();
    }

    pub fn appFrame(self: *SimHost) !dvui.App.Result {
        var chrome_col = dvui.box(@src(), .{ .dir = .vertical }, .{ .expand = .horizontal });
        defer chrome_col.deinit();

        if (@import("builtin").mode == .Debug) {
            try self.drawDebugTray();
        }

        try self.drawSimulationToolbar();
        try self.drawFpsStatusStrip();

        return self.simFrame();
    }

    fn drawDebugTray(self: *SimHost) !void {
        var debug_tray = dvui.box(@src(), .{ .dir = .horizontal }, chrome.debugTrayOpts());
        defer debug_tray.deinit();

        if (dvui.button(@src(), "Debug Window", .{}, .{})) dvui.toggleDebugWindow();

        dvui.Examples.demo();
        const demo_label = if (dvui.Examples.show_demo_window) "Hide Demo Window" else "Show Demo Window";
        if (dvui.button(@src(), demo_label, .{}, .{ .tag = "show-demo-btn" })) {
            dvui.Examples.show_demo_window = !dvui.Examples.show_demo_window;
        }

        if (self.show_stats_window) {
            var stats = dvui.floatingWindow(@src(), .{ .open_flag = &self.show_stats_window, .window_avoid = .nudge }, chrome.floatingPanelOpts().override(.{
                .min_size_content = .{ .w = 420, .h = 420 },
                .max_size_content = .width(440),
            }));
            defer stats.deinit();
            stats.dragAreaSet(dvui.windowHeader("Simulation overview", "", &self.show_stats_window));

            const sim_stats = try Particle.print(self.alloc(), self.timeline.activeGraph());
            defer self.alloc().free(sim_stats);

            var stats_tl = dvui.textLayout(@src(), .{}, .{ .background = false, .expand = .horizontal });
            defer stats_tl.deinit();
            stats_tl.addText(sim_stats, .{});
        }
        const stats_opts = (if (self.show_stats_window) chrome.toggleOnAccent() else dvui.Options{}).override(.{ .tag = "show-sim-btn" });
        const stats_label = if (self.show_stats_window) "Stats: on" else "Stats: off";
        if (dvui.button(@src(), stats_label, .{}, stats_opts)) {
            self.show_stats_window = !self.show_stats_window;
        }
    }

    fn drawSimulationToolbar(self: *SimHost) !void {
        var view_tray = dvui.box(@src(), .{ .dir = .horizontal }, chrome.toolbarTrayOpts());
        defer view_tray.deinit();

        const tip_edges = "Show or hide directed edge segments between vertices in the 3D view.";
        const tip_viz_rel = "Full relational view: one point per vertex, optional edges, shared force-directed embedding.";
        const tip_viz_clu = "Cluster view: click aggregate hubs or vertices; hubs list member keys; selection ring in the 3D view.";
        const tip_layout = "Layout on: RelationalLayout advances the embedding each frame (vertex positions in graph space). Layout off: freeze those positions (camera still moves). Not the same as zooming the camera.";
        const tip_detached = "Floating list of graphs shelved from the main timeline graph (today: isolates removed when the frontier advances). Pick one to inspect in the left panel; they are not drawn in 3D.";
        const tip_time_run = "Each frame, advance the simulation frontier when you are already at the latest step.";
        const tip_time_hold = "Stop auto-advancing time; scrub with the slider or Step+/-.";
        const tip_step_m = "Go to the previous stored simulation step (same graph snapshot as the slider).";
        const tip_step_p = "Go to the next step, or run one new frontier step if you are already at the latest.";
        const tip_slider = "Choose which stored step is shown. Does not run new physics until you reach the frontier and advance (Step+ or Time run).";

        const edge_opts = (if (self.show_graph_edges) chrome.toggleOnAccent() else dvui.Options{}).override(.{ .tag = "toggle-edges-btn" });
        const edge_label = if (self.show_graph_edges) "Edges: on" else "Edges: off";
        if (chrome.buttonWithTooltip(.edges, @src(), edge_label, tip_edges, .{}, edge_opts)) {
            self.show_graph_edges = !self.show_graph_edges;
        }

        chrome.toolbarGroupSpacer(20);

        const viz_opts = switch (self.viz_active) {
            .relational => chrome.toggleOnAccent().override(.{ .tag = "toggle-viz-active-btn" }),
            .clusters => chrome.vizClustersAccent().override(.{ .tag = "toggle-viz-active-btn" }),
        };
        const viz_label = switch (self.viz_active) {
            .relational => "Viz: relational",
            .clusters => "Viz: clusters",
        };
        const viz_tip = switch (self.viz_active) {
            .relational => tip_viz_rel,
            .clusters => tip_viz_clu,
        };
        if (chrome.buttonWithTooltip(.viz, @src(), viz_label, viz_tip, .{}, viz_opts)) {
            self.viz_active = switch (self.viz_active) {
                .relational => .clusters,
                .clusters => .relational,
            };
        }

        if (vlib.layoutRuns(self.viz_active)) {
            const layout_opts = (if (self.run_layout) chrome.toggleOnAccent() else dvui.Options{}).override(.{ .tag = "toggle-layout-btn" });
            const layout_label = if (self.run_layout) "Layout: relax" else "Layout: freeze";
            if (chrome.buttonWithTooltip(.layout, @src(), layout_label, tip_layout, .{}, layout_opts)) {
                self.run_layout = !self.run_layout;
            }
        }

        chrome.toolbarGroupSpacer(21);

        const detached_opts = (if (self.show_detached_topologies) chrome.toggleOnAccent() else dvui.Options{}).override(.{ .tag = "toggle-detached-btn" });
        const detached_label = if (self.show_detached_topologies) "Detached: on" else "Detached: off";
        if (chrome.buttonWithTooltip(.detached, @src(), detached_label, tip_detached, .{}, detached_opts)) {
            self.show_detached_topologies = !self.show_detached_topologies;
        }

        chrome.toolbarGroupSpacer(22);

        const time_opts = (if (self.auto_advance_time) chrome.toggleOnAccent() else dvui.Options{}).override(.{ .tag = "toggle-time-btn" });
        const time_label = if (self.auto_advance_time) "Time: run" else "Time: hold";
        const time_tip = if (self.auto_advance_time) tip_time_run else tip_time_hold;
        if (chrome.buttonWithTooltip(.time, @src(), time_label, time_tip, .{}, time_opts)) {
            self.auto_advance_time = !self.auto_advance_time;
        }

        if (chrome.buttonWithTooltip(.step_m, @src(), "Step-", tip_step_m, .{}, .{ .tag = "step-minus-btn" })) {
            if (self.timeline.view_step > 0) self.timeline.setViewStep(self.timeline.view_step - 1);
        }
        const step_p_opts = chrome.primaryAccent().override(.{ .tag = "step-plus-btn" });
        if (chrome.buttonWithTooltip(.step_p, @src(), "Step+", tip_step_p, .{}, step_p_opts)) {
            if (self.timeline.view_step < self.timeline.frontierStep()) {
                self.timeline.setViewStep(self.timeline.view_step + 1);
            } else {
                self.timeline.advanceFrontier(&self.detached_shelf) catch {};
                self.timeline.setViewStep(self.timeline.frontierStep());
            }
        }

        chrome.toolbarGroupSpacer(23);

        const mx = self.timeline.frontierStep();
        self.step_slider_frac = if (mx == 0) 0 else @as(f32, @floatFromInt(self.timeline.view_step)) / @as(f32, @floatFromInt(mx));
        var sl_wd: dvui.WidgetData = undefined;
        var sl = dvui.box(@src(), .{ .dir = .horizontal }, .{ .expand = .horizontal, .min_size_content = .{ .w = 140, .h = 26 }, .data_out = &sl_wd });
        defer sl.deinit();
        if (dvui.slider(@src(), .{ .fraction = &self.step_slider_frac }, .{ .expand = .horizontal })) {
            const ns = if (mx == 0) 0 else @as(usize, @intFromFloat(@round(self.step_slider_frac * @as(f32, @floatFromInt(mx)))));
            self.timeline.setViewStep(ns);
        }
        chrome.toolbarTooltipSlider(sl_wd.contentRectScale().r, tip_slider);

        if (self.timeline.loop_pair) |lp| {
            const loop_txt = try std.fmt.allocPrint(self.alloc(), "Loop {d}->{d}", .{ lp.first_step, lp.repeat_step });
            defer self.alloc().free(loop_txt);
            var lp_tl = dvui.textLayout(@src(), .{}, .{ .background = false });
            defer lp_tl.deinit();
            lp_tl.addText(loop_txt, .{ .style = .err });
        }
    }

    fn drawFpsStatusStrip(self: *SimHost) !void {
        var fps_strip = dvui.box(@src(), .{ .dir = .horizontal }, chrome.statusStripOpts().override(.{ .expand = .none }));
        defer fps_strip.deinit();

        var fps_tl = dvui.textLayout(@src(), .{}, .{ .background = false });
        defer fps_tl.deinit();

        const fps = try std.fmt.allocPrint(self.alloc(), "FPS: {d:.1}", .{dvui.FPS()});
        defer self.alloc().free(fps);
        fps_tl.addText(fps, .{ .style = .highlight });

        const fs = self.timeline.frontierStep();
        const vs = self.timeline.view_step;
        const iter_line = if (vs == fs)
            try std.fmt.allocPrint(self.alloc(), "    pairwise pass {d}", .{fs})
        else
            try std.fmt.allocPrint(self.alloc(), "    view {d} / frontier {d}", .{ vs, fs });
        defer self.alloc().free(iter_line);
        fps_tl.addText(iter_line, .{});
    }

    fn layoutApplyThisFrame(self: *const SimHost) bool {
        return self.run_layout;
    }

    fn simFrame(self: *SimHost) !dvui.App.Result {
        frame_host = self;
        defer frame_host = null;

        if (self.auto_advance_time) {
            const at_end = self.timeline.view_step == self.timeline.frontierStep();
            try self.timeline.advanceFrontier(&self.detached_shelf);
            if (at_end) self.timeline.setViewStep(self.timeline.frontierStep());
        }

        if (self.timeline.activeGraph().vertices.count() == 0 and self.detached_shelf.graphCount() == 0) {
            vlib.endRelationalFrameEmbedding();
            return .close;
        }

        self.syncInspectorPickWithGraph();

        var layout_this_frame = self.layoutApplyThisFrame();

        defer vlib.endRelationalFrameEmbedding();
        try vlib.beginRelationalFrameEmbedding(self.viz_active, self.alloc(), self.timeline.activeGraph(), layout_this_frame);

        vlib.frame_ctx = .{
            .active = &self.viz_active,
            .graph = self.timeline.activeGraph(),
            .show_edges = &self.show_graph_edges,
            .apply_layout = &layout_this_frame,
            .allocator = self.alloc(),
            .highlight_keys = self.highlightKeysSlice(),
        };

        try self.drawMainWorkspace(layout_this_frame);
        try self.drawDetachedTopologiesFloating();

        return .ok;
    }

    fn syncInspectorPickWithGraph(self: *SimHost) void {
        const gr = self.timeline.activeGraph();
        switch (self.inspector_pick) {
            .none => {},
            .main => |k| {
                if (gr.getVertex(k) == null) {
                    self.clearClusterPickMembers();
                    self.inspector_pick = .none;
                }
            },
            .edge => |e| {
                if (!gr.hasAdjEdge(e.from, e.to)) {
                    self.clearClusterPickMembers();
                    self.inspector_pick = .none;
                }
            },
            .cluster => {
                if (self.cluster_pick_members) |buf| {
                    for (buf) |mk| {
                        if (gr.getVertex(mk) == null) {
                            self.clearClusterPickMembers();
                            self.inspector_pick = .none;
                            return;
                        }
                    }
                } else {
                    self.inspector_pick = .none;
                }
            },
            .detached => |d| {
                if (d.shelf_index >= self.detached_shelf.graphs.items.len) {
                    self.inspector_pick = .none;
                } else if (self.detached_shelf.graphs.items[d.shelf_index].getVertex(d.key) == null) {
                    self.inspector_pick = .none;
                }
            },
        }
    }

    fn graphDegreeBounds(self: *SimHost) struct { max_out: usize, max_in: usize } {
        var mo: usize = 1;
        var mi: usize = 1;
        var it = self.timeline.activeGraph().vertices.iterator();
        while (it.next()) |ent| {
            mo = @max(mo, ent.value_ptr.*.adjacency_set.count());
            mi = @max(mi, ent.value_ptr.*.incidency_set.count());
        }
        return .{ .max_out = mo, .max_in = mi };
    }

    fn drawLabeledValue(comptime src_loc: std.builtin.SourceLocation, id_extra: usize, label: []const u8, value: []const u8) void {
        // One TextLayout per row: a horizontal box plus two layouts confused vertical packing inside the Shape scroll column.
        var tl = dvui.textLayout(src_loc, .{}, .{
            .background = false,
            .expand = .horizontal,
            .min_size_content = .{ .h = 22 },
            .id_extra = id_extra,
        });
        defer tl.deinit();
        tl.addText(label, .{ .font = dvui.Font.theme(.body) });
        tl.addText("  ", .{});
        tl.addText(value, .{ .style = .highlight });
    }

    fn drawAsciiBar(comptime src_loc: std.builtin.SourceLocation, id_extra: usize, count: usize, maxv: usize) void {
        const bar_w: usize = 28;
        const nh: usize = if (maxv == 0) 0 else @min(bar_w, @max(1, count * bar_w / maxv));
        var row = dvui.box(src_loc, .{ .dir = .horizontal }, .{ .expand = .horizontal, .min_size_content = .{ .h = 14 }, .id_extra = id_extra });
        defer row.deinit();
        var tl = dvui.textLayout(@src(), .{}, .{ .background = false, .id_extra = id_extra * 10 + 1 });
        defer tl.deinit();
        tl.addText("|", .{ .style = .highlight });
        var i: usize = 0;
        while (i < nh) : (i += 1) {
            tl.addText("#", .{ .style = .highlight });
        }
        tl.addText("|", .{ .style = .highlight });
    }

    fn drawMainWorkspace(self: *SimHost, layout_this_frame: bool) !void {
        var layout_var: bool = layout_this_frame;
        var row = dvui.box(@src(), .{ .dir = .horizontal }, .{ .expand = .both });
        defer row.deinit();

        try self.drawInfoColumnLeft(layout_var);
        try self.drawMainViewport(&layout_var);
    }

    fn drawInfoColumnLeft(self: *SimHost, layout_this_frame: bool) !void {
        var outer = dvui.box(@src(), .{ .dir = .horizontal }, chrome.floatingPanelOpts().override(.{
            .expand = .vertical,
            .min_size_content = .{ .w = 300, .h = 160 },
        }));
        defer outer.deinit();

        var tabs = dvui.tabs(@src(), .{ .dir = .vertical }, .{ .expand = .vertical });
        defer tabs.deinit();
        const lt = self.info_left_tab;
        if (tabs.addTabLabel(lt == 0, "Pick", .{ .tag = "info-left-pick" })) self.info_left_tab = 0;
        if (tabs.addTabLabel(lt == 1, "Shape", .{ .tag = "info-left-shape" })) self.info_left_tab = 1;

        var scroll = dvui.scrollArea(@src(), .{ .vertical = .auto }, .{ .expand = .both, .min_size_content = .{ .w = 220, .h = 80 } });
        defer scroll.deinit();

        switch (self.info_left_tab) {
            0 => try self.drawPickTab(),
            1 => try self.drawShapeChartsTab(layout_this_frame),
            else => {
                self.info_left_tab = 0;
                try self.drawPickTab();
            },
        }
    }

    fn drawShapeChartsTab(self: *SimHost, layout_this_frame: bool) !void {
        // Size to content height so rows stack; .both here matched viewport height and packed zero-weight children badly.
        var col = dvui.box(@src(), .{ .dir = .vertical }, .{ .expand = .horizontal });
        defer col.deinit();

        const gr = self.timeline.activeGraph();
        if (vlib.relationalFrameEmbeddingPtr()) |emb| {
            const G = @TypeOf(gr.*);
            var snap = try uSim.structure_analysis.computeStructureSnapshot(G, self.alloc(), gr, emb, .{});
            defer snap.deinit();

            const vn = try std.fmt.allocPrint(self.alloc(), "{d}", .{gr.vertices.count()});
            defer self.alloc().free(vn);
            drawLabeledValue(@src(), 11, "Vertices", vn);

            const cx = try std.fmt.allocPrint(self.alloc(), "{d:.2}", .{snap.centroid[0]});
            defer self.alloc().free(cx);
            const cy = try std.fmt.allocPrint(self.alloc(), "{d:.2}", .{snap.centroid[1]});
            defer self.alloc().free(cy);
            const cz = try std.fmt.allocPrint(self.alloc(), "{d:.2}", .{snap.centroid[2]});
            defer self.alloc().free(cz);
            drawLabeledValue(@src(), 12, "Centroid X", cx);
            drawLabeledValue(@src(), 13, "Centroid Y", cy);
            drawLabeledValue(@src(), 14, "Centroid Z", cz);

            _ = dvui.separator(@src(), .{ .expand = .horizontal });

            const wcc1 = try std.fmt.allocPrint(self.alloc(), "{d}", .{snap.wcc_n});
            defer self.alloc().free(wcc1);
            drawLabeledValue(@src(), 15, "Weak components", wcc1);
            const wcc2 = try std.fmt.allocPrint(self.alloc(), "{d}", .{snap.wcc_largest});
            defer self.alloc().free(wcc2);
            drawLabeledValue(@src(), 16, "Largest WCC", wcc2);
            const wcc3 = try std.fmt.allocPrint(self.alloc(), "{d}", .{snap.wcc_second});
            defer self.alloc().free(wcc3);
            drawLabeledValue(@src(), 17, "2nd WCC", wcc3);

            _ = dvui.separator(@src(), .{ .expand = .horizontal });

            if (snap.shell_nb > 1) {
                var cap: usize = 0;
                for (snap.shell_counts) |c| cap = @max(cap, c);
                var xs: [64]f64 = undefined;
                var ys: [64]f64 = undefined;
                const n = @min(snap.shell_nb, xs.len);
                for (0..n) |i| {
                    xs[i] = @floatFromInt(i);
                    ys[i] = @floatFromInt(snap.shell_counts[i]);
                }
                dvui.plotXY(@src(), .{
                    .xs = xs[0..n],
                    .ys = ys[0..n],
                    .plot_opts = .{ .title = "Vertices per radial shell" },
                }, .{ .min_size_content = .{ .w = 200, .h = 140 }, .expand = .horizontal });
                const cap_s = try std.fmt.allocPrint(self.alloc(), "peak {d} in one bin (shells {d})", .{ cap, snap.shell_nb });
                defer self.alloc().free(cap_s);
                var cap_tl = dvui.textLayout(@src(), .{}, .{ .background = false, .expand = .horizontal, .id_extra = 18 });
                defer cap_tl.deinit();
                cap_tl.addText(cap_s, .{ .font = dvui.Font.theme(.body) });
            }

            _ = dvui.separator(@src(), .{ .expand = .horizontal });

            const kin = try std.fmt.allocPrint(self.alloc(), "{d:.3}", .{snap.k_inertia});
            defer self.alloc().free(kin);
            drawLabeledValue(@src(), 19, "k-means inertia", kin);
            for (snap.k_sizes, 0..) |sz, j| {
                var kbuf: [16]u8 = undefined;
                var vbuf: [16]u8 = undefined;
                const ksl = try std.fmt.bufPrint(&kbuf, "k[{d}]", .{j});
                const vsl = try std.fmt.bufPrint(&vbuf, "{d}", .{sz});
                drawLabeledValue(@src(), 20 + j, ksl, vsl);
            }

            _ = dvui.separator(@src(), .{ .expand = .horizontal });

            const hadron = try Particle.formatHadronStructureHint(self.alloc(), gr);
            defer self.alloc().free(hadron);
            var htl = dvui.textLayout(@src(), .{}, .{ .background = false, .expand = .horizontal, .id_extra = 88 });
            defer htl.deinit();
            htl.addText("Hadron line (inventory)\n", .{ .font = dvui.Font.theme(.heading) });
            htl.addText(hadron, .{});
        } else {
            var tl = dvui.textLayout(@src(), .{}, .{ .background = false, .expand = .horizontal, .id_extra = 90 });
            defer tl.deinit();
            tl.addText(
                "Spatial charts need the relational embedding. Switch Viz to relational or clusters, or enable Layout if frozen.\n",
                .{},
            );
            _ = layout_this_frame;
        }
    }

    fn drawPickTab(self: *SimHost) !void {
        // Match Shape tab: .both vertically fills the scroll viewport and stacks children at y=0 (overlap).
        // .horizontal keeps full width while height follows content so rows pack and scroll correctly.
        var col = dvui.box(@src(), .{ .dir = .vertical }, .{ .expand = .horizontal });
        defer col.deinit();

        const db = self.graphDegreeBounds();
        switch (self.inspector_pick) {
            .none => {
                var tl = dvui.textLayout(@src(), .{}, .{ .background = false, .expand = .horizontal, .id_extra = 50 });
                defer tl.deinit();
                if (self.viz_active == .clusters) {
                    tl.addText(
                        "Clusters: click a hub to inspect an aggregate, a particle for vertex detail, or an edge for field detail. Detached graphs: pick from the list.\n",
                        .{},
                    );
                } else {
                    tl.addText("Click the 3D view to pick a vertex or edge, or use Detached and choose a shelved topology.\n", .{});
                }
            },
            .main => |key| {
                if (self.timeline.activeGraph().getVertex(key)) |node| {
                    const ty = Particle.Type.fromStruct(&node.data);
                    const tag = @tagName(ty);
                    var key_buf: [24]u8 = undefined;
                    const ks = try std.fmt.bufPrint(&key_buf, "{d}", .{key});
                    drawLabeledValue(@src(), 31, "Key", ks);
                    drawLabeledValue(@src(), 32, "Type", tag);

                    const o = node.adjacency_set.count();
                    const i = node.incidency_set.count();
                    const os = try std.fmt.allocPrint(self.alloc(), "{d}", .{o});
                    defer self.alloc().free(os);
                    const ins = try std.fmt.allocPrint(self.alloc(), "{d}", .{i});
                    defer self.alloc().free(ins);
                    drawLabeledValue(@src(), 33, "Edges out", os);
                    drawAsciiBar(@src(), 34, o, db.max_out);
                    drawLabeledValue(@src(), 35, "Edges in", ins);
                    drawAsciiBar(@src(), 36, i, db.max_in);

                    const body = try Particle.formatInspector(self.alloc(), node.data, key, o, i);
                    defer self.alloc().free(body);
                    // One TextLayout for all mono + cluster prose: sibling layouts under scroll often share y=0 and overlap.
                    var mono_tl = dvui.textLayout(@src(), .{}, .{ .background = false, .expand = .horizontal, .id_extra = 37 });
                    defer mono_tl.deinit();
                    mono_tl.addText(body, .{ .font = dvui.Font.theme(.mono) });
                    if (self.viz_active == .clusters) {
                        mono_tl.addText("\n\n", .{});
                        mono_tl.addText("Clusters view (this vertex)\n", .{ .font = dvui.Font.theme(.heading) });
                        const cl_hint = try vlib.cluster_fmt.formatMembershipHint(
                            self.alloc(),
                            self.timeline.activeGraph(),
                            key,
                        );
                        defer self.alloc().free(cl_hint);
                        mono_tl.addText(cl_hint, .{ .font = dvui.Font.theme(.mono) });
                    }
                } else {
                    self.clearClusterPickMembers();
                    self.inspector_pick = .none;
                    var tl = dvui.textLayout(@src(), .{}, .{ .background = false, .expand = .horizontal, .id_extra = 51 });
                    defer tl.deinit();
                    tl.addText("Selection cleared (vertex removed).\n", .{});
                }
            },
            .edge => |e| {
                drawLabeledValue(@src(), 52, "Edge", "selected");
                const from_s = try std.fmt.allocPrint(self.alloc(), "{d}", .{e.from});
                defer self.alloc().free(from_s);
                const to_s = try std.fmt.allocPrint(self.alloc(), "{d}", .{e.to});
                defer self.alloc().free(to_s);
                drawLabeledValue(@src(), 53, "From", from_s);
                drawLabeledValue(@src(), 54, "To", to_s);
                drawLabeledValue(@src(), 55, "Field", @tagName(e.field));

                const body = try Particle.formatEdgeInspector(
                    self.alloc(),
                    self.timeline.activeGraph(),
                    e.from,
                    e.to,
                );
                defer self.alloc().free(body);
                var edge_tl = dvui.textLayout(
                    @src(),
                    .{},
                    .{ .background = false, .expand = .horizontal, .id_extra = 56 },
                );
                defer edge_tl.deinit();
                edge_tl.addText(body, .{ .font = dvui.Font.theme(.mono) });
            },
            .cluster => |c| {
                if (self.cluster_pick_members) |mems| {
                    var repb: [24]u8 = undefined;
                    const reps = try std.fmt.bufPrint(&repb, "{d}", .{c.rep_min_key});
                    drawLabeledValue(@src(), 60, "Hub id (min key)", reps);
                    const kind_s: []const u8 =
                        if (c.partition_match) "matched piece" else "residual aggregate";
                    drawLabeledValue(@src(), 61, "Kind", kind_s);
                    if (c.class_id) |cid| {
                        const lyr = vlib.cluster_registry.activeLayer();
                        drawLabeledValue(@src(), 62, "Layer class", lyr.className(cid));
                    } else {
                        drawLabeledValue(@src(), 62, "Layer class", "(none)");
                    }
                    const ns = try std.fmt.allocPrint(self.alloc(), "{d}", .{mems.len});
                    defer self.alloc().free(ns);
                    drawLabeledValue(@src(), 63, "Members", ns);
                    const hub_body = try vlib.cluster_fmt.formatHubInspector(
                        self.alloc(),
                        self.timeline.activeGraph(),
                        c.rep_min_key,
                        c.partition_match,
                        c.class_id,
                        mems,
                    );
                    defer self.alloc().free(hub_body);
                    var hub_tl = dvui.textLayout(@src(), .{}, .{ .background = false, .expand = .horizontal, .id_extra = 64 });
                    defer hub_tl.deinit();
                    hub_tl.addText(hub_body, .{ .font = dvui.Font.theme(.mono) });
                } else {
                    self.inspector_pick = .none;
                    var tl = dvui.textLayout(@src(), .{}, .{ .background = false, .expand = .horizontal, .id_extra = 65 });
                    defer tl.deinit();
                    tl.addText("Selection cleared (cluster data missing).\n", .{});
                }
            },
            .detached => |d| {
                if (d.shelf_index < self.detached_shelf.graphs.items.len) {
                    if (self.detached_shelf.graphs.items[d.shelf_index].getVertex(d.key)) |node| {
                        drawLabeledValue(@src(), 41, "Shelved", "not in 3D");
                        const ty = Particle.Type.fromStruct(&node.data);
                        drawLabeledValue(@src(), 42, "Type", @tagName(ty));
                        const o = node.adjacency_set.count();
                        const i = node.incidency_set.count();
                        const os = try std.fmt.allocPrint(self.alloc(), "{d}", .{o});
                        defer self.alloc().free(os);
                        const ins = try std.fmt.allocPrint(self.alloc(), "{d}", .{i});
                        defer self.alloc().free(ins);
                        drawLabeledValue(@src(), 43, "Edges out", os);
                        drawAsciiBar(@src(), 44, o, db.max_out);
                        drawLabeledValue(@src(), 45, "Edges in", ins);
                        drawAsciiBar(@src(), 46, i, db.max_in);
                        const body = try Particle.formatInspector(self.alloc(), node.data, d.key, o, i);
                        defer self.alloc().free(body);
                        var body_tl = dvui.textLayout(@src(), .{}, .{ .background = false, .expand = .horizontal, .id_extra = 47 });
                        defer body_tl.deinit();
                        body_tl.addText(body, .{ .font = dvui.Font.theme(.mono) });
                    } else {
                        self.inspector_pick = .none;
                        var tl = dvui.textLayout(@src(), .{}, .{ .background = false, .expand = .horizontal, .id_extra = 52 });
                        defer tl.deinit();
                        tl.addText("Selection cleared.\n", .{});
                    }
                } else {
                    self.inspector_pick = .none;
                    var tl = dvui.textLayout(@src(), .{}, .{ .background = false, .expand = .horizontal, .id_extra = 53 });
                    defer tl.deinit();
                    tl.addText("Selection cleared.\n", .{});
                }
            },
        }
    }

    fn drawMainViewport(self: *SimHost, layout_this_frame: *bool) !void {
        // Pick tab may clear/freed cluster highlights before we reach the 3D widget; `Software3D.render` may free them inside `on_left_press` before `layer.draw`.
        self.syncFrameCtxHighlightKeys();

        var center = dvui.box(@src(), .{ .dir = .vertical }, .{ .expand = .both });
        defer center.deinit();

        var S3D = widgets.Software3D.Software3D(@src(), .{
            .camera_controls = cameraControlsThunk,
            .width = s3d_px_w,
            .height = s3d_px_h,
            .on_left_press = s3dOnLeftPressThunk,
        }, .{}).init();
        defer S3D.deinit(self.alloc());
        S3D.left_press_ctx = @ptrCast(layout_this_frame);

        try S3D.addLayer(self.alloc(), Renderer.Grid(5, 10));
        try S3D.addLayer(self.alloc(), Renderer.Axes(1.0));
        try S3D.addLayer(self.alloc(), vlib.ParticlesLayer);

        try S3D.render(self.alloc());
    }

    fn drawDetachedTopologiesFloating(self: *SimHost) !void {
        if (!self.show_detached_topologies) return;

        var dw = dvui.floatingWindow(@src(), .{ .open_flag = &self.show_detached_topologies, .window_avoid = .nudge }, chrome.floatingPanelOpts().override(.{
            .min_size_content = .{ .w = 380, .h = 340 },
        }));
        defer dw.deinit();
        dw.dragAreaSet(dvui.windowHeader("Detached topologies", "", &self.show_detached_topologies));

        var dw_col = dvui.box(@src(), .{ .dir = .vertical }, .{ .expand = .both });
        defer dw_col.deinit();

        if (self.detached_shelf.graphCount() == 0) {
            var dw_tl = dvui.textLayout(@src(), .{}, .{ .background = false, .expand = .horizontal });
            defer dw_tl.deinit();
            dw_tl.addText(
                "Nothing on the shelf yet. When the timeline frontier advances, vertices with no edges (isolates) are removed from the main graph and appended here as separate one-vertex graphs.\n" ++
                    "Scrub the step slider to an earlier step to see those vertices still inside the main graph.\n",
                .{},
            );
        } else {
            const ng = self.detached_shelf.graphs.items.len;
            var total_v: usize = 0;
            for (self.detached_shelf.graphs.items) |*gr| {
                total_v += gr.vertices.count();
            }
            const intro = try std.fmt.allocPrint(self.alloc(), "Shelf: {d} graph(s), {d} vertices total.\n\nEach row is one shelved graph (not one button per vertex). Click a row to inspect that graph's representative key in the left panel. Shelved graphs are not drawn in 3D.\n", .{ ng, total_v });
            defer self.alloc().free(intro);
            // Finish this TextLayout before any buttons: siblings created while it stays open can interleave layout and overlap text.
            {
                var intro_tl = dvui.textLayout(@src(), .{}, .{
                    .background = false,
                    .expand = .horizontal,
                    .margin = dvui.Rect{ .h = 10 },
                });
                defer intro_tl.deinit();
                intro_tl.addText(intro, .{});
            }

            var topo_btn_id: usize = 0;
            for (self.detached_shelf.graphs.items, 0..) |*gr, gi| {
                topo_btn_id += 1;
                const nk = gr.vertices.count();
                const rep_k = graphMinKey(gr) orelse continue;
                const node = gr.getVertex(rep_k) orelse continue;
                const ty = Particle.Type.fromStruct(&node.data);
                const lbl = try std.fmt.allocPrint(self.alloc(), "Graph {d}/{d}: {d} vert(s), key {d} ({s})", .{ gi + 1, ng, nk, rep_k, @tagName(ty) });
                defer self.alloc().free(lbl);
                const tag = try std.fmt.allocPrint(self.alloc(), "detached-graph-{d}", .{gi});
                defer self.alloc().free(tag);
                if (dvui.button(@src(), lbl, .{}, .{
                    .tag = tag,
                    .id_extra = topo_btn_id,
                    .expand = .horizontal,
                    .margin = dvui.Rect{ .h = 6 },
                })) {
                    self.inspector_pick = .{ .detached = .{ .shelf_index = gi, .key = rep_k } };
                    self.info_left_tab = 0;
                }
            }
        }
    }

    fn handleInput(self: *SimHost, camera: *widgets.Camera) void {
        const move_speed: f32 = 0.1;
        const look_speed: f32 = 0.05;

        for (dvui.events()) |event| {
            if (event.evt == .key) {
                const key_event = event.evt.key;
                if (event.handled) continue;

                if (key_event.action == .down or key_event.action == .repeat) {
                    switch (key_event.code) {
                        .f => {
                            switch (self.inspector_pick) {
                                .main => |key| {
                                    const apply = self.layoutApplyThisFrame();
                                    const wf = vlib.FrameView{
                                        .active = &self.viz_active,
                                        .graph = self.timeline.activeGraph(),
                                        .show_edges = &self.show_graph_edges,
                                        .apply_layout = &apply,
                                        .allocator = self.alloc(),
                                        .highlight_keys = &[_]u64{},
                                    };
                                    if (vlib.worldPositionForVertex(wf, key) catch null) |target| {
                                        frameCameraOnVertex(camera, target);
                                    } else {
                                        frameCameraOnParticles(self, camera);
                                    }
                                },
                                .cluster => {
                                    if (self.cluster_pick_members) |mems| {
                                        if (vlib.centroidWorldForKeys(mems)) |target| {
                                            frameCameraOnVertex(camera, target);
                                        } else {
                                            frameCameraOnParticles(self, camera);
                                        }
                                    } else {
                                        frameCameraOnParticles(self, camera);
                                    }
                                },
                                .edge => |e| {
                                    const apply = self.layoutApplyThisFrame();
                                    const wf = vlib.FrameView{
                                        .active = &self.viz_active,
                                        .graph = self.timeline.activeGraph(),
                                        .show_edges = &self.show_graph_edges,
                                        .apply_layout = &apply,
                                        .allocator = self.alloc(),
                                        .highlight_keys = &[_]u64{},
                                    };
                                    const p1 = vlib.worldPositionForVertex(wf, e.from) catch null;
                                    const p2 = vlib.worldPositionForVertex(wf, e.to) catch null;
                                    if (p1 != null and p2 != null) {
                                        const mid = (p1.? + p2.?) / @as(Renderer.Vec3, @splat(2));
                                        frameCameraOnVertex(camera, mid);
                                    } else {
                                        frameCameraOnParticles(self, camera);
                                    }
                                },
                                .none, .detached => frameCameraOnParticles(self, camera),
                            }
                        },
                        .w => camera.position += camera.forward() * @as(Renderer.Vec3, @splat(move_speed)),
                        .s => camera.position -= camera.forward() * @as(Renderer.Vec3, @splat(move_speed)),
                        .a => camera.position -= camera.right() * @as(Renderer.Vec3, @splat(move_speed)),
                        .d => camera.position += camera.right() * @as(Renderer.Vec3, @splat(move_speed)),
                        .space => camera.position[1] += move_speed,
                        .left_shift => camera.position[1] -= move_speed,
                        .j, .left => camera.yaw += look_speed,
                        .l, .right => camera.yaw -= look_speed,
                        .i, .up => camera.pitch += look_speed,
                        .k, .down => camera.pitch -= look_speed,
                        else => {},
                    }
                }
            }
        }
    }
};

fn graphMinKey(gr: *const Particle.Graph) ?u64 {
    var it = gr.vertices.iterator();
    var best: ?u64 = null;
    while (it.next()) |ent| {
        const k = ent.key_ptr.*;
        best = if (best) |b| @min(b, k) else k;
    }
    return best;
}

fn cameraControlsThunk(camera: *widgets.Camera) void {
    frame_host.?.handleInput(camera);
}

fn s3dOnLeftPressThunk(ctx: ?*anyopaque, camera: widgets.Camera, fx: f32, fy: f32) void {
    const self = frame_host.?;
    const apply_ptr: *bool = @ptrCast(@alignCast(ctx.?));
    const fv = vlib.FrameView{
        .active = &self.viz_active,
        .graph = self.timeline.activeGraph(),
        .show_edges = &self.show_graph_edges,
        .apply_layout = apply_ptr,
        .allocator = self.alloc(),
        .highlight_keys = &[_]u64{},
    };
    const hit = vlib.pickMainView(self.alloc(), fv, camera, s3d_px_w, s3d_px_h, fx, fy) catch return;
    if (hit) |h| {
        switch (h) {
            .vertex => |k| {
                self.clearClusterPickMembers();
                self.inspector_pick = .{ .main = k };
            },
            .edge => |e| {
                self.clearClusterPickMembers();
                self.inspector_pick = .{ .edge = .{
                    .from = e.from,
                    .to = e.to,
                    .field = e.field,
                } };
            },
            .cluster => |cl| {
                self.clearClusterPickMembers();
                self.cluster_pick_members = cl.members;
                self.inspector_pick = .{ .cluster = .{
                    .rep_min_key = cl.rep_min_key,
                    .partition_match = cl.partition_match,
                    .class_id = cl.class_id,
                } };
            },
        }
        self.syncFrameCtxHighlightKeys();
        self.info_left_tab = 0;
    }
}

fn frameCameraOnVertex(camera: *widgets.Camera, target: Renderer.Vec3) void {
    const dist: f32 = 3.0;
    camera.pitch = 0;
    camera.yaw = 0;
    camera.position = target - camera.forward() * @as(Renderer.Vec3, @splat(dist));
}

fn frameCameraOnParticles(self: *SimHost, camera: *widgets.Camera) void {
    const apply = self.layoutApplyThisFrame();
    const b = vlib.worldBounds(self.alloc(), self.viz_active, self.timeline.activeGraph(), apply) catch return orelse return;
    const margin = 1.18;
    const min_r: f32 = 0.35;
    const r = @max(b.radius, min_r);
    const half_fov = std.math.degreesToRadians(camera.fov * 0.5);
    const tan_v = @tan(half_fov);
    const tan_h = tan_v * s3d_aspect_w_over_h;
    const dist_v = r / tan_v;
    const dist_h = r / tan_h;
    const dist = @max(dist_v, dist_h) * margin + camera.near;

    camera.pitch = 0;
    camera.yaw = 0;
    camera.position = b.center - camera.forward() * @as(Renderer.Vec3, @splat(dist));
}
