/// Field names must match the column names.
pub const User = struct {
    id: ?i32 = null,
    name: []const u8,
    email: []const u8,
};
