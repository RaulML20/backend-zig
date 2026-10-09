const std = @import("std");
const Allocator = std.mem.Allocator;
const Error = @import("../utils/exception.zig").Error;
const User = @import("../entities/user_entity.zig").User;

pub const UserDTO = struct {
    id: ?i32,
    name: []const u8,
    email: []const u8,

    pub fn init(user: User) UserDTO {
        return .{ .id = user.id, .name = user.name, .email = user.email };
    }

    pub fn toDTOs(arena: Allocator, users: []const User) Allocator.Error![]UserDTO {
        const dtos = try arena.alloc(UserDTO, users.len);
        for (users, dtos) |user, *dto| dto.* = .init(user);
        return dtos;
    }
};

pub const CreateUserDTO = struct {
    name: []const u8,
    email: []const u8,

    pub fn fromJson(arena: Allocator, body: []const u8) Error!CreateUserDTO {
        return std.json.parseFromSliceLeaky(CreateUserDTO, arena, body, .{
            .ignore_unknown_fields = true,
        }) catch |err| switch (err) {
            error.OutOfMemory => error.OutOfMemory,
            else => error.InvalidJsonBody,
        };
    }

    pub fn validate(self: CreateUserDTO) Error!void {
        if (isBlank(self.name)) return error.NameEmpty;
        if (isBlank(self.email)) return error.EmailEmpty;
        if (!isValidEmail(self.email)) return error.InvalidEmailFormat;
    }

    fn isBlank(value: []const u8) bool {
        return std.mem.trim(u8, value, &std.ascii.whitespace).len == 0;
    }

    /// Same rule as the regex `^[^@\s]+@[^@\s]+\.[^@\s]+$`.
    fn isValidEmail(email: []const u8) bool {
        for (email) |c| {
            if (std.ascii.isWhitespace(c)) return false;
        }
        const at = std.mem.findScalar(u8, email, '@') orelse return false;
        const domain = email[at + 1 ..];
        if (at == 0 or std.mem.findScalar(u8, domain, '@') != null) return false;

        for (domain, 0..) |c, i| {
            if (c == '.' and i > 0 and i < domain.len - 1) return true;
        }
        return false;
    }
};

test "isValidEmail" {
    const valid = [_][]const u8{ "raul@example.com", "a@b.c", "a@b.c.", "a@.b.c" };
    for (valid) |email| try std.testing.expect(CreateUserDTO.isValidEmail(email));

    const invalid = [_][]const u8{ "", "raul", "@b.c", "a@b", "a@b.", "a@.b", "a@@b.c", "a b@c.d", "a@b@c.d" };
    for (invalid) |email| try std.testing.expect(!CreateUserDTO.isValidEmail(email));
}

test "fromJson and validate" {
    var arena_state: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const dto = try CreateUserDTO.fromJson(arena, "{\"name\":\"Raúl\",\"email\":\"raul@example.com\",\"extra\":1}");
    try dto.validate();
    try std.testing.expectEqualStrings("Raúl", dto.name);

    try std.testing.expectError(error.InvalidJsonBody, CreateUserDTO.fromJson(arena, "{\"name\":\"x\"}"));
    try std.testing.expectError(error.InvalidJsonBody, CreateUserDTO.fromJson(arena, "not json"));

    const blank: CreateUserDTO = .{ .name = "  ", .email = "a@b.c" };
    try std.testing.expectError(error.NameEmpty, blank.validate());
    const bad_email: CreateUserDTO = .{ .name = "x", .email = "nope" };
    try std.testing.expectError(error.InvalidEmailFormat, bad_email.validate());
}
