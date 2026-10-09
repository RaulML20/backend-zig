const std = @import("std");
const pg = @import("pg");
const Router = @import("../router/router.zig").Router;
const UserRepository = @import("../repositories/user_repository.zig").UserRepository;
const UserService = @import("../services/user_service.zig").UserService;
const UserController = @import("../controllers/user_controller.zig").UserController;

/// `arena` has to outlive the router.
pub fn register(arena: std.mem.Allocator, router: *Router, db: *pg.Pool) !void {
    const base_url = "/users";

    const user_repository = try arena.create(UserRepository);
    user_repository.* = .{ .db = db };
    const user_service = try arena.create(UserService);
    user_service.* = .{ .user_repository = user_repository };
    const user_controller = try arena.create(UserController);
    user_controller.* = .{ .user_service = user_service };

    try router.addRoute(.GET, base_url ++ "/readAll", .{}, .bind(user_controller, UserController.readAll));

    try router.addRoute(.POST, base_url ++ "/add", .{}, .bind(user_controller, UserController.add));

    try router.addRoute(.GET, base_url ++ "/read/:id", .{ .auth = true }, .bind(user_controller, UserController.read));
}
