const std = @import("std");
const Context = @import("../http/context.zig").Context;
const Error = @import("../utils/exception.zig").Error;

/// Zig has no closures, so the controller goes along with its method.
pub const Handler = struct {
    ptr: *anyopaque,
    func: *const fn (ptr: *anyopaque, ctx: *Context) Error!void,

    pub fn bind(instance: anytype, comptime method: anytype) Handler {
        const T = @typeInfo(@TypeOf(instance)).pointer.child;
        const Wrapper = struct {
            fn call(ptr: *anyopaque, ctx: *Context) Error!void {
                const self: *T = @ptrCast(@alignCast(ptr));
                return method(self, ctx);
            }
        };
        return .{ .ptr = instance, .func = Wrapper.call };
    }

    pub fn call(h: Handler, ctx: *Context) Error!void {
        return h.func(h.ptr, ctx);
    }
};

pub const TrieNode = struct {
    children: std.StringHashMapUnmanaged(*TrieNode) = .empty,
    dynamic_child: ?*TrieNode = null,
    param_name: ?[]const u8 = null,
    handlers: std.EnumMap(std.http.Method, Handler) = .init(.{}),
    protected_routes: std.EnumMap(std.http.Method, bool) = .init(.{}),
};
