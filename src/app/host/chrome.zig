//! dvui styling helpers for the host shell (Pixi-inspired: rounded panels, soft shadow, translucent trays).
//! Call `floatingPanelOpts` / `toolbarTrayOpts` only between `Window.begin` and `Window.end`.
const std = @import("std");
const dvui = @import("dvui");

/// `FloatingTooltipWidget.init` only forwards `.name` and `.rect` into `WidgetData.init`, so
/// `Options.id_extra` on the tooltip does **not** change the widget id. Every tooltip therefore shares
/// `id_extra == 0` in the id hash; only `@src()` disambiguates. Distinct wrapper functions below each use
/// their own `@src()` line so ids stay unique even when `ReleaseFast` blurs caller line info.
pub const ToolbarTooltipTag = enum {
    edges,
    viz,
    layout,
    detached,
    time,
    step_m,
    step_p,
};

/// Delay before fade-in (microseconds); keeps toolbar hints from flickering on fast mouse moves.
pub const toolbar_tooltip_delay_us: i32 = 350_000;

fn floatingHelpTooltipImpl(
    tooltip_src: std.builtin.SourceLocation,
    active_rect_physical: dvui.Rect.Physical,
    comptime fmt: []const u8,
    fmt_args: anytype,
) void {
    var tt: dvui.FloatingTooltipWidget = undefined;
    tt.init(tooltip_src, .{
        .active_rect = active_rect_physical,
        .position = .vertical,
        .delay = toolbar_tooltip_delay_us,
    }, .{
        .role = .tooltip,
        .min_size_content = .{ .w = 340, .h = 36 },
    });
    if (tt.shown()) {
        var tl2 = dvui.textLayout(@src(), .{}, .{
            .background = false,
            .expand = .horizontal,
            .min_size_content = .{ .w = 300, .h = 0 },
            .padding = dvui.Rect.all(6),
        });
        tl2.format(fmt, fmt_args, .{});
        tl2.deinit();
        if (tt.data().accesskit_node()) |ak_node| {
            var str_builder: std.Io.Writer.Allocating = .init(dvui.currentWindow().arena());
            str_builder.writer.print(fmt, fmt_args) catch {};
            dvui.AccessKit.nodeSetLabel(ak_node, str_builder.toOwnedSliceSentinel(0) catch "");
        }
    }
    tt.deinit();
}

fn ttSimEdges(active: dvui.Rect.Physical, tip: []const u8) void {
    floatingHelpTooltipImpl(@src(), active, "{s}", .{tip});
}
fn ttSimViz(active: dvui.Rect.Physical, tip: []const u8) void {
    floatingHelpTooltipImpl(@src(), active, "{s}", .{tip});
}
fn ttSimLayout(active: dvui.Rect.Physical, tip: []const u8) void {
    floatingHelpTooltipImpl(@src(), active, "{s}", .{tip});
}
fn ttSimDetached(active: dvui.Rect.Physical, tip: []const u8) void {
    floatingHelpTooltipImpl(@src(), active, "{s}", .{tip});
}
fn ttSimTime(active: dvui.Rect.Physical, tip: []const u8) void {
    floatingHelpTooltipImpl(@src(), active, "{s}", .{tip});
}
fn ttSimStepM(active: dvui.Rect.Physical, tip: []const u8) void {
    floatingHelpTooltipImpl(@src(), active, "{s}", .{tip});
}
fn ttSimStepP(active: dvui.Rect.Physical, tip: []const u8) void {
    floatingHelpTooltipImpl(@src(), active, "{s}", .{tip});
}

/// Step slider tray uses the same tooltip sizing; separate `@src()` from toolbar buttons.
pub fn toolbarTooltipSlider(active: dvui.Rect.Physical, tip: []const u8) void {
    floatingHelpTooltipImpl(@src(), active, "{s}", .{tip});
}

/// Narrow gap between toolbar control groups (Pixi / IDE style).
/// `id_extra` must differ for each spacer under the same parent (same `@src()` here otherwise collides).
pub fn toolbarGroupSpacer(id_extra: usize) void {
    _ = dvui.spacer(@src(), .{ .min_size_content = .{ .w = 10, .h = 1 }, .id_extra = id_extra });
}

/// Toolbar button with hover tooltip (`tip` must live until end of frame; static string is fine).
pub fn buttonWithTooltip(
    comptime tt_tag: ToolbarTooltipTag,
    src: std.builtin.SourceLocation,
    label: []const u8,
    tip: []const u8,
    init_opts: dvui.ButtonWidget.InitOptions,
    opts: dvui.Options,
) bool {
    var wd: dvui.WidgetData = undefined;
    const o = opts.override(.{ .data_out = &wd });
    const clicked = dvui.button(src, label, init_opts, o);
    // Content rect tracks the label area; avoids matching hover to the full margin box.
    const hot = wd.contentRectScale().r;
    switch (tt_tag) {
        .edges => ttSimEdges(hot, tip),
        .viz => ttSimViz(hot, tip),
        .layout => ttSimLayout(hot, tip),
        .detached => ttSimDetached(hot, tip),
        .time => ttSimTime(hot, tip),
        .step_m => ttSimStepM(hot, tip),
        .step_p => ttSimStepP(hot, tip),
    }
    return clicked;
}

/// Floating statistics / inspector windows: card-like panels.
pub fn floatingPanelOpts() dvui.Options {
    const t = dvui.themeGet();
    return .{
        .style = .window,
        // Slightly larger radius reads smoother at typical UI scale than r=8..10 alone (still limited by backend AA).
        .corner_radius = dvui.Rect.all(12),
        .border = dvui.Rect.all(1),
        .padding = dvui.Rect{ .x = 12, .y = 12, .w = 12, .h = 12 },
        // Less translucent so floating panels do not show the 3D view through the card (was mistaken for bad rounding).
        .color_fill = t.color(.window, .fill).opacity(0.97),
        .box_shadow = .{
            .color = .black,
            .alpha = 0.4,
            .offset = .{ .x = 0, .y = 6 },
            .fade = 18,
        },
    };
}

/// Main simulation toolbar background (sits over the 3D view).
pub fn toolbarTrayOpts() dvui.Options {
    const t = dvui.themeGet();
    return .{
        .style = .content,
        .corner_radius = dvui.Rect.all(8),
        .padding = dvui.Rect{ .x = 8, .y = 6, .w = 8, .h = 6 },
        .margin = dvui.Rect{ .x = 8, .y = 6, .w = 8, .h = 6 },
        .color_fill = t.color(.content, .fill).opacity(0.58),
        .border = dvui.Rect.all(1),
    };
}

/// Debug-only button row (lighter tray).
pub fn debugTrayOpts() dvui.Options {
    const t = dvui.themeGet();
    return .{
        .style = .content,
        .corner_radius = dvui.Rect.all(6),
        .padding = dvui.Rect.all(5),
        .margin = dvui.Rect{ .x = 6, .y = 4, .w = 6, .h = 0 },
        .color_fill = t.color(.app1, .fill).opacity(0.22),
        .border = dvui.Rect.all(1),
    };
}

/// FPS / status strip under the toolbar.
pub fn statusStripOpts() dvui.Options {
    const t = dvui.themeGet();
    return .{
        .style = .content,
        .corner_radius = dvui.Rect.all(5),
        .padding = dvui.Rect{ .x = 8, .y = 3, .w = 8, .h = 3 },
        .margin = dvui.Rect{ .x = 8, .y = 0, .w = 8, .h = 4 },
        .color_fill = t.color(.content, .fill).opacity(0.4),
    };
}

/// Highlight for boolean toggles that are "on" (edges, layout, time run, etc.).
pub fn toggleOnAccent() dvui.Options {
    const t = dvui.themeGet();
    return .{
        .style = .highlight,
        .color_fill = t.color(.highlight, .fill).opacity(0.42),
    };
}

/// Hadron-cluster aggregate visualization (distinct from relational).
pub fn vizClustersAccent() dvui.Options {
    const t = dvui.themeGet();
    return .{
        .style = .app1,
        .color_fill = t.color(.app1, .fill).opacity(0.42),
    };
}

/// Advance-time / primary action (e.g. Step+).
pub fn primaryAccent() dvui.Options {
    const t = dvui.themeGet();
    return .{
        .style = .app1,
        .color_fill = t.color(.app1, .fill).opacity(0.48),
    };
}
