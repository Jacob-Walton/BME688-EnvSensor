const std = @import("std");
const Bme68x = @import("bme68x.zig").Bme68x;
const bsec = @import("bsec.zig");
const bsec_config = @import("config.zig").bsec_config;

const STATE_FILE = "/var/lib/bsec_state.bin";
const SAVE_INTERVAL_NS = 5 * 60 * std.time.ns_per_s; // Save every 5 mins

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

const SharedState = struct {
    mutex: std.Thread.Mutex = .{},
    value: Metrics = .{},

    fn set(self: *SharedState, metrics: Metrics) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.value = metrics;
    }

    fn get(self: *SharedState) Metrics {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.value;
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const sensor = try Bme68x.init(allocator, "/dev/i2c-1", 0x76);
    defer sensor.deinit();

    var bsec_inst = try bsec.Bsec.init(allocator);
    defer bsec_inst.deinit();

    var shared = SharedState{};
    const http_thread = try startHttpServer(allocator, &shared);
    http_thread.detach();

    const ver = try bsec_inst.getVersion();
    std.debug.print("BSEC {}.{}.{}.{}\n", .{ ver.major, ver.minor, ver.major_bugfix, ver.minor_bugfix });

    try bsec_inst.setConfiguration(&bsec_config);

    // Load saved state if it exists
    if (loadState(&bsec_inst)) {
        std.debug.print("Loaded saved state\n", .{});
    } else {
        std.debug.print("No saved state, starting fresh\n", .{});
    }

    const sample_rate = bsec.SAMPLE_RATE_LP;
    try bsec_inst.updateSubscription(&.{
        .{ .output = .iaq, .sample_rate = sample_rate },
        .{ .output = .static_iaq, .sample_rate = sample_rate },
        .{ .output = .co2_equivalent, .sample_rate = sample_rate },
        .{ .output = .breath_voc_equivalent, .sample_rate = sample_rate },
        .{ .output = .heat_compensated_temperature, .sample_rate = sample_rate },
        .{ .output = .heat_compensated_humidity, .sample_rate = sample_rate },
        .{ .output = .raw_pressure, .sample_rate = sample_rate },
    });

    var last_save: i128 = std.time.nanoTimestamp();

    while (true) {
        const timestamp_ns = std.time.nanoTimestamp();
        const settings = try bsec_inst.sensorControl(timestamp_ns);
        if (settings.trigger_measurement) {
            const temp_os = if (settings.temperature_oversampling == 0) @as(u8, 1) else settings.temperature_oversampling;
            const pres_os = if (settings.pressure_oversampling == 0) @as(u8, 1) else settings.pressure_oversampling;
            const hum_os = if (settings.humidity_oversampling == 0) @as(u8, 1) else settings.humidity_oversampling;

            sensor.configure(.{
                .temp_oversampling = temp_os,
                .pressure_oversampling = pres_os,
                .humidity_oversampling = hum_os,
                .heater_temp = settings.heater_temperature,
                .heater_duration = settings.heater_duration,
            }) catch continue;

            const data = sensor.measure() catch continue;

            const outputs = bsec_inst.doSteps(
                timestamp_ns,
                if (settings.shouldProcess(.temperature)) data.temperature else null,
                if (settings.shouldProcess(.humidity)) data.humidity else null,
                if (settings.shouldProcess(.pressure)) data.pressure else null,
                if (settings.shouldProcess(.gas)) data.gas_resistance else null,
                null,
            ) catch continue;

            printOutputs(outputs);
            updateSharedMetrics(outputs, timestamp_ns, &shared);

            if (timestamp_ns - last_save > SAVE_INTERVAL_NS) {
                saveState(&bsec_inst);
                last_save = timestamp_ns;
            }
        }
    }
}

fn loadState(bsec_inst: *bsec.Bsec) bool {
    const file = std.fs.openFileAbsolute(STATE_FILE, .{}) catch return false;
    defer file.close();

    var buf: [bsec.MAX_STATE_BLOB_SIZE]u8 = undefined;
    const n = file.readAll(&buf) catch return false;

    if (n == 0) return false;

    bsec_inst.setState(buf[0..n]) catch return false;
    return true;
}

fn saveState(bsec_inst: *bsec.Bsec) void {
    var buf: [bsec.MAX_STATE_BLOB_SIZE]u8 = undefined;
    const state = bsec_inst.getState(&buf) catch return;

    const file = std.fs.createFileAbsolute(STATE_FILE, .{}) catch return;
    defer file.close();

    file.writeAll(state) catch return;
    std.debug.print("State saved\n", .{});
}

fn printOutputs(outputs: []bsec.SensorOutput) void {
    const data = gatherMetrics(outputs);

    std.debug.print("{d:.1}C  {d:.1}%  {d:.0}hPa  IAQ:{d:.0}({s})  CO2:{d:.0}ppm  VOC:{d:.2}ppm\n", .{
        data.temperature_c,
        data.humidity_pct,
        data.pressure_hpa,
        data.iaq,
        data.accuracy_label,
        data.co2_ppm,
        data.voc_ppm,
    });
}

fn updateSharedMetrics(outputs: []bsec.SensorOutput, timestamp_ns: i128, shared: *SharedState) void {
    var data = gatherMetrics(outputs);
    data.timestamp_ns = @as(i64, @intCast(timestamp_ns));
    shared.set(data);
}

fn gatherMetrics(outputs: []bsec.SensorOutput) Metrics {
    var iaq: ?f32 = null;
    var iaq_acc: u8 = 0;
    var co2: ?f32 = null;
    var voc: ?f32 = null;
    var temp: ?f32 = null;
    var hum: ?f32 = null;
    var pres: ?f32 = null;

    for (outputs) |out| {
        switch (out.sensor_id) {
            .iaq => {
                iaq = out.signal;
                iaq_acc = out.accuracy;
            },
            .co2_equivalent => co2 = out.signal,
            .breath_voc_equivalent => voc = out.signal,
            .heat_compensated_temperature => temp = out.signal,
            .heat_compensated_humidity => hum = out.signal,
            .raw_pressure => pres = out.signal,
            else => {},
        }
    }

    const accuracy_str = accuracyLabel(iaq_acc);

    return .{
        .iaq = iaq orelse 0,
        .iaq_accuracy = iaq_acc,
        .accuracy_label = accuracy_str,
        .co2_ppm = co2 orelse 0,
        .voc_ppm = voc orelse 0,
        .temperature_c = temp orelse 0,
        .humidity_pct = hum orelse 0,
        .pressure_hpa = if (pres) |p| p / 100.0 else 0,
    };
}

fn accuracyLabel(accuracy: u8) []const u8 {
    return switch (accuracy) {
        0 => "stabilizing",
        1 => "low",
        2 => "medium",
        3 => "high",
        else => "?",
    };
}

fn startHttpServer(allocator: std.mem.Allocator, shared: *SharedState) !std.Thread {
    return std.Thread.spawn(.{}, httpLoop, .{ allocator, shared });
}

fn httpLoop(allocator: std.mem.Allocator, shared: *SharedState) !void {
    _ = allocator; // Future use

    const address = try std.net.Address.parseIp("0.0.0.0", 12000);
    var server = try std.net.Address.listen(address, .{ .reuse_address = true });
    defer server.deinit();

    while (true) {
        const conn = server.accept() catch continue;
        var stream = conn.stream;
        handleConnection(&stream, shared) catch {};
        stream.close();
    }
}

fn handleConnection(stream: *std.net.Stream, shared: *SharedState) !void {
    var buf: [2048]u8 = undefined;
    const n = try stream.read(&buf);
    if (n == 0) return;

    const req = buf[0..n];
    const first_line_end = std.mem.indexOf(u8, req, "\r\n") orelse return;
    const first_line = req[0..first_line_end];
    if (!std.mem.startsWith(u8, first_line, "GET ")) {
        try respond(stream, "405 Method Not Allowed", "text/plain", "method not allowed");
        return;
    }

    const after_method = first_line[4..];
    const space_idx = std.mem.indexOfScalar(u8, after_method, ' ') orelse return;
    const target = after_method[0..space_idx];

    if (std.mem.eql(u8, target, "/api/metrics")) {
        const metrics = shared.get();
        var json_buf: [512]u8 = undefined;
        const body = try metrics.toJson(&json_buf);

        try respond(stream, "200 OK", "application/json", body);
    } else {
        try respond(stream, "404 Not Found", "text/plain", "not found");
    }
}

fn respond(stream: *std.net.Stream, status: []const u8, content_type: []const u8, body: []const u8) !void {
    var header_buf: [256]u8 = undefined;
    const header = try std.fmt.bufPrint(
        &header_buf,
        "HTTP/1.1 {s}\r\nContent-Type: {s}\r\nCache-Control: no-store\r\nContent-Length: {d}\r\nConnection: close\r\n\r\n",
        .{ status, content_type, body.len },
    );
    try stream.writeAll(header);
    try stream.writeAll(body);
}
