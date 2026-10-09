const std = @import("std");
const Allocator = std.mem.Allocator;
const pg = @import("pg");
const database = @import("../config/database.zig");
const Error = @import("../utils/exception.zig").Error;
const User = @import("../entities/user_entity.zig").User;

pub const UserRepository = struct {
    db: *pg.Pool,

    pub fn read(self: *UserRepository, arena: Allocator, id: i32) Error!?User {
        const conn = self.db.acquire() catch |err| return database.fail(null, err);
        defer conn.release();

        var row = (conn.rowOpts("SELECT * FROM users WHERE id = $1", .{id}, .{
            .column_names = true,
            .allocator = arena,
        }) catch |err| return database.fail(conn, err)) orelse return null;
        defer row.deinit() catch {};

        return row.to(User, .{ .map = .name, .allocator = arena }) catch |err| database.fail(conn, err);
    }

    pub fn readAll(self: *UserRepository, arena: Allocator) Error![]User {
        const conn = self.db.acquire() catch |err| return database.fail(null, err);
        defer conn.release();

        var result = conn.queryOpts("SELECT * FROM users", .{}, .{
            .column_names = true,
            .allocator = arena,
        }) catch |err| return database.fail(conn, err);
        defer result.deinit();

        var users: std.ArrayList(User) = .empty;
        var mapper = result.mapper(User, .{ .allocator = arena });
        while (mapper.next() catch |err| return database.fail(conn, err)) |user| try users.append(arena, user);
        return users.items;
    }

    pub fn add(self: *UserRepository, user: User) Error!User {
        const conn = self.db.acquire() catch |err| return database.fail(null, err);
        defer conn.release();

        var row = (conn.row(
            "INSERT INTO users (name, email) VALUES ($1, $2) RETURNING id",
            .{ user.name, user.email },
        ) catch |err| return database.fail(conn, err)) orelse return error.DatabaseError;
        defer row.deinit() catch {};

        const id = row.get(i32, 0) catch |err| return database.fail(conn, err);
        return .{ .id = id, .name = user.name, .email = user.email };
    }
};