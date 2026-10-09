const std = @import("std");
const Allocator = std.mem.Allocator;
const HmacSha256 = std.crypto.auth.hmac.sha2.HmacSha256;
const base64 = std.base64.url_safe_no_pad;

pub const DecodeError = error{ InvalidToken, InvalidSignature, UnsupportedAlgorithm } || Allocator.Error;

const header_json = "{\"alg\":\"HS256\",\"typ\":\"JWT\"}";

pub fn decode(arena: Allocator, token: []const u8, secret: []const u8) DecodeError!std.json.Value {
    var parts = std.mem.splitScalar(u8, token, '.');
    const header_b64 = parts.next() orelse return error.InvalidToken;
    const payload_b64 = parts.next() orelse return error.InvalidToken;
    const signature_b64 = parts.next() orelse return error.InvalidToken;
    if (parts.next() != null) return error.InvalidToken;

    const header = try parseSegment(arena, header_b64);
    const alg = switch (header) {
        .object => |object| object.get("alg") orelse return error.InvalidToken,
        else => return error.InvalidToken,
    };
    if (alg != .string or !std.mem.eql(u8, alg.string, "HS256")) return error.UnsupportedAlgorithm;

    var expected: [HmacSha256.mac_length]u8 = undefined;
    HmacSha256.create(&expected, token[0 .. header_b64.len + 1 + payload_b64.len], secret);

    var signature: [HmacSha256.mac_length]u8 = undefined;
    const signature_len = base64.Decoder.calcSizeForSlice(signature_b64) catch return error.InvalidToken;
    if (signature_len != signature.len) return error.InvalidSignature;
    base64.Decoder.decode(&signature, signature_b64) catch return error.InvalidToken;
    if (!std.crypto.timing_safe.eql([HmacSha256.mac_length]u8, expected, signature)) return error.InvalidSignature;

    return parseSegment(arena, payload_b64);
}

pub fn encode(arena: Allocator, payload_json: []const u8, secret: []const u8) Allocator.Error![]const u8 {
    const header_len = base64.Encoder.calcSize(header_json.len);
    const payload_len = base64.Encoder.calcSize(payload_json.len);
    const signature_len = base64.Encoder.calcSize(HmacSha256.mac_length);

    const token = try arena.alloc(u8, header_len + 1 + payload_len + 1 + signature_len);
    _ = base64.Encoder.encode(token[0..header_len], header_json);
    token[header_len] = '.';
    _ = base64.Encoder.encode(token[header_len + 1 ..][0..payload_len], payload_json);

    const signing_input = token[0 .. header_len + 1 + payload_len];
    var mac: [HmacSha256.mac_length]u8 = undefined;
    HmacSha256.create(&mac, signing_input, secret);
    token[signing_input.len] = '.';
    _ = base64.Encoder.encode(token[signing_input.len + 1 ..], &mac);

    return token;
}

fn parseSegment(arena: Allocator, segment: []const u8) DecodeError!std.json.Value {
    const len = base64.Decoder.calcSizeForSlice(segment) catch return error.InvalidToken;
    const json = try arena.alloc(u8, len);
    base64.Decoder.decode(json, segment) catch return error.InvalidToken;
    return std.json.parseFromSliceLeaky(std.json.Value, arena, json, .{}) catch |err| switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        else => error.InvalidToken,
    };
}

test "encode and decode round trip" {
    var arena_state: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const token = try encode(arena, "{\"sub\":\"42\",\"exp\":1}", "secret");
    const payload = try decode(arena, token, "secret");
    try std.testing.expectEqualStrings("42", payload.object.get("sub").?.string);
    try std.testing.expectEqual(1, payload.object.get("exp").?.integer);
}

test "decode rejects a wrong secret or a tampered token" {
    var arena_state: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const token = try encode(arena, "{\"sub\":\"42\"}", "secret");
    try std.testing.expectError(error.InvalidSignature, decode(arena, token, "other"));

    const tampered = try arena.dupe(u8, token);
    tampered[tampered.len - 1] = if (tampered[tampered.len - 1] == 'A') 'B' else 'A';
    try std.testing.expectError(error.InvalidSignature, decode(arena, tampered, "secret"));

    try std.testing.expectError(error.InvalidToken, decode(arena, "not-a-token", "secret"));
}

test "decode rejects other algorithms" {
    var arena_state: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena_state.deinit();

    // {"alg":"none"}.{"sub":"42"}.
    try std.testing.expectError(
        error.UnsupportedAlgorithm,
        decode(arena_state.allocator(), "eyJhbGciOiJub25lIn0.eyJzdWIiOiI0MiJ9.", "secret"),
    );
}
