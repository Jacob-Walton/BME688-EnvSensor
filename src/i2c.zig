const std = @import("std");

// Linux I2C slave address ioctl
const I2C_SLAVE = 0x0703;

pub const I2cError = error{
    OpenFailed,
    SetAddressFailed,
    WriteFailed,
    ReadFailed,
};

/// Simple I2C device interface wrapper for Linux /dev/i2c-* devices
pub const I2c = struct {
    fd: std.posix.fd_t,

    const Self = @This();

    /// Initialize an I2C connection to the specified bus and slave address
    pub fn init(bus: []const u8, address: u8) I2cError!Self {
        const fd = std.posix.open(bus, .{ .ACCMODE = .RDWR }, 0) catch {
            return error.OpenFailed;
        };
        errdefer std.posix.close(fd);

        // Set the I2C slave address we want to communicate with
        const result = std.os.linux.ioctl(fd, I2C_SLAVE, @intCast(address));
        if (@as(isize, @bitCast(result)) < 0) {
            return error.SetAddressFailed;
        }

        return .{ .fd = fd };
    }

    pub fn deinit(self: *Self) void {
        std.posix.close(self.fd);
    }

    /// Write data to the I2C slave device
    pub fn write(self: *const Self, data: []const u8) I2cError!void {
        const written = std.posix.write(self.fd, data) catch return error.WriteFailed;
        if (written != data.len) return error.WriteFailed;
    }

    /// Read data from the I2C slave device
    pub fn read(self: *const Self, buffer: []u8) I2cError!void {
        const n = std.posix.read(self.fd, buffer) catch return error.ReadFailed;
        if (n != buffer.len) return error.ReadFailed;
    }
};
