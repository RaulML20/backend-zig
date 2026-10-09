const std = @import("std");
const Allocator = std.mem.Allocator;
const Error = @import("../utils/exception.zig").Error;
const User = @import("../entities/user_entity.zig").User;
const CreateUserDTO = @import("../dtos/user_dto.zig").CreateUserDTO;
const UserRepository = @import("../repositories/user_repository.zig").UserRepository;

pub const UserService = struct {
    user_repository: *UserRepository,

    pub fn read(self: *UserService, arena: Allocator, id: i32) Error!?User {
        return self.user_repository.read(arena, id);
    }

    pub fn readAll(self: *UserService, arena: Allocator) Error![]User {
        return self.user_repository.readAll(arena);
    }

    pub fn add(self: *UserService, user_dto: CreateUserDTO) Error!User {
        const user: User = .{ .name = user_dto.name, .email = user_dto.email };
        return self.user_repository.add(user);
    }
};