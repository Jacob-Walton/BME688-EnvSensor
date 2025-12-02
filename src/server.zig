const std = @import("std");
const httpz = @import("httpz");
const Version = @import("bsec.zig").Version;
const logger = @import("logger.zig");

var last_altitude: f32 = -1.0;
var last_altitude_timestamp_ns: i128 = 0;
var next_altitude_update_ns: i128 = 0;
var last_altimeter_hpa: f32 = 0.0;
var last_icao: [8]u8 = undefined;
var last_icao_len: usize = 0;
var last_metar_timestamp: [64]u8 = undefined;
var last_metar_timestamp_len: usize = 0;
var last_metar_observation_time: [64]u8 = undefined;
var last_metar_observation_time_len: usize = 0;

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
    logger: ?*logger.Logger = null,

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
    router.get("/api/altitude", handleRelativeAltitude, .{});
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
        .bsec_version = .{
            .major = shared.version.major,
            .minor = shared.version.minor,
            .major_bugfix = shared.version.major_bugfix,
            .minor_bugfix = shared.version.minor_bugfix,
        },
    }, .{});
}

const Altimeter = struct {
    value: f64,
};

const MetaInfo = struct {
    timestamp: []const u8,
};

const TimeInfo = struct {
    dt: []const u8,
};

const Metar = struct {
    altimeter: Altimeter,
    station: []const u8,
    meta: MetaInfo,
    time: TimeInfo,
};

const AltitudeResult = struct {
    altitude_ft: f32,
    altimeter_hpa: f32,
    icao: [8]u8,
    icao_len: usize,
    timestamp: [64]u8,
    timestamp_len: usize,
    observation_time: [64]u8,
    observation_time_len: usize,
};

fn handleRelativeAltitude(shared: *SharedState, _: *httpz.Request, res: *httpz.Response) !void {
    if (last_altitude != -1.0 and std.time.nanoTimestamp() < next_altitude_update_ns) {
        try res.json(.{
            .relative_altitude = last_altitude,
            .altimeter_hpa = last_altimeter_hpa,
            .icao = last_icao[0..last_icao_len],
            .updated_at = last_metar_timestamp[0..last_metar_timestamp_len],
            .observation_time = last_metar_observation_time[0..last_metar_observation_time_len],
        }, .{});
        return;
    }

    const metrics = shared.get();
    const result = relativeAltitude(metrics.pressure_hpa, shared.logger) catch |altitude_err| {
        if (shared.logger) |log| {
            log.err("Failed to get relative altitude: {}", .{altitude_err});
        }
        try res.json(.{
            .relative_altitude = 0,
            .error_message = @errorName(altitude_err),
        }, .{});
        return;
    };

    last_altitude = result.altitude_ft;
    last_altimeter_hpa = result.altimeter_hpa;
    last_altitude_timestamp_ns = std.time.nanoTimestamp();
    next_altitude_update_ns = last_altitude_timestamp_ns + 10_000_000_000; // 10 seconds

    // Copy from result to static buffers
    @memcpy(last_icao[0..result.icao_len], result.icao[0..result.icao_len]);
    last_icao_len = result.icao_len;
    @memcpy(last_metar_timestamp[0..result.timestamp_len], result.timestamp[0..result.timestamp_len]);
    last_metar_timestamp_len = result.timestamp_len;
    @memcpy(last_metar_observation_time[0..result.observation_time_len], result.observation_time[0..result.observation_time_len]);
    last_metar_observation_time_len = result.observation_time_len;

    try res.json(.{
        .relative_altitude = result.altitude_ft,
        .altimeter_hpa = result.altimeter_hpa,
        .icao = last_icao[0..last_icao_len],
        .updated_at = last_metar_timestamp[0..last_metar_timestamp_len],
        .observation_time = last_metar_observation_time[0..last_metar_observation_time_len],
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

    // Set content type
    const ext = std.fs.path.extension(file_path);
    if (std.mem.eql(u8, ext, ".js")) {
        res.header("content-type", "text/javascript; charset=utf-8");
    } else if (std.mem.eql(u8, ext, ".css")) {
        res.header("content-type", "text/css; charset=utf-8");
    } else if (std.mem.eql(u8, ext, ".html") or std.mem.eql(u8, ext, ".htm")) {
        res.header("content-type", "text/html; charset=utf-8");
    } else if (std.mem.eql(u8, ext, ".json")) {
        res.header("content-type", "application/json; charset=utf-8");
    } else if (std.mem.eql(u8, ext, ".png")) {
        res.header("content-type", "image/png");
    } else if (std.mem.eql(u8, ext, ".jpg") or std.mem.eql(u8, ext, ".jpeg")) {
        res.header("content-type", "image/jpeg");
    } else if (std.mem.eql(u8, ext, ".svg")) {
        res.header("content-type", "image/svg+xml");
    } else if (std.mem.eql(u8, ext, ".woff")) {
        res.header("content-type", "font/woff");
    } else if (std.mem.eql(u8, ext, ".woff2")) {
        res.header("content-type", "font/woff2");
    } else {
        res.content_type = contentType(file_path);
    }

    res.body = content[0..bytes_read];
}

fn contentType(path: []const u8) httpz.ContentType {
    const ext = std.fs.path.extension(path);
    if (ext.len < 2) return .BINARY;

    // Check common types first
    if (std.mem.eql(u8, ext, ".js")) return .JS;
    if (std.mem.eql(u8, ext, ".css")) return .CSS;
    if (std.mem.eql(u8, ext, ".html")) return .HTML;
    if (std.mem.eql(u8, ext, ".htm")) return .HTML;
    if (std.mem.eql(u8, ext, ".json")) return .JSON;
    if (std.mem.eql(u8, ext, ".png")) return .PNG;
    if (std.mem.eql(u8, ext, ".jpg")) return .JPG;
    if (std.mem.eql(u8, ext, ".jpeg")) return .JPG;
    if (std.mem.eql(u8, ext, ".gif")) return .GIF;
    if (std.mem.eql(u8, ext, ".svg")) return .SVG;
    if (std.mem.eql(u8, ext, ".ico")) return .ICO;
    if (std.mem.eql(u8, ext, ".woff")) return .WOFF;
    if (std.mem.eql(u8, ext, ".woff2")) return .WOFF2;
    if (std.mem.eql(u8, ext, ".ttf")) return .TTF;
    if (std.mem.eql(u8, ext, ".otf")) return .OTF;
    if (std.mem.eql(u8, ext, ".eot")) return .EOT;
    if (std.mem.eql(u8, ext, ".wasm")) return .WASM;
    if (std.mem.eql(u8, ext, ".pdf")) return .PDF;
    if (std.mem.eql(u8, ext, ".csv")) return .CSV;
    if (std.mem.eql(u8, ext, ".gz")) return .GZ;
    if (std.mem.eql(u8, ext, ".tar.gz")) return .GZ;
    if (std.mem.eql(u8, ext, ".tar")) return .TAR;
    if (std.mem.eql(u8, ext, ".xml")) return .XML;
    if (std.mem.eql(u8, ext, ".txt")) return .TEXT;
    if (std.mem.eql(u8, ext, ".webp")) return .WEBP;

    return .BINARY;
}

fn get_altitude(measured: f64, qnh: f64) f64 {
    const ratio = measured / qnh;
    return 44330.0 * (1.0 - std.math.pow(f64, ratio, 0.190284));
}

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

fn relativeAltitude(pressure_hpa: f32, log: ?*logger.Logger) !AltitudeResult {
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const env = get_api_key_from_env(allocator) catch |env_err| {
        if (log) |l| l.err("Failed to get API key from env: {}", .{env_err});
        return env_err;
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
    }) catch |fetch_err| {
        if (log) |l| l.err("METAR API request failed: {}", .{fetch_err});
        return fetch_err;
    };

    if (result.status != .ok) {
        if (log) |l| l.err("METAR API returned status: {}", .{result.status});
        return error.ApiRequestFailed;
    }

    const response_body = try body.toOwnedSlice();
    defer allocator.free(response_body);

    const parsed = std.json.parseFromSlice(Metar, allocator, response_body, .{
        .ignore_unknown_fields = true,
    }) catch |parse_err| {
        if (log) |l| l.err("Failed to parse METAR response: {}", .{parse_err});
        return parse_err;
    };
    defer parsed.deinit();

    const qnh = parsed.value.altimeter.value;
    const altitude = get_altitude(pressure_hpa, qnh);
    const altitude_ft = altitude * 3.28084;

    // Copy strings to stack buffers before parsed.deinit()
    var icao_buf: [8]u8 = undefined;
    var timestamp_buf: [64]u8 = undefined;
    var observation_time_buf: [64]u8 = undefined;

    const icao_len = @min(parsed.value.station.len, icao_buf.len);
    const timestamp_len = @min(parsed.value.meta.timestamp.len, timestamp_buf.len);
    const observation_time_len = @min(parsed.value.time.dt.len, observation_time_buf.len);

    @memcpy(icao_buf[0..icao_len], parsed.value.station[0..icao_len]);
    @memcpy(timestamp_buf[0..timestamp_len], parsed.value.meta.timestamp[0..timestamp_len]);
    @memcpy(observation_time_buf[0..observation_time_len], parsed.value.time.dt[0..observation_time_len]);

    return .{
        .altitude_ft = @as(f32, @floatCast(altitude_ft)),
        .altimeter_hpa = @as(f32, @floatCast(qnh)),
        .icao = icao_buf,
        .icao_len = icao_len,
        .timestamp = timestamp_buf,
        .timestamp_len = timestamp_len,
        .observation_time = observation_time_buf,
        .observation_time_len = observation_time_len,
    };
}
