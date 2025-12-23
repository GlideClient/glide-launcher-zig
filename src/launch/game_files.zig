const std = @import("std");
const api = @import("../web/api.zig");
const files = @import("../file/files.zig");
const platform = @import("../platform.zig");
const json_types = @import("../json/types.zig");

pub const ProgressCallback = *const fn (status: []const u8, progress: f32, user_data: ?*anyopaque) void;

pub const GameFilesError = error{
    FetchFailed,
    ParseFailed,
    DownloadFailed,
    ExtractFailed,
    InvalidData,
};

pub const AssetIndex = struct {
    id: []const u8,
    sha1: []const u8,
    size: u64,
    totalSize: u64,
    url: []const u8,
};

pub const DownloadInfo = struct {
    sha1: []const u8,
    size: u64,
    url: []const u8,
};

pub const GameDownloads = struct {
    client: DownloadInfo,
    server: ?DownloadInfo = null,
};

pub const LibraryArtifact = struct {
    path: []const u8,
    sha1: []const u8,
    size: u64,
    url: []const u8,
};

pub const LibraryDownloads = struct {
    artifact: ?LibraryArtifact = null,
};

pub const OsRule = struct {
    name: ?[]const u8 = null,
    arch: ?[]const u8 = null,
};

pub const Rule = struct {
    action: []const u8,
    os: ?OsRule = null,
};

pub const Library = struct {
    name: []const u8,
    downloads: ?LibraryDownloads = null,
    rules: ?[]Rule = null,
    natives: ?std.json.ObjectMap = null,
};

pub const LoggingFile = struct {
    id: []const u8,
    sha1: []const u8,
    size: u64,
    url: []const u8,
};

pub const LoggingConfig = struct {
    argument: []const u8,
    file: LoggingFile,
    @"type": []const u8,
};

pub const ClientLogging = struct {
    client: ?LoggingConfig = null,
};

pub const JavaVersionInfo = struct {
    component: []const u8,
    majorVersion: u32,
};

pub const VersionManifest = struct {
    id: []const u8,
    assetIndex: AssetIndex,
    assets: []const u8,
    downloads: GameDownloads,
    libraries: []const std.json.Value,
    logging: ?std.json.Value = null,
    mainClass: []const u8,
    minecraftArguments: ?[]const u8 = null,
    javaVersion: ?JavaVersionInfo = null,
};

/// Check if a library should be included based on rules
fn isLibraryAllowed(rules: ?[]const std.json.Value) bool {
    if (rules == null) return true;

    const builtin = @import("builtin");
    const current_os = switch (builtin.os.tag) {
        .linux => "linux",
        .windows => "windows",
        .macos => "osx",
        else => "linux",
    };

    var dominated = false;
    var dominated_by = true;

    for (rules.?) |rule| {
        const action = rule.object.get("action").?.string;
        const is_allow = std.mem.eql(u8, action, "allow");

        if (rule.object.get("os")) |os_obj| {
            if (os_obj.object.get("name")) |name_val| {
                const os_name = name_val.string;
                if (std.mem.eql(u8, os_name, current_os)) {
                    dominated = true;
                    dominated_by = is_allow;
                }
            }
        } else {
            // No OS specified, applies to all
            dominated_by = is_allow;
        }
    }

    return dominated_by;
}

pub fn downloadAssetIndex(
    allocator: std.mem.Allocator,
    asset_index: AssetIndex,
    progress_cb: ?ProgressCallback,
    user_data: ?*anyopaque,
) GameFilesError!void {
    const asset_path = std.fmt.allocPrint(allocator, "assets/indexes/{s}.json", .{asset_index.id}) catch return GameFilesError.DownloadFailed;
    defer allocator.free(asset_path);

    if (files.fileExists(allocator, asset_path)) {
        if (progress_cb) |cb| cb("Asset index already exists", 1.0, user_data);
        return;
    }

    if (progress_cb) |cb| cb("Downloading asset index...", 0.0, user_data);

    files.makeDirRecursive(allocator, "assets/indexes") catch return GameFilesError.DownloadFailed;

    const abs_path = files.getAbsolutePath(allocator, asset_path) catch return GameFilesError.DownloadFailed;
    defer allocator.free(abs_path);

    api.downloadFromUrl(allocator, asset_index.url, abs_path, null, null) catch return GameFilesError.DownloadFailed;

    if (progress_cb) |cb| cb("Asset index downloaded", 1.0, user_data);
}

pub fn downloadClient(
    allocator: std.mem.Allocator,
    version_id: []const u8,
    download: DownloadInfo,
    progress_cb: ?ProgressCallback,
    user_data: ?*anyopaque,
) GameFilesError!void {
    const client_path = std.fmt.allocPrint(allocator, "versions/{s}/{s}.jar", .{ version_id, version_id }) catch return GameFilesError.DownloadFailed;
    defer allocator.free(client_path);

    if (files.fileExists(allocator, client_path)) {
        if (progress_cb) |cb| cb("Client JAR already exists", 1.0, user_data);
        return;
    }

    if (progress_cb) |cb| cb("Downloading client...", 0.0, user_data);

    const version_dir = std.fmt.allocPrint(allocator, "versions/{s}", .{version_id}) catch return GameFilesError.DownloadFailed;
    defer allocator.free(version_dir);
    files.makeDirRecursive(allocator, version_dir) catch return GameFilesError.DownloadFailed;

    const abs_path = files.getAbsolutePath(allocator, client_path) catch return GameFilesError.DownloadFailed;
    defer allocator.free(abs_path);

    api.downloadFromUrl(allocator, download.url, abs_path, null, null) catch return GameFilesError.DownloadFailed;

    if (progress_cb) |cb| cb("Client downloaded", 1.0, user_data);
}

/// Downloads a single library with retry support
pub fn downloadLibrary(
    allocator: std.mem.Allocator,
    artifact: LibraryArtifact,
    progress_cb: ?ProgressCallback,
    user_data: ?*anyopaque,
) GameFilesError!void {
    const lib_path = std.fmt.allocPrint(allocator, "libraries/{s}", .{artifact.path}) catch return GameFilesError.DownloadFailed;
    defer allocator.free(lib_path);

    if (files.fileExists(allocator, lib_path)) {
        return;
    }

    if (progress_cb) |cb| cb("Downloading library...", 0.0, user_data);

    if (std.fs.path.dirname(lib_path)) |dir| {
        files.makeDirRecursive(allocator, dir) catch return GameFilesError.DownloadFailed;
    }

    const abs_path = files.getAbsolutePath(allocator, lib_path) catch return GameFilesError.DownloadFailed;
    defer allocator.free(abs_path);

    // Try up to 3 times
    var attempts: u32 = 0;
    while (attempts < 3) : (attempts += 1) {
        api.downloadFromUrl(allocator, artifact.url, abs_path, null, null) catch {
            std.debug.print("  Attempt {}/3 failed for: {s}\n", .{ attempts + 1, artifact.path });
            std.Thread.sleep(500 * std.time.ns_per_ms);
            continue;
        };
        return; // Success
    }

    std.debug.print("Failed to download after 3 attempts: {s}\n", .{artifact.path});
    return GameFilesError.DownloadFailed;
}

pub fn downloadLibraries(
    allocator: std.mem.Allocator,
    libraries_json: []const std.json.Value,
    progress_cb: ?ProgressCallback,
    user_data: ?*anyopaque,
) GameFilesError!void {
    if (progress_cb) |cb| cb("Downloading libraries...", 0.0, user_data);

    var downloaded: usize = 0;
    var failed: usize = 0;
    var skipped: usize = 0;
    const total = libraries_json.len;

    for (libraries_json) |lib_value| {
        const lib_obj = lib_value.object;

        // Check rules to see if this library applies to current OS
        if (lib_obj.get("rules")) |rules_val| {
            if (!isLibraryAllowed(rules_val.array.items)) {
                skipped += 1;
                downloaded += 1;
                continue;
            }
        }

        // Download the main artifact
        if (lib_obj.get("downloads")) |downloads_val| {
            if (downloads_val.object.get("artifact")) |artifact_val| {
                const artifact = LibraryArtifact{
                    .path = artifact_val.object.get("path").?.string,
                    .sha1 = artifact_val.object.get("sha1").?.string,
                    .size = @intCast(artifact_val.object.get("size").?.integer),
                    .url = artifact_val.object.get("url").?.string,
                };

                downloadLibrary(allocator, artifact, null, null) catch {
                    std.debug.print("Failed to download library: {s}\n", .{artifact.path});
                    failed += 1;
                };
            }

            // Also download native classifiers if present
            if (downloads_val.object.get("classifiers")) |classifiers_val| {
                const builtin = @import("builtin");
                const native_key = switch (builtin.os.tag) {
                    .linux => "natives-linux",
                    .windows => "natives-windows",
                    .macos => "natives-osx",
                    else => "natives-linux",
                };

                if (classifiers_val.object.get(native_key)) |native_artifact_val| {
                    const native_artifact = LibraryArtifact{
                        .path = native_artifact_val.object.get("path").?.string,
                        .sha1 = native_artifact_val.object.get("sha1").?.string,
                        .size = @intCast(native_artifact_val.object.get("size").?.integer),
                        .url = native_artifact_val.object.get("url").?.string,
                    };

                    downloadLibrary(allocator, native_artifact, null, null) catch {
                        std.debug.print("Failed to download native: {s}\n", .{native_artifact.path});
                        failed += 1;
                    };
                }
            }
        }

        downloaded += 1;
        if (progress_cb) |cb| {
            const progress = @as(f32, @floatFromInt(downloaded)) / @as(f32, @floatFromInt(total));
            cb("Downloading libraries...", progress, user_data);
        }
    }

    std.debug.print("Libraries: {} total, {} skipped (wrong OS), {} failed\n", .{ total, skipped, failed });
    if (progress_cb) |cb| cb("Libraries downloaded", 1.0, user_data);
}

pub fn downloadLoggingConfig(
    allocator: std.mem.Allocator,
    logging_json: std.json.Value,
    progress_cb: ?ProgressCallback,
    user_data: ?*anyopaque,
) GameFilesError!void {
    const client_logging = logging_json.object.get("client") orelse return;
    const file_info = client_logging.object.get("file") orelse return;

    const file_id = file_info.object.get("id").?.string;
    const file_url = file_info.object.get("url").?.string;

    const log_path = std.fmt.allocPrint(allocator, "assets/log_configs/{s}", .{file_id}) catch return GameFilesError.DownloadFailed;
    defer allocator.free(log_path);

    if (files.fileExists(allocator, log_path)) {
        if (progress_cb) |cb| cb("Logging config already exists", 1.0, user_data);
        return;
    }

    if (progress_cb) |cb| cb("Downloading logging config...", 0.0, user_data);

    files.makeDirRecursive(allocator, "assets/log_configs") catch return GameFilesError.DownloadFailed;

    const abs_path = files.getAbsolutePath(allocator, log_path) catch return GameFilesError.DownloadFailed;
    defer allocator.free(abs_path);

    api.downloadFromUrl(allocator, file_url, abs_path, null, null) catch return GameFilesError.DownloadFailed;

    if (progress_cb) |cb| cb("Logging config downloaded", 1.0, user_data);
}

pub fn fetchVersionManifest(
    allocator: std.mem.Allocator,
    manifest_url: []const u8,
) GameFilesError!std.json.Parsed(std.json.Value) {
    const data = api.downloadFromUrlToMemory(allocator, manifest_url) catch return GameFilesError.FetchFailed;
    defer allocator.free(data);

    const parsed = std.json.parseFromSlice(std.json.Value, allocator, data, .{}) catch return GameFilesError.ParseFailed;

    return parsed;
}

pub fn downloadAllGameFiles(
    allocator: std.mem.Allocator,
    version_manifest_url: []const u8,
    progress_cb: ?ProgressCallback,
    user_data: ?*anyopaque,
) GameFilesError!void {
    if (progress_cb) |cb| cb("Fetching version manifest...", 0.0, user_data);

    const manifest = fetchVersionManifest(allocator, version_manifest_url) catch return GameFilesError.FetchFailed;
    defer manifest.deinit();

    const root = manifest.value.object;

    const version_id = root.get("id").?.string;

    if (root.get("assetIndex")) |asset_index_val| {
        const ai = asset_index_val.object;
        const asset_index = AssetIndex{
            .id = ai.get("id").?.string,
            .sha1 = ai.get("sha1").?.string,
            .size = @intCast(ai.get("size").?.integer),
            .totalSize = @intCast(ai.get("totalSize").?.integer),
            .url = ai.get("url").?.string,
        };
        downloadAssetIndex(allocator, asset_index, progress_cb, user_data) catch |err| {
            std.debug.print("Failed to download asset index: {}\n", .{err});
        };
    }

    if (root.get("downloads")) |downloads_val| {
        if (downloads_val.object.get("client")) |client_val| {
            const client_download = DownloadInfo{
                .sha1 = client_val.object.get("sha1").?.string,
                .size = @intCast(client_val.object.get("size").?.integer),
                .url = client_val.object.get("url").?.string,
            };
            downloadClient(allocator, version_id, client_download, progress_cb, user_data) catch |err| {
                std.debug.print("Failed to download client: {}\n", .{err});
            };
        }
    }

    if (root.get("libraries")) |libraries_val| {
        downloadLibraries(allocator, libraries_val.array.items, progress_cb, user_data) catch |err| {
            std.debug.print("Failed to download libraries: {}\n", .{err});
        };
    }

    if (root.get("logging")) |logging_val| {
        downloadLoggingConfig(allocator, logging_val, progress_cb, user_data) catch |err| {
            std.debug.print("Failed to download logging config: {}\n", .{err});
        };
    }

    if (progress_cb) |cb| cb("All game files ready!", 1.0, user_data);
}

pub fn buildClasspath(
    allocator: std.mem.Allocator,
    libraries_json: []const std.json.Value,
    version_id: []const u8,
) ![]const u8 {
    var classpath = std.ArrayList(u8).init(allocator);
    defer classpath.deinit();

    const sep = if (@import("builtin").os.tag == .windows) ";" else ":";

    for (libraries_json) |lib_value| {
        const lib_obj = lib_value.object;

        if (lib_obj.get("downloads")) |downloads_val| {
            if (downloads_val.object.get("artifact")) |artifact_val| {
                const path = artifact_val.object.get("path").?.string;
                const lib_path = try std.fmt.allocPrint(allocator, "libraries/{s}", .{path});
                defer allocator.free(lib_path);

                const abs_path = try files.getAbsolutePath(allocator, lib_path);
                defer allocator.free(abs_path);

                if (classpath.items.len > 0) {
                    try classpath.appendSlice(sep);
                }
                try classpath.appendSlice(abs_path);
            }
        }
    }

    const client_path = try std.fmt.allocPrint(allocator, "versions/{s}/{s}.jar", .{ version_id, version_id });
    defer allocator.free(client_path);

    const abs_client = try files.getAbsolutePath(allocator, client_path);
    defer allocator.free(abs_client);

    if (classpath.items.len > 0) {
        try classpath.appendSlice(sep);
    }
    try classpath.appendSlice(abs_client);

    return try classpath.toOwnedSlice();
}

