const std = @import("std");
const Allocator = std.mem.Allocator;

const env = @import("config/env.zig");
const database = @import("config/database.zig");
const security = @import("config/security.zig");
const Cors = @import("config/cors.zig").Cors;
const exception = @import("utils/exception.zig");
const Context = @import("http/context.zig").Context;
const Router = @import("router/router.zig").Router;
const user_route = @import("routes/user_route.zig");

const max_connections = 256;

const App = struct {
    io: std.Io,
    gpa: Allocator,
    router: *const Router,
    cors: Cors,
    connection_slots: *std.Io.Semaphore,
};

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const arena = init.arena.allocator();
    const environ = init.environ_map;

    const env_path = environ.get("ENV_FILE") orelse try env.defaultPath(io, arena);
    try env.load(io, init.gpa, environ, env_path);

    const db = try database.init(io, init.gpa, environ);
    defer db.deinit();

    const secret = try arena.dupe(u8, try env.require(environ, "SECRET_KEY"));
    var router: Router = .init(arena, .{ .secret = secret });
    try user_route.register(arena, &router, db);

    var connection_slots: std.Io.Semaphore = .{ .permits = max_connections };
    const app: App = .{
        .io = io,
        .gpa = init.gpa,
        .router = &router,
        .cors = try .fromEnv(arena, environ),
        .connection_slots = &connection_slots,
    };

    const host = environ.get("HOST") orelse "127.0.0.1";
    const port = std.fmt.parseInt(u16, environ.get("PORT") orelse "8080", 10) catch {
        std.log.err("PORT is not a valid port", .{});
        return error.InvalidPort;
    };
    const address = try std.Io.net.IpAddress.parse(host, port);
    var server = try address.listen(io, .{ .reuse_address = true });
    defer server.deinit(io);
    std.log.info("Listening on http://{f}", .{address});

    var connections: std.Io.Group = .init;
    defer connections.cancel(io);

    while (true) {
        try connection_slots.wait(io);
        const stream = server.accept(io) catch |err| {
            connection_slots.post(io);
            switch (err) {
                error.Canceled => return err,
                else => {
                    std.log.err("accept failed: {s}", .{@errorName(err)});
                    continue;
                },
            }
        };
        connections.concurrent(io, handleConnection, .{ &app, stream }) catch {
            std.log.err("no capacity for a new connection", .{});
            connection_slots.post(io);
            stream.close(io);
        };
    }
}

fn handleConnection(app: *const App, stream: std.Io.net.Stream) void {
    defer app.connection_slots.post(app.io);
    defer stream.close(app.io);

    var recv_buffer: [8192]u8 = undefined;
    var send_buffer: [8192]u8 = undefined;
    var connection_reader = stream.reader(app.io, &recv_buffer);
    var connection_writer = stream.writer(app.io, &send_buffer);
    var server: std.http.Server = .init(&connection_reader.interface, &connection_writer.interface);

    var arena_state: std.heap.ArenaAllocator = .init(app.gpa);
    defer arena_state.deinit();

    while (true) {
        _ = arena_state.reset(.retain_capacity);

        var request = server.receiveHead() catch return;
        handleRequest(app, arena_state.allocator(), &request) catch return;
        // If part of the body was left unread the connection can't be reused.
        if (server.reader.state != .ready) return;
    }
}

fn handleRequest(app: *const App, arena: Allocator, request: *std.http.Server.Request) !void {
    var ctx = try Context.init(arena, app.io, request);
    dispatch(app, &ctx) catch |err| switch (err) {
        error.Canceled => return err,
        else => {
            try writeError(&ctx, err);
            if (ctx.response.status.class() == .server_error) {
                std.log.err("{s} {s}: {s}", .{ @tagName(ctx.request.method), ctx.request.path, @errorName(err) });
            }
        },
    };

    // Without Content-Length or chunked we don't know where the body ends.
    const head = request.head;
    const framed = !head.method.requestHasBody() or head.content_length != null or head.transfer_encoding != .none;

    try request.respond(ctx.response.body.items, .{
        .status = ctx.response.status,
        .extra_headers = ctx.response.headers.items,
        .keep_alive = framed,
    });
}

fn dispatch(app: *const App, ctx: *Context) exception.Error!void {
    try security.applySecurityHeaders(ctx);

    if (try app.cors.handle(ctx)) return;

    try app.router.handle(ctx);
}

fn writeError(ctx: *Context, err: exception.Error) Allocator.Error!void {
    const e = exception.describe(err);
    ctx.response.status = e.status;
    ctx.response.body.clearRetainingCapacity();
    try ctx.json(.{ .ok = 0, .@"error" = e.message });
}

test {
    _ = @import("config/env.zig");
    _ = @import("config/cors.zig");
    _ = @import("config/security.zig");
    _ = @import("config/transactions.zig");
    _ = @import("utils/exception.zig");
    _ = @import("utils/jwt.zig");
    _ = @import("http/context.zig");
    _ = @import("middleware/auth.zig");
    _ = @import("router/router.zig");
    _ = @import("dtos/user_dto.zig");
    _ = @import("routes/user_route.zig");
}

test "errors become the JSON envelope" {
    var arena_state: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena_state.deinit();

    var ctx = Context.initTest(arena_state.allocator(), .GET, "/", &.{});
    try ctx.print("partial");
    try writeError(&ctx, error.UserNotFound);
    try std.testing.expectEqual(std.http.Status.not_found, ctx.response.status);
    try std.testing.expectEqualStrings("{\"ok\":0,\"error\":\"User not found\"}", ctx.response.body.items);

    try writeError(&ctx, error.OutOfMemory);
    try std.testing.expectEqual(std.http.Status.internal_server_error, ctx.response.status);
    try std.testing.expectEqualStrings("{\"ok\":0,\"error\":\"Internal server error\"}", ctx.response.body.items);
}