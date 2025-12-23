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

pub const Progress = struct {
    bytes_received: usize,
    total_bytes: ?usize,

    pub fn percentage(self: Progress) ?f32 {
        if (self.total_bytes) |total| {
            if (total == 0) return 100.0;
            return @as(f32, @floatFromInt(self.bytes_received)) / @as(f32, @floatFromInt(total)) * 100.0;
        }
        return null;
    }
};

pub const ProgressCallback = *const fn (progress: Progress, user_data: ?*anyopaque) void;

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

/// Fetches a file with progress tracking. For larger downloads where you want to show progress.
/// # Parameters
/// - `allocator`: Allocator to use for response body.
/// - `file`: Path to the file relative to ROOT_URL.
/// - `content_type`: Expected content type (e.g. "application/json").
/// - `progress_callback`: Called periodically with download progress. Can be null.
/// - `user_data`: User data passed to the progress callback.
/// # Returns
/// - On success: Response body as a byte slice.
/// - On failure: An `APIError` indicating the type of error.
pub fn fetchFileWithProgress(
    allocator: Allocator,
    file: []const u8,
    content_type: []const u8,
    progress_callback: ?ProgressCallback,
    user_data: ?*anyopaque,
) APIError![]u8 {
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

    const content_length: ?usize = if (res.head.content_length) |len| len else null;

    var transfer_buffer: [16384]u8 = undefined;
    var decompress_buffer: [65536]u8 = undefined;
    var decompress: http.Decompress = undefined;

    if (progress_callback) |callback| {
        callback(.{
            .bytes_received = 0,
            .total_bytes = content_length,
        }, user_data);
    }

    const reader = res.readerDecompressing(&transfer_buffer, &decompress, &decompress_buffer);
    const body = reader.allocRemaining(allocator, std.io.Limit.limited(1024 * 1024 * 100)) catch return APIError.NetworkError;

    // Report final progress
    if (progress_callback) |callback| {
        callback(.{
            .bytes_received = body.len,
            .total_bytes = if (content_length) |_| body.len else null,
        }, user_data);
    }

    return body;
}

/// Downloads a file to disk with progress tracking.
/// # Parameters
/// - `allocator`: Allocator for temporary operations.
/// - `file`: Path to the file relative to ROOT_URL.
/// - `dest_path`: Local filesystem path to save the file.
/// - `progress_callback`: Called periodically with download progress. Can be null.
/// - `user_data`: User data passed to the progress callback.
/// # Returns
/// - On success: void
/// - On failure: An `APIError` indicating the type of error.
pub fn downloadFile(
    allocator: Allocator,
    file: []const u8,
    dest_path: []const u8,
    progress_callback: ?ProgressCallback,
    user_data: ?*anyopaque,
) APIError!void {
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
            .{ .name = "Accept", .value = "application/octet-stream" },
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

    const content_length: ?usize = if (res.head.content_length) |len| len else null;

    const dest_file = std.fs.cwd().createFile(dest_path, .{}) catch return APIError.NetworkError;
    defer dest_file.close();

    var transfer_buffer: [16384]u8 = undefined;
    var decompress_buffer: [65536]u8 = undefined;
    var decompress: http.Decompress = undefined;

    const reader = res.readerDecompressing(&transfer_buffer, &decompress, &decompress_buffer);

    var chunk_buffer: [8192]u8 = undefined;
    var total_received: usize = 0;

    while (true) {
        const bytes_read = reader.read(&chunk_buffer) catch return APIError.NetworkError;
        if (bytes_read == 0) break;

        dest_file.writeAll(chunk_buffer[0..bytes_read]) catch return APIError.NetworkError;
        total_received += bytes_read;

        if (progress_callback) |callback| {
            callback(.{
                .bytes_received = total_received,
                .total_bytes = content_length,
            }, user_data);
        }
    }
}

/// Downloads a file from an absolute URL to disk with progress tracking.
/// # Parameters
/// - `allocator`: Allocator for temporary operations.
/// - `url`: Full URL to download from.
/// - `dest_path`: Local filesystem path to save the file.
/// - `progress_callback`: Called periodically with download progress. Can be null.
/// - `user_data`: User data passed to the progress callback.
/// # Returns
/// - On success: void
/// - On failure: An `APIError` indicating the type of error.
pub fn downloadFromUrl(
    allocator: Allocator,
    url: []const u8,
    dest_path: []const u8,
    progress_callback: ?ProgressCallback,
    user_data: ?*anyopaque,
) APIError!void {
    var client = http.Client{ .allocator = allocator };
    defer client.deinit();

    const uri = std.Uri.parse(url) catch {
        return APIError.InvalidResponse;
    };

    var req = client.request(.GET, uri, .{
        .extra_headers = &.{
            .{ .name = "User-Agent", .value = "GlideLauncher" },
            .{ .name = "Accept", .value = "application/octet-stream" },
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

    const content_length: ?usize = if (res.head.content_length) |len| len else null;

    const dest_file = std.fs.cwd().createFile(dest_path, .{}) catch return APIError.NetworkError;
    defer dest_file.close();

    var transfer_buffer: [16384]u8 = undefined;
    var decompress_buffer: [65536]u8 = undefined;
    var decompress: http.Decompress = undefined;

    const reader = res.readerDecompressing(&transfer_buffer, &decompress, &decompress_buffer);

    const body = reader.allocRemaining(allocator, std.io.Limit.limited(1024 * 1024 * 500)) catch return APIError.NetworkError;
    defer allocator.free(body);

    dest_file.writeAll(body) catch return APIError.NetworkError;

    if (progress_callback) |callback| {
        callback(.{
            .bytes_received = body.len,
            .total_bytes = content_length,
        }, user_data);
    }
}

/// Downloads a file from an absolute URL into memory.
/// # Parameters
/// - `allocator`: Allocator for the response body.
/// - `url`: Full URL to download from.
/// # Returns
/// - On success: Response body as a byte slice (caller owns memory).
/// - On failure: An `APIError` indicating the type of error.
pub fn downloadFromUrlToMemory(
    allocator: Allocator,
    url: []const u8,
) APIError![]u8 {
    var client = http.Client{ .allocator = allocator };
    defer client.deinit();

    const uri = std.Uri.parse(url) catch {
        return APIError.InvalidResponse;
    };

    var req = client.request(.GET, uri, .{
        .extra_headers = &.{
            .{ .name = "User-Agent", .value = "GlideLauncher" },
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

    var transfer_buffer: [16384]u8 = undefined;
    var decompress_buffer: [65536]u8 = undefined;
    var decompress: http.Decompress = undefined;

    const reader = res.readerDecompressing(&transfer_buffer, &decompress, &decompress_buffer);
    const body = reader.allocRemaining(allocator, std.io.Limit.limited(1024 * 1024 * 500)) catch return APIError.NetworkError;

    return body;
}

