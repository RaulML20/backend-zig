const Context = @import("../http/context.zig").Context;

/// HSTS is set in the proxy (nginx / Cloudflare).
pub fn applySecurityHeaders(ctx: *Context) !void {
    try ctx.setHeader("X-Content-Type-Options", "nosniff");
    try ctx.setHeader("X-Frame-Options", "DENY");
    try ctx.setHeader("Content-Security-Policy", "default-src 'none'; frame-ancestors 'none'");
    try ctx.setHeader("Cache-Control", "no-store");
}