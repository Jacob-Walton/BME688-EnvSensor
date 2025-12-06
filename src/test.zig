const std = @import("std");
const testing = std.testing;

const logger = @import("logger.zig");
const config = @import("config.zig");
const server = @import("server.zig");
const bsec = @import("bsec.zig");

test {
    testing.refAllDecls(@import("logger.zig"));
    testing.refAllDecls(@import("config.zig"));
}
