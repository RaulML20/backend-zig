const std = @import("std");
const Allocator = std.mem.Allocator;
const Context = @import("../http/context.zig").Context;
const Auth = @import("../middleware/auth.zig").Auth;
const Error = @import("../utils/exception.zig").Error;
const trie = @import("trie_node.zig");
const TrieNode = trie.TrieNode;

pub const Handler = trie.Handler;

pub const RouteOptions = struct {
    auth: bool = false,
};

pub const Router = struct {
    pub const base_url = "/api/v1";

    arena: Allocator,
    auth: Auth,
    root: TrieNode = .{},

    pub fn init(arena: Allocator, auth: Auth) Router {
        return .{ .arena = arena, .auth = auth };
    }

    pub fn addRoute(
        self: *Router,
        method: std.http.Method,
        comptime path: []const u8,
        options: RouteOptions,
        handler: Handler,
    ) Allocator.Error!void {
        var parts = std.mem.tokenizeScalar(u8, base_url ++ path, '/');
        var node = &self.root;

        while (parts.next()) |part| {
            if (part[0] == ':') {
                if (node.dynamic_child == null) node.dynamic_child = try self.newNode();
                node = node.dynamic_child.?;
                node.param_name = part[1..];
            } else {
                const entry = try node.children.getOrPut(self.arena, part);
                if (!entry.found_existing) entry.value_ptr.* = try self.newNode();
                node = entry.value_ptr.*;
            }
        }

        node.handlers.put(method, handler);
        node.protected_routes.put(method, options.auth);
    }

    pub fn handle(self: *const Router, ctx: *Context) Error!void {
        const method = ctx.request.method;
        var parts = std.mem.tokenizeScalar(u8, ctx.request.path, '/');

        var node = &self.root;
        var params: std.StringHashMapUnmanaged([]const u8) = .empty;

        while (parts.next()) |part| {
            if (node.children.get(part)) |child| {
                node = child;
            } else if (node.dynamic_child) |dynamic| {
                node = dynamic;
                if (node.param_name) |param| try params.put(ctx.arena, param, part);
            } else {
                return error.RouteNotFound;
            }
        }

        const handler = node.handlers.get(method) orelse {
            return if (node.handlers.count() == 0) error.RouteNotFound else error.MethodNotAllowed;
        };
        if ((node.protected_routes.get(method) orelse false) and !self.auth.validate(ctx)) {
            return error.Unauthorized;
        }

        ctx.params = params;
        try handler.call(ctx);
    }

    fn newNode(self: *Router) Allocator.Error!*TrieNode {
        const node = try self.arena.create(TrieNode);
        node.* = .{};
        return node;
    }
};

const TestController = struct {
    last_id: ?[]const u8 = null,
    calls: usize = 0,

    fn list(self: *TestController, _: *Context) !void {
        self.calls += 1;
    }

    fn show(self: *TestController, ctx: *Context) !void {
        self.calls += 1;
        self.last_id = ctx.params.get("id");
    }
};

fn testRouter(arena: Allocator, controller: *TestController) !Router {
    var router: Router = .init(arena, .{ .secret = "secret" });
    try router.addRoute(.GET, "/users/readAll", .{}, .bind(controller, TestController.list));
    try router.addRoute(.GET, "/users/read/:id", .{}, .bind(controller, TestController.show));
    try router.addRoute(.GET, "/users/private/:id", .{ .auth = true }, .bind(controller, TestController.show));
    return router;
}

test "static and dynamic routes" {
    var arena_state: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var controller: TestController = .{};
    const router = try testRouter(arena, &controller);

    var all = Context.initTest(arena, .GET, "/api/v1/users/readAll", &.{});
    try router.handle(&all);
    try std.testing.expectEqual(1, controller.calls);

    var one = Context.initTest(arena, .GET, "/api/v1/users/read/42", &.{});
    try router.handle(&one);
    try std.testing.expectEqualStrings("42", controller.last_id.?);
}

test "404, 405 and 401" {
    var arena_state: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var controller: TestController = .{};
    const router = try testRouter(arena, &controller);

    var missing = Context.initTest(arena, .GET, "/api/v1/nope", &.{});
    try std.testing.expectError(error.RouteNotFound, router.handle(&missing));

    var intermediate = Context.initTest(arena, .GET, "/api/v1/users", &.{});
    try std.testing.expectError(error.RouteNotFound, router.handle(&intermediate));

    var wrong_method = Context.initTest(arena, .POST, "/api/v1/users/readAll", &.{});
    try std.testing.expectError(error.MethodNotAllowed, router.handle(&wrong_method));

    var unauthorized = Context.initTest(arena, .GET, "/api/v1/users/private/1", &.{});
    try std.testing.expectError(error.Unauthorized, router.handle(&unauthorized));

    try std.testing.expectEqual(0, controller.calls);
}
