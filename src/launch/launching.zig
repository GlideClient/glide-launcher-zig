const types = @import("../json/types.zig");

pub const LaunchContext = struct {
    selected_version: ?[]const u8,
    client: ?types.Client,

    pub fn init() LaunchContext {
        return .{
            .selected_version = null,
            .client = null,
        };
    }
};

var ctx: ?*LaunchContext = null;

pub fn set(context: *LaunchContext) void {
    ctx = context;
}

pub fn get() *LaunchContext {
    return ctx.?;
}

