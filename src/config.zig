const std = @import("std");

const config_csv = @embedFile("bsec_iaq.csv");

pub const bsec_config = parseConfig();

fn parseConfig() [554]u8 {
    @setEvalBranchQuota(10000);
    var result: [554]u8 = undefined;
    var index: usize = 0;
    var num: u16 = 0;
    var in_number = false;

    // Skip the first number (length prefix) and its comma
    var skip_first = true;

    for (config_csv) |char| {
        if (char >= '0' and char <= '9') {
            num = num * 10 + (char - '0');
            in_number = true;
        } else if (in_number) {
            if (skip_first) {
                skip_first = false;
            } else {
                result[index] = @intCast(num);
                index += 1;
            }
            num = 0;
            in_number = false;
        }
    }
    // Handle last number if no trailing comma/newline
    if (in_number and !skip_first) {
        result[index] = @intCast(num);
    }

    return result;
}
