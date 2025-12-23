const std = @import("std");

pub fn hashFileSha256(path: []const u8) !struct {
    size: u64,
    hash: [std.crypto.hash.sha2.Sha256.digest_length]u8,
} {
    const file = try std.fs.openFileAbsolute(path, .{});
    defer file.close();

    const size = try file.getEndPos();

    var hasher = std.crypto.hash.sha2.Sha256.init(.{});

    var buf: [64 * 1024]u8 = undefined;
    var reader = file.reader(&buf);

    while (true) {
        const bytes = reader.interface.take(buf.len) catch |err| switch (err) {
            error.EndOfStream => break,
            else => return error.ReadError,
        };
        if (bytes.len == 0) break;
        hasher.update(bytes);
    }

    var digest: [std.crypto.hash.sha2.Sha256.digest_length]u8 = undefined;
    hasher.final(&digest);

    return .{
        .size = size,
        .hash = digest,
    };
}
