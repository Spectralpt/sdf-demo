const std = @import("std");
const state = @import("state.zig");

pub fn processArgs(appState: *state.app_state, allocator: std.mem.Allocator) !void {
    // 1. Set your default values upfront
    appState.renderer.render_w = 1920;
    appState.renderer.render_h = 1080;
    appState.window_w = 1920;
    appState.window_h = 1080;
    appState.renderer.samples_per_frame = 0;
    // Assuming you have an `s` variable in your state. Let's default to 1.
    // appState.s_value = 1;

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    // 2. Skip the first argument (the executable path itself)
    _ = args.next();

    // 3. Loop through the remaining arguments
    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "-rw")) {
            const val = try getNextArgValue(&args, arg);
            appState.renderer.render_w = try std.fmt.parseInt(c_int, val, 10);
        } else if (std.mem.eql(u8, arg, "-rh")) {
            const val = try getNextArgValue(&args, arg);
            appState.renderer.render_h = try std.fmt.parseInt(c_int, val, 10);
        } else if (std.mem.eql(u8, arg, "-w")) {
            const val = try getNextArgValue(&args, arg);
            appState.window_w = try std.fmt.parseInt(c_int, val, 10);
        } else if (std.mem.eql(u8, arg, "-h")) {
            const val = try getNextArgValue(&args, arg);
            appState.window_h = try std.fmt.parseInt(c_int, val, 10);
        } else if (std.mem.eql(u8, arg, "-s")) {
            const val = try getNextArgValue(&args, arg);
            // Parse as an integer
            const s_val = try std.fmt.parseInt(c_int, val, 10);

            // Validate bounds (1 to 32)
            if (s_val < 1 or s_val > 32) {
                std.debug.print("Error: -s must be between 1 and 32. Got: {d}\n", .{s_val});
                return error.ValueOutOfBounds;
            }

            // Assign to your state (update this to match your actual state struct)
            appState.renderer.samples_per_frame = s_val;
        } else {
            std.debug.print("Warning: Unknown argument '{s}' ignored.\n", .{arg});
        }
    }
}

/// Helper function to grab the value after a flag safely
fn getNextArgValue(args: *std.process.ArgIterator, flagName: []const u8) ![]const u8 {
    return args.next() orelse {
        std.debug.print("Error: Missing expected value after '{s}' flag.\n", .{flagName});
        return error.MissingArgument;
    };
}
