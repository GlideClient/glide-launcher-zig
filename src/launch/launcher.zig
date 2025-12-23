const std = @import("std");
const api = @import("../web/api.zig");
const files = @import("../file/files.zig");
const platform = @import("../platform.zig");
const json_types = @import("../json/types.zig");
const game_files = @import("game_files.zig");
const launching = @import("launching.zig");

pub const DownloadState = struct {
    allocator: std.mem.Allocator,
    is_downloading: bool = false,
    progress: f32 = 0.0,
    status: []const u8 = "",

    pub fn init(allocator: std.mem.Allocator) DownloadState {
        return .{ .allocator = allocator };
    }
};

pub const ProgressCallback = *const fn (status: []const u8, progress: f32, user_data: ?*anyopaque) void;

/// Downloads and extracts Java for the given component
pub fn downloadJava(
    allocator: std.mem.Allocator,
    java_component: []const u8,
    progress_cb: ?ProgressCallback,
    user_data: ?*anyopaque,
) bool {
    const java_dir = std.fmt.allocPrint(allocator, "java/{s}", .{java_component}) catch return false;
    defer allocator.free(java_dir);

    if (files.dirExists(allocator, java_dir)) {
        std.debug.print("Java {s} already exists\n", .{java_component});
        return true;
    }

    if (progress_cb) |cb| cb("Fetching Java info...", 0.0, user_data);

    const java_manifest_data = api.fetchFileWithProgress(
        allocator,
        "api/v1/shared/java/all.json",
        "application/json",
        null,
        null,
    ) catch {
        if (progress_cb) |cb| cb("Error: Failed to fetch Java manifest", 0.0, user_data);
        return false;
    };
    defer allocator.free(java_manifest_data);

    const platform_str = platform.getPlatformString();
    std.debug.print("Platform: {s}\n", .{platform_str});

    const parsed = std.json.parseFromSlice(std.json.Value, allocator, java_manifest_data, .{}) catch {
        if (progress_cb) |cb| cb("Error: Failed to parse Java manifest", 0.0, user_data);
        return false;
    };
    defer parsed.deinit();

    const platform_obj = parsed.value.object.get(platform_str) orelse {
        std.debug.print("Platform {s} not found in Java manifest\n", .{platform_str});
        if (progress_cb) |cb| cb("Error: Platform not supported", 0.0, user_data);
        return false;
    };

    const java_info = platform_obj.object.get(java_component) orelse {
        std.debug.print("Java component {s} not found for platform {s}\n", .{ java_component, platform_str });
        if (progress_cb) |cb| cb("Error: Java version not found", 0.0, user_data);
        return false;
    };

    const url = java_info.object.get("url").?.string;

    std.debug.print("Downloading Java from: {s}\n", .{url});
    if (progress_cb) |cb| cb("Downloading Java...", 0.1, user_data);

    files.makeDirRecursive(allocator, java_dir) catch {
        if (progress_cb) |cb| cb("Error: Failed to create Java directory", 0.0, user_data);
        return false;
    };

    const zip_path = std.fmt.allocPrint(allocator, "java/{s}.zip", .{java_component}) catch return false;
    defer allocator.free(zip_path);

    const abs_zip_path = files.getAbsolutePath(allocator, zip_path) catch return false;
    defer allocator.free(abs_zip_path);

    api.downloadFromUrl(allocator, url, abs_zip_path, null, null) catch {
        if (progress_cb) |cb| cb("Error: Failed to download Java", 0.0, user_data);
        return false;
    };

    if (progress_cb) |cb| cb("Extracting Java...", 0.8, user_data);
    std.debug.print("Java downloaded to: {s}\n", .{abs_zip_path});

    const abs_java_dir = files.getAbsolutePath(allocator, java_dir) catch return false;
    defer allocator.free(abs_java_dir);

    var dest_dir = std.fs.openDirAbsolute(abs_java_dir, .{}) catch {
        if (progress_cb) |cb| cb("Error: Failed to open Java directory", 0.0, user_data);
        return false;
    };
    defer dest_dir.close();

    var zip_file = std.fs.openFileAbsolute(abs_zip_path, .{}) catch {
        if (progress_cb) |cb| cb("Error: Failed to open zip file", 0.0, user_data);
        return false;
    };
    defer zip_file.close();

    var read_buffer: [4096]u8 = undefined;
    var file_reader = zip_file.reader(&read_buffer);
    std.zip.extract(dest_dir, &file_reader, .{}) catch {
        if (progress_cb) |cb| cb("Error: Failed to extract Java", 0.0, user_data);
        return false;
    };

    std.fs.deleteFileAbsolute(abs_zip_path) catch {
        std.debug.print("Warning: Failed to delete zip file\n", .{});
    };

    // Make Java binaries executable (zip extraction doesn't preserve permissions)
    const builtin = @import("builtin");
    if (builtin.os.tag != .windows) {
        makeExecutable(allocator, java_dir) catch |err| {
            std.debug.print("Warning: Failed to set executable permissions: {}\n", .{err});
        };
    }

    if (progress_cb) |cb| cb("Java ready!", 1.0, user_data);
    std.debug.print("Java extracted to: {s}\n", .{abs_java_dir});

    return true;
}

fn makeExecutable(allocator: std.mem.Allocator, java_dir: []const u8) !void {
    const bin_dir = try std.fmt.allocPrint(allocator, "{s}/bin", .{java_dir});
    defer allocator.free(bin_dir);

    const abs_bin_dir = try files.getAbsolutePath(allocator, bin_dir);
    defer allocator.free(abs_bin_dir);

    var dir = try std.fs.openDirAbsolute(abs_bin_dir, .{ .iterate = true });
    defer dir.close();

    var iterator = dir.iterate();
    while (try iterator.next()) |entry| {
        if (entry.kind == .file) {
            const file_path = try std.fs.path.join(allocator, &.{ abs_bin_dir, entry.name });
            defer allocator.free(file_path);

            // Use chmod via std.c to make executable (755 = rwxr-xr-x)
            const file_path_z = try allocator.dupeZ(u8, file_path);
            defer allocator.free(file_path_z);

            const result = std.c.chmod(file_path_z, 0o755);
            if (result != 0) {
                std.debug.print("Warning: Failed to chmod {s}\n", .{entry.name});
                continue;
            }

            std.debug.print("Made executable: {s}\n", .{entry.name});
        }
    }
}

/// Fetches client info from API
pub fn fetchClientInfo(
    allocator: std.mem.Allocator,
    version: []const u8,
    progress_cb: ?ProgressCallback,
    user_data: ?*anyopaque,
) ?json_types.Client {
    if (progress_cb) |cb| cb("Fetching client info...", 0.0, user_data);

    const path = std.fmt.allocPrint(allocator, "api/v1/client/{s}.json", .{version}) catch return null;
    defer allocator.free(path);

    const local_path = std.fmt.allocPrint(allocator, "versions/{s}.json", .{version}) catch return null;
    defer allocator.free(local_path);

    var buffer: [8192]u8 = undefined;

    const data: []const u8 = api.fetchFileWithProgress(
        allocator,
        path,
        "application/json",
        null,
        null,
    ) catch blk: {
        if (progress_cb) |cb| cb("Trying local file...", 0.0, user_data);
        const local_data = files.readFile(allocator, local_path, &buffer) catch {
            if (progress_cb) |cb| cb("Error: Failed to get client info", 0.0, user_data);
            return null;
        };
        break :blk local_data;
    };

    // Save locally for offline use
    files.writeFile(allocator, local_path, data) catch {};

    const parsed = std.json.parseFromSlice(json_types.Client, allocator, data, .{
        .ignore_unknown_fields = true,
    }) catch |err| {
        std.debug.print("Failed to parse Client json: {}\n", .{err});
        if (progress_cb) |cb| cb("Error: Failed to parse client info", 0.0, user_data);
        return null;
    };

    if (progress_cb) |cb| cb("Client info loaded", 1.0, user_data);
    return parsed.value;
}

/// Downloads the custom libraries from the client config
pub fn downloadCustomLibraries(
    allocator: std.mem.Allocator,
    client: json_types.Client,
    progress_cb: ?ProgressCallback,
    user_data: ?*anyopaque,
) bool {
    if (progress_cb) |cb| cb("Downloading custom libraries...", 0.0, user_data);

    var downloaded: usize = 0;
    var failed: usize = 0;
    const total = client.libraries.len;

    for (client.libraries) |lib| {
        const lib_path = std.fmt.allocPrint(allocator, "libraries/{s}", .{lib.name}) catch continue;
        defer allocator.free(lib_path);

        // Check if already exists
        if (files.fileExists(allocator, lib_path)) {
            std.debug.print("Custom library already exists: {s}\n", .{lib.name});
            downloaded += 1;
            continue;
        }

        // Create parent directory
        if (std.fs.path.dirname(lib_path)) |dir| {
            files.makeDirRecursive(allocator, dir) catch {
                std.debug.print("Failed to create directory for: {s}\n", .{lib.name});
                failed += 1;
                continue;
            };
        }

        const abs_path = files.getAbsolutePath(allocator, lib_path) catch {
            failed += 1;
            continue;
        };
        defer allocator.free(abs_path);

        std.debug.print("Downloading custom library: {s}\n", .{lib.name});

        // Try up to 3 times
        var success = false;
        var attempts: u32 = 0;
        while (attempts < 3) : (attempts += 1) {
            api.downloadFromUrl(allocator, lib.url, abs_path, null, null) catch {
                std.debug.print("  Attempt {}/3 failed for: {s}\n", .{ attempts + 1, lib.name });
                std.Thread.sleep(500 * std.time.ns_per_ms);
                continue;
            };
            success = true;
            break;
        }

        if (!success) {
            std.debug.print("Failed to download after 3 attempts: {s}\n", .{lib.name});
            failed += 1;
        }

        downloaded += 1;
        if (progress_cb) |cb| {
            const progress = @as(f32, @floatFromInt(downloaded)) / @as(f32, @floatFromInt(total));
            cb("Downloading custom libraries...", progress, user_data);
        }
    }

    std.debug.print("Custom libraries: {} total, {} failed\n", .{ total, failed });
    if (progress_cb) |cb| cb("Custom libraries downloaded", 1.0, user_data);
    return failed == 0;
}

/// Downloads the custom client JAR from the client's download URL
pub fn downloadCustomClient(
    allocator: std.mem.Allocator,
    client: json_types.Client,
    progress_cb: ?ProgressCallback,
    user_data: ?*anyopaque,
) bool {
    const client_path = std.fmt.allocPrint(allocator, "versions/{s}/{s}.jar", .{ client.id, client.id }) catch return false;
    defer allocator.free(client_path);

    // Check if already exists
    if (files.fileExists(allocator, client_path)) {
        std.debug.print("Custom client JAR already exists: {s}\n", .{client_path});
        return true;
    }

    if (progress_cb) |cb| cb("Downloading client JAR...", 0.0, user_data);

    // Create directory
    const client_dir = std.fmt.allocPrint(allocator, "versions/{s}", .{client.id}) catch return false;
    defer allocator.free(client_dir);

    files.makeDirRecursive(allocator, client_dir) catch {
        if (progress_cb) |cb| cb("Error: Failed to create client directory", 0.0, user_data);
        return false;
    };

    const abs_path = files.getAbsolutePath(allocator, client_path) catch return false;
    defer allocator.free(abs_path);

    std.debug.print("Downloading client from: {s}\n", .{client.download.url});

    api.downloadFromUrl(allocator, client.download.url, abs_path, null, null) catch {
        if (progress_cb) |cb| cb("Error: Failed to download client JAR", 0.0, user_data);
        return false;
    };

    if (progress_cb) |cb| cb("Client JAR downloaded", 1.0, user_data);
    std.debug.print("Client JAR downloaded to: {s}\n", .{abs_path});
    return true;
}

/// Launches the game
pub fn launchGame(
    allocator: std.mem.Allocator,
    client: json_types.Client,
    progress_cb: ?ProgressCallback,
    user_data: ?*anyopaque,
) !void {
    if (progress_cb) |cb| cb("Preparing to launch...", 0.0, user_data);

    // Get Java executable path
    const java_path = try getJavaExecutable(allocator, client.java.component);
    defer allocator.free(java_path);

    // Get game directory
    const game_dir = try files.getAbsolutePath(allocator, "run");
    defer allocator.free(game_dir);

    // Create game directory if it doesn't exist
    files.makeDirRecursive(allocator, "run") catch {};

    // Get assets directory
    const assets_dir = try files.getAbsolutePath(allocator, "assets");
    defer allocator.free(assets_dir);

    // Get natives directory and extract natives
    const natives_dir = try files.getAbsolutePath(allocator, "natives");
    defer allocator.free(natives_dir);
    files.makeDirRecursive(allocator, "natives") catch {};

    if (progress_cb) |cb| cb("Extracting natives...", 0.2, user_data);
    extractNatives(allocator, natives_dir) catch |err| {
        std.debug.print("Warning: Failed to extract some natives: {}\n", .{err});
    };

    // Build classpath
    const classpath = try buildClasspath(allocator, client);
    defer allocator.free(classpath);

    // Build launch arguments
    var args = std.array_list.Managed([]const u8).init(allocator);
    defer args.deinit();

    // Java executable
    try args.append(java_path);

    // JVM memory arguments
    try args.append("-Xmx2G");
    try args.append("-Xms2G");

    // GC and performance arguments
    try args.append("-XX:+DisableExplicitGC");
    try args.append("-XX:+UseConcMarkSweepGC");
    try args.append("-XX:+UseParNewGC");
    try args.append("-XX:+UseNUMA");
    try args.append("-XX:+CMSParallelRemarkEnabled");
    try args.append("-XX:MaxTenuringThreshold=15");
    try args.append("-XX:MaxGCPauseMillis=30");
    try args.append("-XX:GCPauseIntervalMillis=150");
    try args.append("-XX:+UseAdaptiveGCBoundary");
    try args.append("-XX:-UseGCOverheadLimit");
    try args.append("-XX:+UseBiasedLocking");
    try args.append("-XX:SurvivorRatio=8");
    try args.append("-XX:TargetSurvivorRatio=90");
    try args.append("-Dfml.ignorePatchDiscrepancies=true");
    try args.append("-Dfml.ignoreInvalidMinecraftCertificates=true");
    try args.append("-XX:+UseFastAccessorMethods");
    try args.append("-XX:+UseCompressedOops");
    try args.append("-XX:+OptimizeStringConcat");
    try args.append("-XX:+AggressiveOpts");
    try args.append("-XX:ReservedCodeCacheSize=2048m");
    try args.append("-XX:+UseCodeCacheFlushing");
    try args.append("-XX:SoftRefLRUPolicyMSPerMB=10000");
    try args.append("-XX:ParallelGCThreads=10");

    // Natives path
    const natives_arg = try std.fmt.allocPrint(allocator, "-Djava.library.path={s}", .{natives_dir});
    defer allocator.free(natives_arg);
    try args.append(natives_arg);

    // Classpath
    try args.append("-cp");
    try args.append(classpath);

    // Main class - use launchwrapper for tweak classes
    try args.append("net.minecraft.launchwrapper.Launch");

    // Game arguments
    try args.append("--username");
    try args.append("Player");

    try args.append("--version");
    try args.append(client.id);

    try args.append("--gameDir");
    try args.append(game_dir);

    try args.append("--assetsDir");
    try args.append(assets_dir);

    try args.append("--assetIndex");
    try args.append("1.8"); // TODO: Get from manifest

    try args.append("--accessToken");
    try args.append("0");

    try args.append("--uuid");
    try args.append("00000000-0000-0000-0000-000000000000");

    try args.append("--userType");
    try args.append("legacy");

    try args.append("--userProperties");
    try args.append("{}");

    // Tweak classes - OptiFine first, then client tweaker if specified
    try args.append("--tweakClass");
    try args.append("optifine.OptiFineForgeTweaker");

    if (client.tweakClass) |tweak_class| {
        try args.append("--tweakClass");
        try args.append(tweak_class);
    }

    if (progress_cb) |cb| cb("Launching game...", 0.9, user_data);

    std.debug.print("\n=== LAUNCHING GAME ===\n", .{});
    std.debug.print("Java: {s}\n", .{java_path});
    std.debug.print("Game dir: {s}\n", .{game_dir});
    std.debug.print("Natives: {s}\n", .{natives_dir});
    std.debug.print("Classpath length: {} chars\n", .{classpath.len});
    std.debug.print("======================\n\n", .{});

    // Spawn the process with stdout/stderr piped for logging
    var child = std.process.Child.init(args.items, allocator);
    child.cwd = game_dir;
    child.stdout_behavior = .Inherit;
    child.stderr_behavior = .Inherit;

    _ = child.spawn() catch |err| {
        std.debug.print("Failed to spawn process: {}\n", .{err});
        if (progress_cb) |cb| cb("Error: Failed to launch game", 0.0, user_data);
        return err;
    };

    if (progress_cb) |cb| cb("Game launched!", 1.0, user_data);
}

/// Extracts native libraries from JAR files in the libraries directory
fn extractNatives(allocator: std.mem.Allocator, natives_dir: []const u8) !void {
    const libs_dir = try files.getAbsolutePath(allocator, "libraries");
    defer allocator.free(libs_dir);

    try extractNativesFromDir(allocator, libs_dir, natives_dir);
}

fn extractNativesFromDir(allocator: std.mem.Allocator, dir_path: []const u8, natives_dir: []const u8) !void {
    var dir = std.fs.openDirAbsolute(dir_path, .{ .iterate = true }) catch return;
    defer dir.close();

    const builtin = @import("builtin");
    const native_suffix = switch (builtin.os.tag) {
        .linux => "natives-linux",
        .windows => "natives-windows",
        .macos => "natives-osx",
        else => "natives-linux",
    };

    var iterator = dir.iterate();
    while (try iterator.next()) |entry| {
        const full_path = try std.fs.path.join(allocator, &.{ dir_path, entry.name });
        defer allocator.free(full_path);

        if (entry.kind == .directory) {
            try extractNativesFromDir(allocator, full_path, natives_dir);
        } else if (entry.kind == .file) {
            // Check if it's a natives JAR file
            if (std.mem.endsWith(u8, entry.name, ".jar") and
                std.mem.indexOf(u8, entry.name, native_suffix) != null) {
                std.debug.print("Extracting natives from: {s}\n", .{entry.name});
                extractJarToDir(allocator, full_path, natives_dir) catch |err| {
                    std.debug.print("  Warning: Failed to extract {s}: {}\n", .{entry.name, err});
                };
            }
        }
    }
}

fn extractJarToDir(_: std.mem.Allocator, jar_path: []const u8, dest_dir: []const u8) !void {
    var jar_file = try std.fs.openFileAbsolute(jar_path, .{});
    defer jar_file.close();

    var dest = try std.fs.openDirAbsolute(dest_dir, .{});
    defer dest.close();

    var read_buffer: [4096]u8 = undefined;
    var file_reader = jar_file.reader(&read_buffer);

    // Extract all files - META-INF will be extracted but shouldn't cause issues
    std.zip.extract(dest, &file_reader, .{}) catch |err| {
        // Some JARs may have issues, just log and continue
        std.debug.print("  Zip extraction issue: {}\n", .{err});
    };
}

fn getJavaExecutable(allocator: std.mem.Allocator, java_component: []const u8) ![]const u8 {
    const builtin = @import("builtin");

    const java_bin = if (builtin.os.tag == .windows)
        try std.fmt.allocPrint(allocator, "java/{s}/bin/java.exe", .{java_component})
    else
        try std.fmt.allocPrint(allocator, "java/{s}/bin/java", .{java_component});
    defer allocator.free(java_bin);

    return try files.getAbsolutePath(allocator, java_bin);
}

fn buildClasspath(allocator: std.mem.Allocator, client: json_types.Client) ![]const u8 {
    const builtin = @import("builtin");
    const sep = if (builtin.os.tag == .windows) ";" else ":";

    var classpath = std.array_list.Managed(u8).init(allocator);
    errdefer classpath.deinit();

    // Add custom libraries from client config (launchwrapper, optifine, etc.)
    for (client.libraries) |lib| {
        const lib_path = try std.fmt.allocPrint(allocator, "libraries/{s}", .{lib.name});
        defer allocator.free(lib_path);

        if (files.fileExists(allocator, lib_path)) {
            const abs_path = try files.getAbsolutePath(allocator, lib_path);
            defer allocator.free(abs_path);

            std.debug.print("Adding custom library to classpath: {s}\n", .{lib.name});

            if (classpath.items.len > 0) {
                try classpath.appendSlice(sep);
            }
            try classpath.appendSlice(abs_path);
        }
    }

    // Scan the libraries directory for all Mojang libraries
    const libs_dir_path = try files.getAbsolutePath(allocator, "libraries");
    defer allocator.free(libs_dir_path);

    try addLibrariesFromDir(allocator, &classpath, libs_dir_path, sep);

    // Add the vanilla Minecraft JAR (e.g., 1.8.9.jar) - look for version with a dot in name
    const versions_dir_path = try files.getAbsolutePath(allocator, "versions");
    defer allocator.free(versions_dir_path);

    try addVanillaMinecraftJar(allocator, &classpath, versions_dir_path, sep);

    // Add the specific custom client JAR for this version
    const client_jar_path = try std.fmt.allocPrint(allocator, "versions/{s}/{s}.jar", .{ client.id, client.id });
    defer allocator.free(client_jar_path);

    if (files.fileExists(allocator, client_jar_path)) {
        const abs_client_jar = try files.getAbsolutePath(allocator, client_jar_path);
        defer allocator.free(abs_client_jar);

        std.debug.print("Adding client JAR to classpath: {s}\n", .{client_jar_path});

        if (classpath.items.len > 0) {
            try classpath.appendSlice(sep);
        }
        try classpath.appendSlice(abs_client_jar);
    }

    return try classpath.toOwnedSlice();
}

/// Only adds vanilla Minecraft JARs (version names with dots like "1.8.9")
fn addVanillaMinecraftJar(allocator: std.mem.Allocator, classpath: *std.array_list.Managed(u8), versions_dir: []const u8, sep: []const u8) !void {
    var dir = std.fs.openDirAbsolute(versions_dir, .{ .iterate = true }) catch return;
    defer dir.close();

    var iterator = dir.iterate();
    while (try iterator.next()) |entry| {
        if (entry.kind == .directory) {
            // Only process vanilla versions (contain a dot, like "1.8.9")
            if (std.mem.indexOf(u8, entry.name, ".") == null) continue;

            const version_dir = try std.fs.path.join(allocator, &.{ versions_dir, entry.name });
            defer allocator.free(version_dir);

            var sub_dir = std.fs.openDirAbsolute(version_dir, .{ .iterate = true }) catch continue;
            defer sub_dir.close();

            var sub_iterator = sub_dir.iterate();
            while (try sub_iterator.next()) |sub_entry| {
                if (sub_entry.kind == .file and std.mem.endsWith(u8, sub_entry.name, ".jar")) {
                    const jar_path = try std.fs.path.join(allocator, &.{ version_dir, sub_entry.name });
                    defer allocator.free(jar_path);

                    std.debug.print("Adding vanilla Minecraft JAR to classpath: {s}\n", .{jar_path});

                    if (classpath.items.len > 0) {
                        try classpath.appendSlice(sep);
                    }
                    try classpath.appendSlice(jar_path);
                }
            }
        }
    }
}

fn addLibrariesFromDir(allocator: std.mem.Allocator, classpath: *std.array_list.Managed(u8), dir_path: []const u8, sep: []const u8) !void {
    var dir = std.fs.openDirAbsolute(dir_path, .{ .iterate = true }) catch return;
    defer dir.close();

    var iterator = dir.iterate();
    while (try iterator.next()) |entry| {
        const full_path = try std.fs.path.join(allocator, &.{ dir_path, entry.name });
        defer allocator.free(full_path);

        if (entry.kind == .directory) {
            // Recursively search subdirectories
            try addLibrariesFromDir(allocator, classpath, full_path, sep);
        } else if (entry.kind == .file) {
            // Check if it's a .jar file
            if (std.mem.endsWith(u8, entry.name, ".jar")) {
                if (classpath.items.len > 0) {
                    try classpath.appendSlice(sep);
                }
                try classpath.appendSlice(full_path);
            }
        }
    }
}

