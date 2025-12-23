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

pub fn writeFile(allocator: std.mem.Allocator, relative_path: []const u8, data: []const u8) !void {
    const full_path = try std.fs.path.join(allocator, &.{root_dir, relative_path});
    defer allocator.free(full_path);

    if (std.fs.path.dirname(full_path)) |dir| {
        std.fs.makeDirAbsolute(dir) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return err,
        };
    }

    const file = try std.fs.createFileAbsolute(full_path, .{ .truncate = true });
    defer file.close();

    try file.writeAll(data);
}

pub fn readFile(allocator: std.mem.Allocator, relative_path: []const u8, buffer: []u8) ![]const u8 {
    const full_path = try std.fs.path.join(allocator, &.{root_dir, relative_path});
    defer allocator.free(full_path);

    const file = try std.fs.openFileAbsolute(full_path, .{});
    defer file.close();

    const file_size = try file.getEndPos();
    if (file_size > @as(u64, buffer.len)) {
        return error.BufferTooSmall;
    }

    const bytes_read = try file.readAll(buffer[0..@intCast(file_size)]);
    return buffer[0..bytes_read];
}

pub fn writeVersionManifest(allocator: std.mem.Allocator, manifest_json: []const u8) !void {
    try writeFile(allocator, "versions/version_manifest.json", manifest_json);
}

pub fn readLocalVersionManifest(allocator: std.mem.Allocator, buffer: []u8) ![]const u8 {
    return readFile(allocator, "versions/version_manifest.json", buffer);
}

pub fn getAbsolutePath(allocator: std.mem.Allocator, relative_path: []const u8) ![]const u8 {
    return std.fs.path.join(allocator, &.{ root_dir, relative_path });
}

pub fn makeDirRecursive(allocator: std.mem.Allocator, relative_path: []const u8) !void {
    const full_path = try std.fs.path.join(allocator, &.{ root_dir, relative_path });
    defer allocator.free(full_path);

    var path_so_far = std.array_list.Managed(u8).init(allocator);
    defer path_so_far.deinit();

    var it = std.mem.splitScalar(u8, full_path, std.fs.path.sep);
    while (it.next()) |component| {
        if (component.len == 0) {
            try path_so_far.append(std.fs.path.sep);
            continue;
        }

        if (path_so_far.items.len > 0 and path_so_far.items[path_so_far.items.len - 1] != std.fs.path.sep) {
            try path_so_far.append(std.fs.path.sep);
        }
        try path_so_far.appendSlice(component);

        std.fs.makeDirAbsolute(path_so_far.items) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return err,
        };
    }
}

pub fn fileExists(allocator: std.mem.Allocator, relative_path: []const u8) bool {
    const full_path = std.fs.path.join(allocator, &.{ root_dir, relative_path }) catch return false;
    defer allocator.free(full_path);

    std.fs.accessAbsolute(full_path, .{}) catch return false;
    return true;
}

pub fn dirExists(allocator: std.mem.Allocator, relative_path: []const u8) bool {
    const full_path = std.fs.path.join(allocator, &.{ root_dir, relative_path }) catch return false;
    defer allocator.free(full_path);

    var dir = std.fs.openDirAbsolute(full_path, .{}) catch return false;
    dir.close();
    return true;
}
