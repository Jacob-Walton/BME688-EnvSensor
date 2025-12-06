const std = @import("std");

// BSEC (Bosch Sensortec Environmental Cluster) library C interface
// Provides air quality and environmental sensor data fusion with machine learning
pub const c = @cImport({
    @cInclude("bsec_interface.h");
    @cInclude("bsec_datatypes.h");
});

// Re-export common BSEC sample rates: LP=Low Power, ULP=Ultra Low Power, CONT=Continuous
pub const SAMPLE_RATE_LP = c.BSEC_SAMPLE_RATE_LP;
pub const SAMPLE_RATE_ULP = c.BSEC_SAMPLE_RATE_ULP;
pub const SAMPLE_RATE_CONT = c.BSEC_SAMPLE_RATE_CONT;
pub const SAMPLE_RATE_DISABLED = c.BSEC_SAMPLE_RATE_DISABLED;

pub const MAX_PHYSICAL_SENSOR = c.BSEC_MAX_PHYSICAL_SENSOR;
pub const NUMBER_OUTPUTS = c.BSEC_NUMBER_OUTPUTS;
pub const MAX_STATE_BLOB_SIZE = c.BSEC_MAX_STATE_BLOB_SIZE;
pub const MAX_PROPERTY_BLOB_SIZE = c.BSEC_MAX_PROPERTY_BLOB_SIZE;
pub const MAX_WORKBUFFER_SIZE = c.BSEC_MAX_WORKBUFFER_SIZE;

// Virtual sensor outputs
pub const Output = enum(u8) {
    iaq = c.BSEC_OUTPUT_IAQ,
    static_iaq = c.BSEC_OUTPUT_STATIC_IAQ,
    co2_equivalent = c.BSEC_OUTPUT_CO2_EQUIVALENT,
    breath_voc_equivalent = c.BSEC_OUTPUT_BREATH_VOC_EQUIVALENT,
    raw_temperature = c.BSEC_OUTPUT_RAW_TEMPERATURE,
    raw_pressure = c.BSEC_OUTPUT_RAW_PRESSURE,
    raw_humidity = c.BSEC_OUTPUT_RAW_HUMIDITY,
    raw_gas = c.BSEC_OUTPUT_RAW_GAS,
    stabilization_status = c.BSEC_OUTPUT_STABILIZATION_STATUS,
    run_in_status = c.BSEC_OUTPUT_RUN_IN_STATUS,
    heat_compensated_temperature = c.BSEC_OUTPUT_SENSOR_HEAT_COMPENSATED_TEMPERATURE,
    heat_compensated_humidity = c.BSEC_OUTPUT_SENSOR_HEAT_COMPENSATED_HUMIDITY,
    compensated_gas = c.BSEC_OUTPUT_COMPENSATED_GAS,
    gas_percentage = c.BSEC_OUTPUT_GAS_PERCENTAGE,
    _,
};

// Physical sensor inputs
pub const Input = enum(u8) {
    pressure = c.BSEC_INPUT_PRESSURE,
    humidity = c.BSEC_INPUT_HUMIDITY,
    temperature = c.BSEC_INPUT_TEMPERATURE,
    gas_resistance = c.BSEC_INPUT_GASRESISTOR,
    heat_source = c.BSEC_INPUT_HEATSOURCE,
    disable_baseline_tracker = c.BSEC_INPUT_DISABLE_BASELINE_TRACKER,
    profile_part = c.BSEC_INPUT_PROFILE_PART,
    _,
};

pub const BsecError = error{
    InvalidInput,
    ValueLimits,
    DuplicateInput,
    NoOutputsReturnable,
    WrongDataRate,
    SampleRateLimits,
    DuplicateGate,
    InvalidSampleRate,
    GateCountExceedsArray,
    SamplingIntervalIntegerMult,
    MultGasSamplingInterval,
    HighHeaterOnDuration,
    ParseSectionExceedsWorkBuffer,
    ConfigFail,
    ConfigCrcMismatch,
    ConfigVersionMismatch,
    ConfigFeatureMismatch,
    ConfigEmpty,
    ConfigInsufficientWorkBuffer,
    ConfigInvalidStringSize,
    ConfigInsufficientBuffer,
    SetInvalidChannelIdentifier,
    SetInvalidLength,
    OutOfMemory,
    Unknown,
};

/// Convert BSEC C library return codes to Zig error types.
/// Most warnings are treated as success since they're non-fatal informational messages.
fn mapBsecError(ret: c.bsec_library_return_t) BsecError!void {
    return switch (ret) {
        c.BSEC_OK => {},
        c.BSEC_E_DOSTEPS_INVALIDINPUT => error.InvalidInput,
        c.BSEC_E_DOSTEPS_VALUELIMITS => error.ValueLimits,
        c.BSEC_E_DOSTEPS_DUPLICATEINPUT => error.DuplicateInput,
        c.BSEC_I_DOSTEPS_NOOUTPUTSRETURNABLE => error.NoOutputsReturnable,
        c.BSEC_E_SU_WRONGDATARATE => error.WrongDataRate,
        c.BSEC_E_SU_SAMPLERATELIMITS => error.SampleRateLimits,
        c.BSEC_E_SU_DUPLICATEGATE => error.DuplicateGate,
        c.BSEC_E_SU_INVALIDSAMPLERATE => error.InvalidSampleRate,
        c.BSEC_E_SU_GATECOUNTEXCEEDSARRAY => error.GateCountExceedsArray,
        c.BSEC_E_SU_SAMPLINTVLINTEGERMULT => error.SamplingIntervalIntegerMult,
        c.BSEC_E_SU_MULTGASSAMPLINTVL => error.MultGasSamplingInterval,
        c.BSEC_E_SU_HIGHHEATERONDURATION => error.HighHeaterOnDuration,
        c.BSEC_E_PARSE_SECTIONEXCEEDSWORKBUFFER => error.ParseSectionExceedsWorkBuffer,
        c.BSEC_E_CONFIG_FAIL => error.ConfigFail,
        c.BSEC_E_CONFIG_VERSIONMISMATCH => error.ConfigVersionMismatch,
        c.BSEC_E_CONFIG_FEATUREMISMATCH => error.ConfigFeatureMismatch,
        c.BSEC_E_CONFIG_CRCMISMATCH => error.ConfigCrcMismatch,
        c.BSEC_E_CONFIG_EMPTY => error.ConfigEmpty,
        c.BSEC_E_CONFIG_INSUFFICIENTWORKBUFFER => error.ConfigInsufficientWorkBuffer,
        c.BSEC_E_CONFIG_INVALIDSTRINGSIZE => error.ConfigInvalidStringSize,
        c.BSEC_E_CONFIG_INSUFFICIENTBUFFER => error.ConfigInsufficientBuffer,
        c.BSEC_E_SET_INVALIDCHANNELIDENTIFIER => error.SetInvalidChannelIdentifier,
        c.BSEC_E_SET_INVALIDLENGTH => error.SetInvalidLength,
        // Warnings are treated as success
        c.BSEC_W_DOSTEPS_TSINTRADIFFOUTOFRANGE,
        c.BSEC_W_DOSTEPS_EXCESSOUTPUTS,
        c.BSEC_W_DOSTEPS_GASINDEXMISS,
        c.BSEC_W_SU_UNKNOWNOUTPUTGATE,
        c.BSEC_W_SU_MODINNOULP,
        c.BSEC_I_SU_SUBSCRIBEDOUTPUTGATES,
        c.BSEC_I_SU_GASESTIMATEPRECEDENCE,
        c.BSEC_W_SU_SAMPLERATEMISMATCH,
        c.BSEC_W_SC_CALL_TIMING_VIOLATION,
        c.BSEC_W_SC_MODEXCEEDULPTIMELIMIT,
        c.BSEC_W_SC_MODINSUFFICIENTWAITTIME,
        => {},
        else => error.Unknown,
    };
}

pub const Version = struct {
    major: u8,
    minor: u8,
    major_bugfix: u8,
    minor_bugfix: u8,
};

pub const SensorOutput = struct {
    timestamp_ns: i64,
    signal: f32,
    sensor_id: Output,
    accuracy: u8,
};

pub const BmeSettings = struct {
    next_call_ns: i64,
    process_data: u32,
    heater_temperature: u16,
    heater_duration: u16,
    heater_temperature_profile: [10]u16,
    heater_duration_profile: [10]u16,
    heater_profile_len: u8,
    run_gas: bool,
    pressure_oversampling: u8,
    temperature_oversampling: u8,
    humidity_oversampling: u8,
    trigger_measurement: bool,
    op_mode: u8,

    pub fn shouldProcess(self: BmeSettings, comptime sensor: enum { pressure, temperature, humidity, gas, profile_part }) bool {
        const mask = switch (sensor) {
            .pressure => c.BSEC_PROCESS_PRESSURE,
            .temperature => c.BSEC_PROCESS_TEMPERATURE,
            .humidity => c.BSEC_PROCESS_HUMIDITY,
            .gas => c.BSEC_PROCESS_GAS,
            .profile_part => c.BSEC_PROCESS_PROFILE_PART,
        };
        return (self.process_data & mask) != 0;
    }
};

/// BSEC library instance wrapper
pub const Bsec = struct {
    instance: []align(8) u8,
    allocator: std.mem.Allocator,

    const Self = @This();

    /// Create an initialize a new BSEC instance
    pub fn init(allocator: std.mem.Allocator) !Self {
        const instance_size = c.bsec_get_instance_size();

        const instance = allocator.alignedAlloc(u8, .@"8", instance_size) catch {
            return error.OutOfMemory;
        };
        errdefer allocator.free(instance);

        try mapBsecError(c.bsec_init(instance.ptr));

        return Self{
            .instance = instance,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.instance);
    }

    /// Get BSEC library version
    pub fn getVersion(self: *Self) !Version {
        var ver: c.bsec_version_t = undefined;
        try mapBsecError(c.bsec_get_version(self.instance.ptr, &ver));
        return Version{
            .major = ver.major,
            .minor = ver.minor,
            .major_bugfix = ver.major_bugfix,
            .minor_bugfix = ver.minor_bugfix,
        };
    }

    /// Set BSEC configuration from a binary blob
    pub fn setConfiguration(self: *Self, config: []const u8) !void {
        var work_buffer: [MAX_WORKBUFFER_SIZE]u8 = undefined;
        try mapBsecError(c.bsec_set_configuration(
            self.instance.ptr,
            config.ptr,
            @intCast(config.len),
            &work_buffer,
            work_buffer.len,
        ));
    }

    /// Subscribe to virtual sensor outputs at specified sample rates.
    /// BSEC will return the required physical sensor measurements needed.
    pub fn updateSubscription(self: *Self, requested: []const struct { output: Output, sample_rate: f32 }) !void {
        var requested_sensors: [NUMBER_OUTPUTS]c.bsec_sensor_configuration_t = undefined;
        for (requested, 0..) |req, i| {
            requested_sensors[i] = .{
                .sensor_id = @intFromEnum(req.output),
                .sample_rate = req.sample_rate,
            };
        }

        var required_settings: [MAX_PHYSICAL_SENSOR]c.bsec_sensor_configuration_t = undefined;
        var n_required: u8 = MAX_PHYSICAL_SENSOR;

        try mapBsecError(c.bsec_update_subscription(
            self.instance.ptr,
            &requested_sensors,
            @intCast(requested.len),
            &required_settings,
            &n_required,
        ));
    }

    /// Get sensor control settings for the next measurement
    pub fn sensorControl(self: *Self, timestamp_ns: i128) !BmeSettings {
        var settings: c.bsec_bme_settings_t = undefined;
        try mapBsecError(c.bsec_sensor_control(self.instance.ptr, @as(i64, @intCast(timestamp_ns)), &settings));

        return BmeSettings{
            .next_call_ns = settings.next_call,
            .process_data = settings.process_data,
            .heater_temperature = settings.heater_temperature,
            .heater_duration = settings.heater_duration,
            .heater_temperature_profile = settings.heater_temperature_profile,
            .heater_duration_profile = settings.heater_duration_profile,
            .heater_profile_len = settings.heater_profile_len,
            .run_gas = settings.run_gas != 0,
            .pressure_oversampling = settings.pressure_oversampling,
            .temperature_oversampling = settings.temperature_oversampling,
            .humidity_oversampling = settings.humidity_oversampling,
            .trigger_measurement = settings.trigger_measurement != 0,
            .op_mode = settings.op_mode,
        };
    }

    /// Process physical sensor inputs through BSEC algorithm to compute virtual sensor outputs.
    /// Returns array of SensorOutput with computed values like IAQ, CO2 equivalent, etc.
    pub fn doSteps(
        self: *Self,
        timestamp_ns: i128,
        temperature: ?f32,
        humidity: ?f32,
        pressure: ?f32,
        gas_resistance: ?f32,
        heat_source: ?f32,
    ) ![]SensorOutput {
        var inputs: [MAX_PHYSICAL_SENSOR]c.bsec_input_t = undefined;
        var n_inputs: u8 = 0;

        inline for (.{
            .{ temperature, Input.temperature },
            .{ humidity, Input.humidity },
            .{ pressure, Input.pressure },
            .{ gas_resistance, Input.gas_resistance },
            .{ heat_source, Input.heat_source },
        }) |pair| {
            if (pair[0]) |value| {
                inputs[n_inputs] = .{
                    .time_stamp = @as(i64, @intCast(timestamp_ns)),
                    .signal = value,
                    .signal_dimensions = 1,
                    .sensor_id = @intFromEnum(pair[1]),
                };
                n_inputs += 1;
            }
        }

        var outputs: [NUMBER_OUTPUTS]c.bsec_output_t = undefined;
        var n_outputs: u8 = NUMBER_OUTPUTS;

        try mapBsecError(c.bsec_do_steps(
            self.instance.ptr,
            &inputs,
            n_inputs,
            &outputs,
            &n_outputs,
        ));

        // Convert C struct outputs to Zig-friendly format with proper error types
        const Static = struct {
            var result: [NUMBER_OUTPUTS]SensorOutput = undefined;
        };

        for (outputs[0..n_outputs], 0..) |out, i| {
            Static.result[i] = .{
                .timestamp_ns = out.time_stamp,
                .signal = out.signal,
                .sensor_id = @enumFromInt(out.sensor_id),
                .accuracy = out.accuracy,
            };
        }

        return Static.result[0..n_outputs];
    }

    /// Save BSEC internal state (machine learning model calibration, baselines, etc.)
    /// Returns a slice of the provided buffer containing the state data
    pub fn getState(self: *Self, buffer: []u8) ![]u8 {
        var work_buffer: [MAX_WORKBUFFER_SIZE]u8 = undefined;
        var actual_size: u32 = 0;

        try mapBsecError(c.bsec_get_state(
            self.instance.ptr,
            0, // state_set_id: 0 = all states
            buffer.ptr,
            @intCast(buffer.len),
            &work_buffer,
            work_buffer.len,
            &actual_size,
        ));

        return buffer[0..actual_size];
    }

    /// Restore BSEC state
    pub fn setState(self: *Self, state: []const u8) !void {
        var work_buffer: [MAX_WORKBUFFER_SIZE]u8 = undefined;
        try mapBsecError(c.bsec_set_state(
            self.instance.ptr,
            state.ptr,
            @intCast(state.len),
            &work_buffer,
            work_buffer.len,
        ));
    }

    /// Reset a specific virtual sensor output (e.g., clear IAQ accumulation)
    pub fn resetOutput(self: *Self, output: Output) !void {
        try mapBsecError(c.bsec_reset_output(self.instance.ptr, @intFromEnum(output)));
    }
};
