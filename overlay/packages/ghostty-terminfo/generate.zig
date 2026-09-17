const std = @import("std");
const ghostty = @import("src/terminfo/ghostty.zig").ghostty;

pub fn main() !void {
    var buffer: [1024]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&buffer);
    try ghostty.encode(&stdout_writer.interface);
    try stdout_writer.end();
}
