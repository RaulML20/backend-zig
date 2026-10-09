const std = @import("std");
const pg = @import("pg");
const database = @import("database.zig");
const Error = @import("../utils/exception.zig").Error;

/// `func` gets the connection as its first argument.
pub fn withTransaction(db: *pg.Pool, comptime func: anytype, args: anytype) Error!Payload(func) {
    const conn = db.acquire() catch |err| return database.fail(null, err);
    defer conn.release();

    conn.begin() catch |err| return database.fail(conn, err);
    const result = @call(.auto, func, .{conn} ++ args) catch |err| {
        const mapped = database.fail(conn, err);
        conn.rollback() catch {};
        return mapped;
    };
    conn.commit() catch |err| return database.fail(conn, err);
    return result;
}

fn Payload(comptime func: anytype) type {
    const Return = @typeInfo(@TypeOf(func)).@"fn".return_type.?;
    return @typeInfo(Return).error_union.payload;
}