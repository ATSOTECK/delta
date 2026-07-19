const std = @import("std");
const sdl = @import("zsdl3");

pub const SdlError = error{Sdl};

pub fn sdl_error(msg: []const u8) SdlError {
    std.log.err("{s}: {?s}", .{ msg, sdl.getError() });
    return error.Sdl;
}
