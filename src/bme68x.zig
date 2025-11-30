const std = @import("std");
const i2c = @import("i2c.zig");

pub const c = @cImport({
    @cInclude("bme68x.h");
});

pub const Bme68xError = error{
    InitFailed,
    ConfigFailed,
    MeasurementFailed,
    OutOfMemory,
};

pub const SensorData = struct {
    temperature: f32,
    pressure: f32,
    humidity: f32,
    gas_resistance: f32,
    gas_valid: bool,
    heat_stable: bool,
};

pub const Bme68x = struct {
    dev: c.bme68x_dev,
    i2c_dev: i2c.I2c,
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, i2c_bus: []const u8, address: u8) !*Self {
        const self = allocator.create(Self) catch return error.OutOfMemory;
        errdefer allocator.destroy(self);

        self.allocator = allocator;
        self.i2c_dev = try i2c.I2c.init(i2c_bus, address);
        errdefer self.i2c_dev.deinit();

        self.dev = std.mem.zeroes(c.bme68x_dev);
        self.dev.intf = c.BME68X_I2C_INTF;
        self.dev.read = bme68xI2cRead;
        self.dev.write = bme68xI2cWrite;
        self.dev.delay_us = bme68xDelayUs;
        self.dev.intf_ptr = @ptrCast(&self.i2c_dev);
        self.dev.amb_temp = 20;

        const result = c.bme68x_init(&self.dev);
        if (result != c.BME68X_OK) {
            std.debug.print("BME68x init failed: {}\n", .{result});
            return error.InitFailed;
        }

        return self;
    }

    pub fn deinit(self: *Self) void {
        self.i2c_dev.deinit();
        self.allocator.destroy(self);
    }

    pub fn configure(self: *Self, options: ConfigOptions) !void {
        var conf: c.bme68x_conf = undefined;
        var result = c.bme68x_get_conf(&conf, &self.dev);
        if (result != c.BME68X_OK) return error.ConfigFailed;

        conf.os_temp = options.temp_oversampling;
        conf.os_pres = options.pressure_oversampling;
        conf.os_hum = options.humidity_oversampling;
        conf.filter = options.filter;

        result = c.bme68x_set_conf(&conf, &self.dev);
        if (result != c.BME68X_OK) return error.ConfigFailed;

        var heatr_conf = std.mem.zeroes(c.bme68x_heatr_conf);
        heatr_conf.enable = c.BME68X_ENABLE;
        heatr_conf.heatr_temp = options.heater_temp;
        heatr_conf.heatr_dur = options.heater_duration;

        result = c.bme68x_set_heatr_conf(c.BME68X_FORCED_MODE, &heatr_conf, &self.dev);
        if (result != c.BME68X_OK) return error.ConfigFailed;
    }

    pub fn measure(self: *Self) !SensorData {
        var result = c.bme68x_set_op_mode(c.BME68X_FORCED_MODE, &self.dev);
        if (result != c.BME68X_OK) return error.MeasurementFailed;

        var conf: c.bme68x_conf = undefined;
        _ = c.bme68x_get_conf(&conf, &self.dev);
        const meas_dur = c.bme68x_get_meas_dur(c.BME68X_FORCED_MODE, &conf, &self.dev);
        const delay_us: u64 = @intCast(meas_dur + 100_000);
        std.Thread.sleep(delay_us * 1000);

        var data: c.bme68x_data = undefined;
        var n_fields: u8 = 0;
        result = c.bme68x_get_data(c.BME68X_FORCED_MODE, &data, &n_fields, &self.dev);
        if (result != c.BME68X_OK) return error.MeasurementFailed;

        return .{
            .temperature = data.temperature,
            .pressure = data.pressure,
            .humidity = data.humidity,
            .gas_resistance = data.gas_resistance,
            .gas_valid = (data.status & c.BME68X_GASM_VALID_MSK) != 0,
            .heat_stable = (data.status & c.BME68X_HEAT_STAB_MSK) != 0,
        };
    }

    pub const ConfigOptions = struct {
        temp_oversampling: u8 = c.BME68X_OS_2X,
        pressure_oversampling: u8 = c.BME68X_OS_2X,
        humidity_oversampling: u8 = c.BME68X_OS_2X,
        filter: u8 = c.BME68X_FILTER_OFF,
        heater_temp: u16 = 300,
        heater_duration: u16 = 100,
    };
};

fn bme68xI2cRead(reg_addr: u8, reg_data: [*c]u8, len: u32, intf_ptr: ?*anyopaque) callconv(.c) i8 {
    const dev: *i2c.I2c = @ptrCast(@alignCast(intf_ptr orelse return -1));
    dev.write(&.{reg_addr}) catch return -1;
    dev.read(reg_data[0..len]) catch return -1;

    return 0;
}

fn bme68xI2cWrite(reg_addr: u8, reg_data: [*c]const u8, len: u32, intf_ptr: ?*anyopaque) callconv(.c) i8 {
    const dev: *i2c.I2c = @ptrCast(@alignCast(intf_ptr orelse return -1));
    var buf: [256]u8 = undefined;
    buf[0] = reg_addr;
    @memcpy(buf[1..][0..len], reg_data[0..len]);
    dev.write(buf[0 .. len + 1]) catch return -1;
    return 0;
}

fn bme68xDelayUs(period: u32, intf_ptr: ?*anyopaque) callconv(.c) void {
    _ = intf_ptr;
    std.Thread.sleep(@as(u64, period) * 1000);
}
