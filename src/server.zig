const std = @import("std");
const httpz = @import("httpz");

pub const Metrics = struct {
    timestamp_ns: i64 = 0,
    iaq: f32 = 0,
    iaq_accuracy: u8 = 0,
    accuracy_label: []const u8 = "stabilizing",
    co2_ppm: f32 = 0,
    voc_ppm: f32 = 0,
    temperature_c: f32 = 0,
    humidity_pct: f32 = 0,
    pressure_hpa: f32 = 0,
};

pub const SharedState = struct {
    mutex: std.Thread.Mutex = .{},
    value: Metrics = .{},

    pub fn set(self: *SharedState, metrics: Metrics) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.value = metrics;
    }

    pub fn get(self: *SharedState) Metrics {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.value;
    }
};

pub fn start(allocator: std.mem.Allocator, shared: *SharedState) !std.Thread {
    return std.Thread.spawn(.{}, run, .{ allocator, shared });
}

fn run(allocator: std.mem.Allocator, shared: *SharedState) void {
    runServer(allocator, shared) catch |err| {
        std.debug.print("HTTP server error: {}\n", .{err});
    };
}

fn runServer(allocator: std.mem.Allocator, shared: *SharedState) !void {
    var server = try httpz.Server(*SharedState).init(allocator, .{
        .port = 12000,
        .address = "0.0.0.0",
    }, shared);
    defer server.deinit();

    var router = try server.router(.{});
    router.get("/api/metrics", handleMetrics, .{});

    std.debug.print("HTTP server listening on port 12000\n", .{});
    try server.listen();
}

fn handleMetrics(shared: *SharedState, _: *httpz.Request, res: *httpz.Response) !void {
    const metrics = shared.get();
    try res.json(.{
        .timestamp_ns = metrics.timestamp_ns,
        .iaq = metrics.iaq,
        .iaq_accuracy = metrics.iaq_accuracy,
        .accuracy_label = metrics.accuracy_label,
        .co2_ppm = metrics.co2_ppm,
        .voc_ppm = metrics.voc_ppm,
        .temperature_c = metrics.temperature_c,
        .humidity_pct = metrics.humidity_pct,
        .pressure_hpa = metrics.pressure_hpa,
    }, .{});
}
