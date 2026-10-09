const std = @import("std");
const Context = @import("../http/context.zig").Context;
const Error = @import("../utils/exception.zig").Error;
const dtos = @import("../dtos/user_dto.zig");
const UserDTO = dtos.UserDTO;
const CreateUserDTO = dtos.CreateUserDTO;
const UserService = @import("../services/user_service.zig").UserService;

pub const UserController = struct {
    user_service: *UserService,

    pub fn read(self: *UserController, ctx: *Context) Error!void {
        const id = ctx.params.get("id") orelse return error.IdNotProvided;

        const id_number = std.fmt.parseInt(i32, id, 10) catch return error.IdNotNumber;

        const user = (try self.user_service.read(ctx.arena, id_number)) orelse return error.UserNotFound;

        try ctx.json(.{ .ok = 1, .data = UserDTO.init(user) });
    }

    pub fn readAll(self: *UserController, ctx: *Context) Error!void {
        const users = try self.user_service.readAll(ctx.arena);

        const dto_list = try UserDTO.toDTOs(ctx.arena, users);
        try ctx.json(.{ .ok = 1, .data = dto_list });
    }

    pub fn add(self: *UserController, ctx: *Context) Error!void {
        const body = try ctx.readBody();
        if (std.mem.trim(u8, body, &std.ascii.whitespace).len == 0) return error.BodyNotProvided;

        const dto = try CreateUserDTO.fromJson(ctx.arena, body);

        try dto.validate();

        const user = try self.user_service.add(dto);

        ctx.response.status = .created;
        try ctx.json(.{ .ok = 1, .data = UserDTO.init(user) });
    }
};