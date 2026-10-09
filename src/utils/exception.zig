const std = @import("std");

pub const ErrorResponse = struct {
    status: std.http.Status,
    message: []const u8,
};

pub const Error = error{
    RouteNotFound,
    MethodNotAllowed,
    Unauthorized,
    BodyNotProvided,
    BodyTooLarge,
    BodyReadFailed,
    ExpectationFailed,
    InvalidJsonBody,
    IdNotProvided,
    IdNotNumber,
    UserNotFound,
    NameEmpty,
    EmailEmpty,
    InvalidEmailFormat,
    DuplicatedRecord,
    MissingRequiredField,
    DatabaseError,
} || std.mem.Allocator.Error || std.Io.Cancelable;

pub fn describe(err: Error) ErrorResponse {
    return switch (err) {
        error.RouteNotFound => .{ .status = .not_found, .message = "Route not found" },
        error.MethodNotAllowed => .{ .status = .method_not_allowed, .message = "Method not allowed" },
        error.Unauthorized => .{ .status = .unauthorized, .message = "Unauthorized" },
        error.BodyNotProvided => .{ .status = .bad_request, .message = "Body not provided" },
        error.BodyTooLarge => .{ .status = .payload_too_large, .message = "Body too large" },
        error.BodyReadFailed => .{ .status = .bad_request, .message = "Body could not be read" },
        error.ExpectationFailed => .{ .status = .expectation_failed, .message = "Expectation failed" },
        error.InvalidJsonBody => .{ .status = .bad_request, .message = "Invalid JSON body" },
        error.IdNotProvided => .{ .status = .bad_request, .message = "ID parameter not provided" },
        error.IdNotNumber => .{ .status = .bad_request, .message = "ID parameter not number" },
        error.UserNotFound => .{ .status = .not_found, .message = "User not found" },
        error.NameEmpty => .{ .status = .bad_request, .message = "Name cannot be empty" },
        error.EmailEmpty => .{ .status = .bad_request, .message = "Email cannot be empty" },
        error.InvalidEmailFormat => .{ .status = .bad_request, .message = "Invalid email format" },
        error.DuplicatedRecord => .{ .status = .conflict, .message = "Duplicated record" },
        error.MissingRequiredField => .{ .status = .bad_request, .message = "Missing required field" },
        error.DatabaseError => .{ .status = .internal_server_error, .message = "Database error" },
        error.OutOfMemory => .{ .status = .internal_server_error, .message = "Internal server error" },
        error.Canceled => .{ .status = .service_unavailable, .message = "Request canceled" },
    };
}

test describe {
    const e = describe(error.UserNotFound);
    try std.testing.expectEqual(std.http.Status.not_found, e.status);
    try std.testing.expectEqualStrings("User not found", e.message);
}