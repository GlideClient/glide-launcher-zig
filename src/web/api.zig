const std = @import("std");
const http = std.http;
const Allocator = std.mem.Allocator;

const ROOT_URL = "https://api.glideclient.com";

pub const APIError = error{
    NetworkError,
    InvalidResponse,
    Unauthorized,
    NotFound,
    ServerError,
};

/// Fetches a file relative to ROOT_URL using given encoding. Mainly for small files (JSON metadata etc).
/// # Parameters
/// - `allocator`: Allocator to use for response body.
/// - `file`: Path to the file relative to ROOT_URL.
/// - `content_type`: Expected content type (e.g. "application/json").
/// # Returns
/// - On success: Response body as a byte slice.
/// - On failure: An `APIError` indicating the type of error.
pub fn fetchFile(allocator: Allocator, file: []const u8, content_type: []const u8) APIError![]u8 {
    var client = http.Client{ .allocator = allocator };
    defer client.deinit();

    const url = std.fmt.allocPrint(allocator, "{s}/{s}", .{ ROOT_URL, file }) catch {
        return APIError.InvalidResponse;
    };
    defer allocator.free(url);

    const uri = std.Uri.parse(url) catch {
        return APIError.InvalidResponse;
    };

    var req = client.request(.GET, uri, .{
        .extra_headers = &.{
            .{ .name = "User-Agent", .value = "GlideLauncher" },
            .{ .name = "Accept", .value = content_type },
        },
    }) catch {
        return APIError.NetworkError;
    };

    defer req.deinit();

    req.sendBodiless() catch return APIError.NetworkError;

    var redirect_buffer: [4096]u8 = undefined;
    var res = req.receiveHead(&redirect_buffer) catch {
        return APIError.InvalidResponse;
    };

    if (res.head.status.class() != .success) {
        return APIError.InvalidResponse;
    }

    // Read the response body with automatic decompression if needed
    var transfer_buffer: [16384]u8 = undefined;
    // flate.gzip requires at least flate.max_window_len (64 KiB) for its buffer
    var decompress_buffer: [65536]u8 = undefined;
    var decompress: http.Decompress = undefined;

    const reader = res.readerDecompressing(&transfer_buffer, &decompress, &decompress_buffer);
    const body = reader.allocRemaining(allocator, std.io.Limit.limited(1024 * 1024)) catch return APIError.NetworkError;
    return body;
}
