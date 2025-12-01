const std = @import("std");
const httpz = @import("httpz");
const Version = @import("bsec.zig").Version;
const logger = @import("logger.zig");

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
        const log = logger.Logger.init(allocator, "/var/log/bme688_sensor.log") catch return;
        defer log.deinit();
        log.err("HTTP server error: {}", .{err});
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
        .raw_pressure_hpa = metrics.raw_pressure_hpa,
        .relative_altitude = relativeAltitude(metrics.pressure_hpa) catch 0,
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

fn get_altitude(measured: f64, qnh: f64) f64 {
    const ratio = measured / qnh;
    return 44330.0 * (1.0 - std.math.pow(f64, ratio, 0.190284));
}

const Altimeter = struct {
    value: f64,
};

const Metar = struct {
    altimeter: Altimeter,
};

fn get_api_key_from_env(allocator: std.mem.Allocator) !struct { icao: []const u8, api_key: []const u8 } {
    var file = try std.fs.cwd().openFile(".env", .{});
    defer file.close();

    const content = try file.readToEndAlloc(allocator, 1024 * 1024);
    defer allocator.free(content);

    var api_key: ?[]const u8 = null;
    var icao: ?[]const u8 = null;

    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \r\t");
        if (trimmed.len == 0 or trimmed[0] == '#') continue;

        if (std.mem.indexOf(u8, trimmed, "API_KEY=")) |_| {
            const key_start = std.mem.indexOf(u8, trimmed, "=").? + 1;
            api_key = try allocator.dupe(u8, trimmed[key_start..]);
        } else if (std.mem.indexOf(u8, trimmed, "ICAO=")) |_| {
            const key_start = std.mem.indexOf(u8, trimmed, "=").? + 1;
            icao = try allocator.dupe(u8, trimmed[key_start..]);
        }
    }

    if (api_key == null) return error.MissingApiKey;
    if (icao == null) return error.MissingIcao;

    return .{ .icao = icao.?, .api_key = api_key.? };
}

fn relativeAltitude(pressure_hpa: f32) !f32 {
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const log = logger.Logger.init(allocator, "/var/log/bme688_sensor.log") catch return 0;
    defer log.deinit();

    const env = get_api_key_from_env(allocator) catch |err| {
        log.err("Failed to get API key from env: {}", .{err});
        return error.MissingApiKey;
    };
    defer allocator.free(env.api_key);
    defer allocator.free(env.icao);

    var client: std.http.Client = .{ .allocator = allocator };
    defer client.deinit();

    var redirect_buffer: [8192]u8 = undefined;

    var body: std.Io.Writer.Allocating = .init(allocator);
    defer body.deinit();

    const bearer = try std.fmt.allocPrint(allocator, "Bearer {s}", .{env.api_key});
    defer allocator.free(bearer);

    const url = try std.fmt.allocPrint(allocator, "https://metar.konpeki.co.uk/api/metar/{s}", .{env.icao});
    defer allocator.free(url);

    const result = client.fetch(.{
        .location = .{ .url = url },
        .method = .GET,
        .redirect_buffer = &redirect_buffer,
        .response_writer = &body.writer,
        .headers = .{
            .authorization = .{ .override = bearer },
        },
    }) catch |err| {
        log.err("METAR API request failed: {}", .{err});
        return err;
    };

    if (result.status != .ok) {
        log.err("METAR API returned status: {}", .{result.status});
        std.debug.print("Request failed with status: {}\n", .{result.status});
        return error.ApiRequestFailed;
    }

    const response_body = try body.toOwnedSlice();
    defer allocator.free(response_body);

    // Parse the returned Json into a Metar struct
    const parsed = std.json.parseFromSlice(Metar, allocator, response_body, .{
        .ignore_unknown_fields = true,
    }) catch |err| {
        log.err("Failed to parse METAR response: {}", .{err});
        return err;
    };
    defer parsed.deinit();

    const qnh = parsed.value.altimeter.value;
    const altitude = get_altitude(pressure_hpa, qnh);
    const altitude_ft = altitude * 3.28084;

    return @as(f32, @floatCast(altitude_ft));
}
