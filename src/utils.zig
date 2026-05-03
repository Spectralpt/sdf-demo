const std = @import("std");
const math = std.math;
const zstbi = @import("zstbi");
const gl = @import("gl");

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

    // std.debug.print("red:{d},green:{d},blue:{d}\n", .{ red, green, blue });

    return [_]f32{ red / 255.0, green / 255.0, blue / 255.0 };
}

pub fn loadTexture(path: [:0]const u8, index: u32) !void {
    std.debug.print("loading asset: {s}\n", .{path});
    var image = try zstbi.Image.loadFromFile(path, 4);
    defer image.deinit();

    gl.BindTexture(gl.TEXTURE_2D, index);
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.REPEAT);
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.REPEAT);

    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR_MIPMAP_LINEAR);
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);

    const is_16_bit = image.bytes_per_component == 2;

    const internal_format: i32 = if (is_16_bit) gl.RGBA16 else gl.RGBA;
    const data_type: u32 = if (is_16_bit) gl.UNSIGNED_SHORT else gl.UNSIGNED_BYTE;

    gl.TexImage2D(
        gl.TEXTURE_2D,
        0,
        internal_format,
        @intCast(image.width),
        @intCast(image.height),
        0,
        gl.RGBA,
        data_type,
        image.data.ptr,
    );
    gl.GenerateMipmap(gl.TEXTURE_2D);
}
