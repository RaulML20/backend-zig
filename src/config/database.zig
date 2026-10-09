const std = @import("std");
const pg = @import("pg");
const env = @import("env.zig");
const Error = @import("../utils/exception.zig").Error;

pub fn init(io: std.Io, gpa: std.mem.Allocator, environ: *const std.process.Environ.Map) !*pg.Pool {
    const port = std.fmt.parseInt(u16, try env.require(environ, "DB_PORT"), 10) catch {
        std.log.err("DB_PORT is not a valid port", .{});
        return error.InvalidDbPort;
    };

    const pool_size = std.fmt.parseInt(u16, environ.get("DB_POOL_SIZE") orelse "5", 10) catch {
        std.log.err("DB_POOL_SIZE is not a valid number", .{});
        return error.InvalidDbPoolSize;
    };

    return pg.Pool.init(io, gpa, .{
        .size = pool_size,
        .connect = .{
            .host = try env.require(environ, "DB_HOST"),
            .port = port,
        },
        .auth = .{
            .username = try env.require(environ, "DB_USER"),
            .password = try env.require(environ, "DB_PASSWORD"),
            .database = try env.require(environ, "DB_NAME"),
            .timeout = 10_000,
        },
    });
}

/// On `error.PG` the PostgreSQL details are in `conn.err`.
pub fn fail(conn: ?*pg.Conn, err: anyerror) Error {
    switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.Canceled => return error.Canceled,
        error.PG => if (conn) |c| if (c.err) |pge| {
            std.log.err("PostgreSQL error {s}: {s}", .{ pge.code, pge.message });
            if (std.mem.eql(u8, pge.code, "23505")) return error.DuplicatedRecord;
            if (std.mem.eql(u8, pge.code, "23502")) return error.MissingRequiredField;
            return error.DatabaseError;
        },
        else => {},
    }
    std.log.err("database error: {s}", .{@errorName(err)});
    return error.DatabaseError;
}