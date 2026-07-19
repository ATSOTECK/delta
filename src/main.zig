const std = @import("std");

pub fn main(init: std.process.Init) !void {
    var buf: [4096]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &buf);
    const stdout = &stdout_writer.interface;

    try stdout.print("Hello, world!\n", .{});
    try stdout.flush();
}
