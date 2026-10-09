const std = @import("std");
const jwt = @import("../utils/jwt.zig");
const Context = @import("../http/context.zig").Context;

const leeway = 10;

pub const Auth = struct {
    secret: []const u8,

    pub fn validate(self: Auth, ctx: *Context) bool {
        return self.check(ctx) catch |err| switch (err) {
            error.InvalidToken, error.InvalidSignature, error.UnsupportedAlgorithm => false,
            else => {
                std.log.err("Unexpected error: {s}", .{@errorName(err)});
                return false;
            },
        };
    }

    fn check(self: Auth, ctx: *Context) !bool {
        const token = ctx.request.cookie("token") orelse return false;

        const payload = try jwt.decode(ctx.arena, token, self.secret);
        if (payload != .object) return false;

        const exp = toUnix(payload.object.get("exp") orelse return false) orelse return false;
        if (std.Io.Clock.real.now(ctx.io).toSeconds() > exp + leeway) return false;

        const sub = try subject(ctx.arena, payload.object.get("sub") orelse return false) orelse return false;
        if (sub.len == 0) return false;

        ctx.user_id = sub;
        return true;
    }
};

fn toUnix(value: std.json.Value) ?i64 {
    return switch (value) {
        .integer => |i| i,
        .float => |f| if (std.math.isFinite(f) and @abs(f) < 1e18) @intFromFloat(f) else null,
        .string, .number_string => |s| std.fmt.parseInt(i64, s, 10) catch null,
        else => null,
    };
}

fn subject(arena: std.mem.Allocator, value: std.json.Value) !?[]const u8 {
    return switch (value) {
        .string, .number_string => |s| s,
        .integer => |i| try std.fmt.allocPrint(arena, "{d}", .{i}),
        else => null,
    };
}

fn testContext(arena: std.mem.Allocator, payload_json: []const u8, secret: []const u8) !Context {
    const token = try jwt.encode(arena, payload_json, secret);
    const cookie = try std.fmt.allocPrint(arena, "token={s}", .{token});
    const headers = try arena.dupe(std.http.Header, &.{.{ .name = "Cookie", .value = cookie }});
    return Context.initTest(arena, .GET, "/", headers);
}

test "valid token sets the user id" {
    var arena_state: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const auth: Auth = .{ .secret = "secret" };
    var ctx = try testContext(arena, "{\"sub\":7,\"exp\":4102444800}", "secret");
    try std.testing.expect(auth.validate(&ctx));
    try std.testing.expectEqualStrings("7", ctx.user_id.?);
}

test "expired, unsigned or subject-less tokens are rejected" {
    var arena_state: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const auth: Auth = .{ .secret = "secret" };

    var expired = try testContext(arena, "{\"sub\":\"7\",\"exp\":1}", "secret");
    try std.testing.expect(!auth.validate(&expired));

    var no_exp = try testContext(arena, "{\"sub\":\"7\"}", "secret");
    try std.testing.expect(!auth.validate(&no_exp));

    var no_sub = try testContext(arena, "{\"exp\":4102444800}", "secret");
    try std.testing.expect(!auth.validate(&no_sub));

    var wrong_secret = try testContext(arena, "{\"sub\":\"7\",\"exp\":4102444800}", "other");
    try std.testing.expect(!auth.validate(&wrong_secret));

    var no_cookie = Context.initTest(arena, .GET, "/", &.{});
    try std.testing.expect(!auth.validate(&no_cookie));
}
