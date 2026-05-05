const std = @import("std");
const state = @import("state.zig");

pub fn processArgs(appState: *state.app_state, allocator: std.mem.Allocator) !void {
    var args = try std.process.argsWithAllocator(allocator);
    var argsArray: std.ArrayList([:0]const u8) = .empty;
    defer argsArray.deinit(allocator);
    defer args.deinit();
    while (args.next()) |arg| {
        try argsArray.append(allocator, arg);
    }

    // if (argsArray.items.len < 5) {
    //     std.debug.print("Usage: sdf-demos <render_w> <render_h> <window_w> <window_h>\n", .{});
    //     return;
    // }

    appState.renderer.render_w = 1920;
    appState.renderer.render_h = 1080;

    appState.window_w = 1920;
    appState.window_h = 1080;

    if (argsArray.items.len >= 5) {
        appState.renderer.render_w = try std.fmt.parseInt(c_int, argsArray.items[1], 10);
        appState.renderer.render_h = try std.fmt.parseInt(c_int, argsArray.items[2], 10);

        appState.window_w = try std.fmt.parseInt(c_int, argsArray.items[3], 10);
        appState.window_h = try std.fmt.parseInt(c_int, argsArray.items[4], 10);
    }
}
