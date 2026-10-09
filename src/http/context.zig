const std = @import("std");
const Allocator = std.mem.Allocator;
const Error = @import("../utils/exception.zig").Error;

const max_body_size = 1024 * 1024;

pub const Context = struct {
    arena: Allocator,
    io: std.Io,
    request: Request,
    params: std.StringHashMapUnmanaged([]const u8) = .empty,
    user_id: ?[]const u8 = null,
    response: Response = .{},

    pub const Request = struct {
        method: std.http.Method,
        /// Without the query string.
        path: []const u8,
        /// Copied, because reading the body overwrites the buffer they point to.
        origin: ?[]const u8 = null,
        cookies: ?[]const u8 = null,
        raw: ?*std.http.Server.Request = null,
        body: ?[]const u8 = null,

        pub fn cookie(r: *const Request, name: []const u8) ?[]const u8 {
            var pairs = std.mem.splitScalar(u8, r.cookies orelse return null, ';');
            while (pairs.next()) |pair| {
                const trimmed = std.mem.trim(u8, pair, " ");
                const eq = std.mem.findScalar(u8, trimmed, '=') orelse continue;
                if (std.mem.eql(u8, trimmed[0..eq], name)) return trimmed[eq + 1 ..];
            }
            return null;
        }

        fn headerField(r: *Request, name: []const u8) ?*?[]const u8 {
            if (std.ascii.eqlIgnoreCase(name, "origin")) return &r.origin;
            if (std.ascii.eqlIgnoreCase(name, "cookie")) return &r.cookies;
            return null;
        }
    };

    pub const Response = struct {
        status: std.http.Status = .ok,
        headers: std.ArrayList(std.http.Header) = .empty,
        body: std.ArrayList(u8) = .empty,
    };

    pub fn init(arena: Allocator, io: std.Io, raw: *std.http.Server.Request) Allocator.Error!Context {
        const target = raw.head.target;
        const path = target[0 .. std.mem.findScalar(u8, target, '?') orelse target.len];

        var request: Request = .{
            .method = raw.head.method,
            .path = try arena.dupe(u8, path),
            .raw = raw,
        };
        var it = raw.iterateHeaders();
        while (it.next()) |h| {
            if (request.headerField(h.name)) |field| field.* = try arena.dupe(u8, h.value);
        }

        return .{ .arena = arena, .io = io, .request = request };
    }

    pub fn readBody(ctx: *Context) Error![]const u8 {
        if (ctx.request.body) |body| return body;
        const raw = ctx.request.raw orelse return "";

        // Without Content-Length or chunked the body only ends when the client closes.
        const head = raw.head;
        if (!head.method.requestHasBody() or (head.content_length == null and head.transfer_encoding == .none)) {
            ctx.request.body = "";
            return "";
        }

        var buffer: [4096]u8 = undefined;
        const reader = raw.readerExpectContinue(&buffer) catch |err| switch (err) {
            error.HttpExpectationFailed => return error.ExpectationFailed,
            error.WriteFailed => return error.BodyReadFailed,
        };
        const body = reader.allocRemaining(ctx.arena, .limited(max_body_size)) catch |err| switch (err) {
            error.StreamTooLong => return error.BodyTooLarge,
            error.ReadFailed => return error.BodyReadFailed,
            error.OutOfMemory => return error.OutOfMemory,
        };
        ctx.request.body = body;
        return body;
    }

    pub fn setHeader(ctx: *Context, name: []const u8, value: []const u8) Allocator.Error!void {
        for (ctx.response.headers.items) |*h| {
            if (std.ascii.eqlIgnoreCase(h.name, name)) {
                h.value = value;
                return;
            }
        }
        try ctx.response.headers.append(ctx.arena, .{ .name = name, .value = value });
    }

    pub fn setContentType(ctx: *Context, value: []const u8) Allocator.Error!void {
        try ctx.setHeader("Content-Type", value);
    }

    pub fn print(ctx: *Context, text: []const u8) Allocator.Error!void {
        try ctx.response.body.appendSlice(ctx.arena, text);
    }

    pub fn json(ctx: *Context, value: anytype) Allocator.Error!void {
        try ctx.setContentType("application/json");
        var out: std.Io.Writer.Allocating = .fromArrayList(ctx.arena, &ctx.response.body);
        defer ctx.response.body = out.toArrayList();
        std.json.Stringify.value(value, .{ .emit_null_optional_fields = false }, &out.writer) catch return error.OutOfMemory;
    }

    pub fn initTest(arena: Allocator, method: std.http.Method, path: []const u8, headers: []const std.http.Header) Context {
        var request: Request = .{ .method = method, .path = path };
        for (headers) |h| {
            if (request.headerField(h.name)) |field| field.* = h.value;
        }
        return .{ .arena = arena, .io = std.testing.io, .request = request };
    }
};

test "cookie lookup" {
    const ctx = Context.initTest(std.testing.allocator, .GET, "/", &.{
        .{ .name = "Cookie", .value = "theme=dark; token=abc.def.ghi" },
    });
    try std.testing.expectEqualStrings("abc.def.ghi", ctx.request.cookie("token").?);
    try std.testing.expectEqualStrings("dark", ctx.request.cookie("theme").?);
    try std.testing.expectEqual(null, ctx.request.cookie("missing"));
}

test "setHeader replaces existing values" {
    var arena_state: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena_state.deinit();

    var ctx = Context.initTest(arena_state.allocator(), .GET, "/", &.{});
    try ctx.setHeader("Vary", "Origin");
    try ctx.setHeader("vary", "Accept");
    try std.testing.expectEqual(1, ctx.response.headers.items.len);
    try std.testing.expectEqualStrings("Accept", ctx.response.headers.items[0].value);
}
