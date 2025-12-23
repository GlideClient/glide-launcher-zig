const std = @import("std");
const builtin = @import("builtin");

var root_dir: []const u8 = undefined;

fn getDataDir(allocator: std.mem.Allocator) !?[]const u8 {
    const os = builtin.os.tag;

    if (os == .windows) {
        return std.process.getEnvVarOwned(allocator, "APPDATA") catch null;
    }

    if (std.process.getEnvVarOwned(allocator, "XDG_DATA_HOME")) |xdg| {
        return xdg;
    } else |_| {}

    if (std.process.getEnvVarOwned(allocator, "HOME")) |home| {
        return try std.fs.path.join(allocator, &.{ home, ".local", "share" });
    } else |_| {}

    return null;
}


pub fn initFileSystem(allocator: std.mem.Allocator) !void {
    var root_path_data = try getDataDir(allocator);
    if (root_path_data) |dir| {
        root_path_data = try std.fs.path.join(allocator, &.{dir, "glide"});
    } else {
        root_path_data = try std.fs.path.join(allocator, &.{".glide"});
    }

    root_dir = root_path_data.?;

    std.fs.makeDirAbsolute(root_dir) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };
}

pub fn writeVersionManifest(allocator: std.mem.Allocator, manifest_json: []const u8) !void {
    const version_dir = try std.fs.path.join(allocator, &.{root_dir, "versions"});
    defer allocator.free(version_dir);

    std.fs.makeDirAbsolute(version_dir) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };

    const manifest_path = try std.fs.path.join(allocator, &.{version_dir, "version_manifest.json"});
    defer allocator.free(manifest_path);

    const file = try std.fs.createFileAbsolute(manifest_path, .{ .truncate = true });
    defer file.close();

    try file.writeAll(manifest_json);
}

pub fn readLocalVersionManifest(allocator: std.mem.Allocator, buffer: []u8) ![]const u8 {
    const manifest_path = try std.fs.path.join(allocator, &.{root_dir, "versions", "version_manifest.json"});
    defer allocator.free(manifest_path);

    const file = try std.fs.openFileAbsolute(manifest_path, .{});
    defer file.close();

    const file_size = try file.getEndPos();
    if (file_size > @as(u64, buffer.len)) {
        return error.BufferTooSmall;
    }

    var read_buffer: [4096]u8 = undefined;
    var reader = file.reader(&read_buffer);
    const bytes = reader.interface.take(@as(usize, @intCast(file_size))) catch return error.ReadError;
    @memcpy(buffer[0..bytes.len], bytes);

    return buffer[0..bytes.len];
}