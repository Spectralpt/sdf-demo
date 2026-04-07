const std = @import("std");
const math = std.math;

pub fn kelvinToColor(temp_in: i32) [3]f32 {
    // const temp = temp_in / 100;
    const temp_f: f32 = @floatFromInt(temp_in);
    const temp = temp_f / 100.0;
    var red: f32 = undefined;
    var green: f32 = undefined;
    var blue: f32 = undefined;

    if (temp <= 66) {
        red = 255;
    } else {
        red = temp - 60;
        red = 329.698727446 * (math.pow(f32, red, -0.1332047592));
        red = math.clamp(red, 0, 255);
    }

    if (temp <= 66) {
        green = temp;
        green = 99.4708025861 * @log(green) - 161.1195681661;
    } else {
        green = temp - 60;
        green = 288.1221695283 * (math.pow(f32, green, -0.0755148492));
        green = math.clamp(green, 0, 255);
    }

    if (temp >= 66) {
        blue = 255;
    } else {
        if (temp <= 19) {
            blue = 0;
        } else {
            blue = temp - 10;
            blue = 138.5177312231 * @log(blue) - 305.0447927307;
            blue = math.clamp(blue, 0, 255);
        }
    }

    std.debug.print("red:{d},green:{d},blue:{d}\n", .{ red, green, blue });

    return [_]f32{ red / 255.0, green / 255.0, blue / 255.0 };
}
