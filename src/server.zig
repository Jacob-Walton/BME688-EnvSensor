const std = @import("std");
const httpz = @import("httpz");
const Version = @import("bsec.zig").Version;

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
    raw_pressure_hpa: f32 = 0,
};

pub const SharedState = struct {
    mutex: std.Thread.Mutex = .{},
    value: Metrics = .{},
    version: Version = .{ .major = 0, .minor = 0, .major_bugfix = 0, .minor_bugfix = 0 },

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
    router.get("/*", handleStatic, .{});

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
        .bsec_version = .{
            .major = shared.version.major,
            .minor = shared.version.minor,
            .major_bugfix = shared.version.major_bugfix,
            .minor_bugfix = shared.version.minor_bugfix,
        },
    }, .{});
}

fn handleStatic(_: *SharedState, req: *httpz.Request, res: *httpz.Response) !void {
    const path = req.url.path;

    // Prevent directory traversal
    if (std.mem.indexOf(u8, path, "..") != null) {
        res.status = 403;
        res.body = "Forbidden";
        return;
    }

    // Determine file path
    const file_path = if (std.mem.eql(u8, path, "/"))
        "public/index.html"
    else
        try std.fmt.allocPrint(res.arena, "public{s}", .{path});

    // Try to open and read the file
    const file = std.fs.cwd().openFile(file_path, .{}) catch {
        res.status = 404;
        res.body = "Not Found";
        return;
    };
    defer file.close();

    const stat = try file.stat();
    const content = try res.arena.alloc(u8, stat.size);
    const bytes_read = try file.readAll(content);

    res.content_type = contentType(file_path);
    res.body = content[0..bytes_read];
}

fn contentType(path: []const u8) httpz.ContentType {
    const ext = std.fs.path.extension(path);
    if (ext.len < 2) return .BINARY;

    switch (ext.len) {
        4 => switch (ext[1]) {
            'h' => if (std.mem.eql(u8, ext, ".htm")) return .HTML,
            'c' => if (std.mem.eql(u8, ext, ".css")) return .CSS,
            'j' => if (std.mem.eql(u8, ext, ".js")) return .JS,
            'p' => if (std.mem.eql(u8, ext, ".png")) return .PNG,
            'g' => if (std.mem.eql(u8, ext, ".gif")) return .GIF,
            'i' => if (std.mem.eql(u8, ext, ".ico")) return .ICO,
            't' => if (std.mem.eql(u8, ext, ".ttf")) return .TTF,
            'w' => if (std.mem.eql(u8, ext, ".wasm")) return .WASM,
            'o' => if (std.mem.eql(u8, ext, ".otf")) return .OTF,
            'e' => if (std.mem.eql(u8, ext, ".eot")) return .EOT,
            else => {},
        },
        5 => switch (ext[1]) {
            'h' => if (std.mem.eql(u8, ext, ".html")) return .HTML,
            'c' => if (std.mem.eql(u8, ext, ".csv")) return .CSV,
            'j' => if (std.mem.eql(u8, ext, ".json")) return .JSON,
            'p' => if (std.mem.eql(u8, ext, ".pdf")) return .PDF,
            't' => if (std.mem.eql(u8, ext, ".ttf")) return .TTF,
            'w' => if (std.mem.eql(u8, ext, ".woff")) return .WOFF,
            else => {},
        },
        6 => switch (ext[1]) {
            'j' => if (std.mem.eql(u8, ext, ".jpeg")) return .JPG,
            'w' => if (std.mem.eql(u8, ext, ".woff2")) return .WOFF2,
            's' => if (std.mem.eql(u8, ext, ".svg")) return .SVG,
            else => {},
        },
        7 => switch (ext[1]) {
            't' => if (std.mem.eql(u8, ext, ".tar.gz")) return .GZ,
            else => {},
        },
        else => {},
    }

    if (std.mem.eql(u8, ext, ".jpg")) return .JPG;
    if (std.mem.eql(u8, ext, ".gz")) return .GZ;
    if (std.mem.eql(u8, ext, ".xml")) return .XML;
    if (std.mem.eql(u8, ext, ".txt")) return .TEXT;
    if (std.mem.eql(u8, ext, ".tar")) return .TAR;
    if (std.mem.eql(u8, ext, ".webp")) return .WEBP;

    return .BINARY;
}
