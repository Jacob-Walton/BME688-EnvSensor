const std = @import("std");
const Bme68x = @import("bme68x.zig").Bme68x;

const Metrics = struct {
    timestamp_ns: i64 = 0,
    iaq: f32 = 0,
    iaq_accuracy: u8 = 0,
    accuracy_label: []const u8 = "stabilizing",
    co2_ppm: f32 = 0,
    voc_ppm: f32 = 0,
    temperature_c: f32 = 0,
    humidity_pct: f32 = 0,
    pressure_hpa: f32 = 0,

    const Self = @This();

    pub fn toJson(self: Self, buf: []u8) ![]const u8 {
        var writer: std.io.Writer = .fixed(buf);
        var stringifier: std.json.Stringify = .{
            .writer = &writer,
            .options = .{},
        };
        try stringifier.write(self);
        return writer.buffered();
    }

    pub fn toJsonPretty(self: Self, buf: []u8) ![]const u8 {
        var writer: std.io.Writer = .fixed(buf);
        var stringifier: std.json.Stringify = .{
            .writer = &writer,
            .options = .{ .whitespace = .indent_2 },
        };
        try stringifier.write(self);
        return writer.buffered();
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const sensor = try Bme68x.init(allocator, "/dev/i2c-1", 0x76);
    defer sensor.deinit();

    var buf: [1024]u8 = undefined;

    const start_time = std.time.nanoTimestamp();
    var next_time = start_time;

    while (true) {
        const current_time = std.time.nanoTimestamp();

        if (current_time >= next_time) {
            next_time = current_time + 5_000_000_000; // 5s

            const data = sensor.measure() catch continue;

            var writer: std.io.Writer = .fixed(&buf);
            var stringifier: std.json.Stringify = .{
                .writer = &writer,
                .options = .{ .whitespace = .indent_2 },
            };

            try stringifier.write(&data);
            std.debug.print("Measurement: {s}\n", .{writer.buffered()});
        }
    }
}
