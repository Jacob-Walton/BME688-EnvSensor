const std = @import("std");

pub const LogLevel = enum {
    debug,
    info,
    warn,
    err,

    fn toString(self: LogLevel) []const u8 {
        return switch (self) {
            .debug => "DEBUG",
            .info => "INFO",
            .warn => "WARN",
            .err => "ERROR",
        };
    }
};

/// Thread-safe file-based logger with ISO 8601 timestamps
pub const Logger = struct {
    file: std.fs.File,
    mutex: std.Thread.Mutex = .{},
    allocator: std.mem.Allocator,

    const Self = @This();

    /// Initialize logger, creating parent directories if needed
    /// Falls back to ./bme688_sensor.log if absolute path fails
    pub fn init(allocator: std.mem.Allocator, log_path: []const u8) !*Self {
        const self = try allocator.create(Self);
        errdefer allocator.destroy(self);

        // Try to create the log file, creating directories as needed
        const file = openOrCreateLogFile(log_path) catch |open_err| blk: {
            // Fallback to local log file
            std.debug.print("Warning: Cannot open {s}: {}. Using ./bme688_sensor.log instead\n", .{ log_path, open_err });
            break :blk std.fs.cwd().createFile("bme688_sensor.log", .{
                .truncate = false,
                .read = true,
            }) catch |create_err| {
                std.debug.print("Error: Cannot create fallback log file: {}\n", .{create_err});
                return create_err;
            };
        };
        errdefer file.close();

        try file.seekFromEnd(0);

        self.* = .{
            .file = file,
            .allocator = allocator,
        };

        return self;
    }

    pub fn deinit(self: *Self) void {
        self.file.close();
        self.allocator.destroy(self);
    }

    pub fn log(self: *Self, level: LogLevel, comptime format: []const u8, args: anytype) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        const timestamp = std.time.timestamp();
        const dt = timestampToDateTime(timestamp);

        // Format the log message into a buffer
        var buf: [4096]u8 = undefined;
        const message = std.fmt.bufPrint(&buf, "[{d:0>4}-{d:0>2}-{d:0>2} {d:0>2}:{d:0>2}:{d:0>2}] [{s}] " ++ format ++ "\n", .{
            dt.year,
            dt.month,
            dt.day,
            dt.hour,
            dt.minute,
            dt.second,
            level.toString(),
        } ++ args) catch return;

        _ = self.file.writeAll(message) catch return;
    }

    pub fn debug(self: *Self, comptime format: []const u8, args: anytype) void {
        self.log(.debug, format, args);
    }

    pub fn info(self: *Self, comptime format: []const u8, args: anytype) void {
        self.log(.info, format, args);
    }

    pub fn warn(self: *Self, comptime format: []const u8, args: anytype) void {
        self.log(.warn, format, args);
    }

    pub fn err(self: *Self, comptime format: []const u8, args: anytype) void {
        self.log(.err, format, args);
    }
};

fn openOrCreateLogFile(log_path: []const u8) !std.fs.File {
    // Try to open the file directly first
    if (std.fs.openFileAbsolute(log_path, .{ .mode = .read_write })) |file| {
        return file;
    } else |_| {
        // File doesn't exist, try to create it
        // First, ensure the directory exists
        if (std.fs.path.dirname(log_path)) |dir_path| {
            std.fs.makeDirAbsolute(dir_path) catch |make_err| switch (make_err) {
                error.PathAlreadyExists => {}, // Directory already exists
                else => return make_err,
            };
        }

        // Now try to create the file
        return std.fs.createFileAbsolute(log_path, .{
            .truncate = false,
            .read = true,
        });
    }
}

const DateTime = struct {
    year: u16,
    month: u8,
    day: u8,
    hour: u8,
    minute: u8,
    second: u8,
};

/// Convert Unix timestamp to broken-down date/time components
fn timestampToDateTime(timestamp: i64) DateTime {
    const seconds_per_day = 86400;
    const days_since_epoch = @divFloor(timestamp, seconds_per_day);
    const seconds_today = @mod(timestamp, seconds_per_day);

    const hour: u8 = @intCast(@divFloor(seconds_today, 3600));
    const minute: u8 = @intCast(@divFloor(@mod(seconds_today, 3600), 60));
    const second: u8 = @intCast(@mod(seconds_today, 60));

    var year: u16 = 1970;
    var days_remaining = days_since_epoch;

    while (true) {
        const days_in_year: i64 = if (isLeapYear(year)) 366 else 365;
        if (days_remaining < days_in_year) break;
        days_remaining -= days_in_year;
        year += 1;
    }

    const is_leap = isLeapYear(year);
    const months = [_]u8{ 31, if (is_leap) 29 else 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };
    var month: u8 = 1;
    for (months) |days_in_month| {
        if (days_remaining < days_in_month) break;
        days_remaining -= days_in_month;
        month += 1;
    }

    const day: u8 = @intCast(days_remaining + 1);

    return .{
        .year = year,
        .month = month,
        .day = day,
        .hour = hour,
        .minute = minute,
        .second = second,
    };
}

/// Check if year is a leap year using Gregorian calendar rules
fn isLeapYear(year: u16) bool {
    return (year % 4 == 0 and year % 100 != 0) or (year % 400 == 0);
}
