pub const Client = struct {
    id: []const u8,
    name: []const u8,
    java: Java,
    libraries: []Library,
    download: Download,
    manifest_url: ?[]const u8 = null,
    tweakClass: ?[]const u8 = null,
};

pub const Java = struct {
    component: []const u8,
    version: u32,
};

pub const JavaDownload = struct {
    url: []const u8,
    sha256: []const u8,
    size: u64,
};

pub const Library = struct {
    name: []const u8,
    url: []const u8,
    sha256: []const u8,
    size: u64,
};

pub const Download = struct {
    url: []const u8,
    sha256: []const u8,
    size: u64,
};

pub const VersionManifest = struct {
    latest: []const u8,
    versions: [][]const u8,
};