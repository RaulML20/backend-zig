const std = @import("std");
const Context = @import("../http/context.zig").Context;

const allowed_methods = "GET, POST, PUT, PATCH, DELETE, OPTIONS";
const allowed_headers = "Content-Type, Authorization, X-CSRF-Token";

pub const Cors = struct {
    allowed_origins: []const []const u8,

    pub fn fromEnv(arena: std.mem.Allocator, environ: *const std.process.Environ.Map) std.mem.Allocator.Error!Cors {
        var origins: std.ArrayList([]const u8) = .empty;
        var it = std.mem.tokenizeScalar(u8, environ.get("CORS_ORIGINS") orelse "", ',');
        while (it.next()) |raw| {
            const origin = std.mem.trim(u8, raw, " \t");
            if (origin.len > 0) try origins.append(arena, try arena.dupe(u8, origin));
        }
        return .{ .allowed_origins = origins.items };
    }

    /// Returns true on a preflight, which is already answered.
    pub fn handle(self: Cors, ctx: *Context) std.mem.Allocator.Error!bool {
        if (ctx.request.origin) |origin| {
            if (self.isAllowed(origin)) {
                try ctx.setHeader("Access-Control-Allow-Origin", origin);
                try ctx.setHeader("Vary", "Origin");
                try ctx.setHeader("Access-Control-Allow-Methods", allowed_methods);
                try ctx.setHeader("Access-Control-Allow-Headers", allowed_headers);
                try ctx.setHeader("Access-Control-Allow-Credentials", "true");
                try ctx.setHeader("Access-Control-Max-Age", "86400");
            }
        }

        if (ctx.request.method == .OPTIONS) {
            ctx.response.status = .no_content;
            return true;
        }

        return false;
    }

    fn isAllowed(self: Cors, origin: []const u8) bool {
        for (self.allowed_origins) |allowed| {
            if (std.mem.eql(u8, origin, allowed)) return true;
        }
        return false;
    }
};

test "origins from the environment" {
    var arena_state: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena_state.deinit();

    var environ: std.process.Environ.Map = .init(std.testing.allocator);
    defer environ.deinit();
    try environ.put("CORS_ORIGINS", "http://localhost:5173, https://app.example.com,");

    const cors: Cors = try .fromEnv(arena_state.allocator(), &environ);
    try std.testing.expectEqual(2, cors.allowed_origins.len);
    try std.testing.expectEqualStrings("https://app.example.com", cors.allowed_origins[1]);
}

test "preflight from an allowed origin" {
    var arena_state: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena_state.deinit();

    const cors: Cors = .{ .allowed_origins = &.{"http://localhost:5173"} };
    var ctx = Context.initTest(arena_state.allocator(), .OPTIONS, "/api/v1/users/add", &.{
        .{ .name = "Origin", .value = "http://localhost:5173" },
    });
    try std.testing.expect(try cors.handle(&ctx));
    try std.testing.expectEqual(std.http.Status.no_content, ctx.response.status);
    try std.testing.expectEqual(6, ctx.response.headers.items.len);
}

test "unknown origins get no CORS headers" {
    var arena_state: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena_state.deinit();

    const cors: Cors = .{ .allowed_origins = &.{"http://localhost:5173"} };
    var ctx = Context.initTest(arena_state.allocator(), .GET, "/", &.{
        .{ .name = "Origin", .value = "http://evil.example" },
    });
    try std.testing.expect(!try cors.handle(&ctx));
    try std.testing.expectEqual(0, ctx.response.headers.items.len);
}