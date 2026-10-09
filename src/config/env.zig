const std = @import("std");
const Environ = std.process.Environ;

/// The `.env` next to the binary, where `zig build` copies it.
pub fn defaultPath(io: std.Io, arena: std.mem.Allocator) ![]const u8 {
    const dir = try std.process.executableDirPathAlloc(io, arena);
    return std.fs.path.join(arena, &.{ dir, ".env" });
}

pub fn load(io: std.Io, gpa: std.mem.Allocator, environ: *Environ.Map, path: []const u8) !void {
    const content = std.Io.Dir.cwd().readFileAlloc(io, path, gpa, .limited(64 * 1024)) catch |err| switch (err) {
        error.FileNotFound => {
            std.log.warn("{s} not found, using the process environment only", .{path});
            return;
        },
        else => return err,
    };
    defer gpa.free(content);
    try parse(content, environ);
}

pub fn parse(content: []const u8, environ: *Environ.Map) !void {
    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \t\r");
        if (line.len == 0 or line[0] == '#') continue;

        const eq = std.mem.findScalar(u8, line, '=') orelse continue;
        const key = std.mem.trim(u8, line[0..eq], " \t");
        if (key.len == 0 or environ.contains(key)) continue;

        try environ.put(key, unquote(std.mem.trim(u8, line[eq + 1 ..], " \t")));
    }
}

pub fn require(environ: *const Environ.Map, key: []const u8) error{MissingEnvVar}![]const u8 {
    return environ.get(key) orelse {
        std.log.err("{s} not defined in .env file", .{key});
        return error.MissingEnvVar;
    };
}

fn unquote(value: []const u8) []const u8 {
    if (value.len >= 2 and (value[0] == '"' or value[0] == '\'') and value[value.len - 1] == value[0]) {
        return value[1 .. value.len - 1];
    }
    return value;
}

test parse {
    var environ: Environ.Map = .init(std.testing.allocator);
    defer environ.deinit();
    try environ.put("PORT", "9000");

    try parse(
        \\# comment
        \\PORT=8080
        \\
        \\DB_HOST = localhost
        \\DB_PASSWORD="a=b c"
        \\
    , &environ);

    try std.testing.expectEqualStrings("9000", environ.get("PORT").?);
    try std.testing.expectEqualStrings("localhost", environ.get("DB_HOST").?);
    try std.testing.expectEqualStrings("a=b c", environ.get("DB_PASSWORD").?);
}