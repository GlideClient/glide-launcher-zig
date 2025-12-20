const FontData = struct {
    name: [:0]const u8,
    data: []const u8,
};

pub const fonts = [_]FontData{
    .{ .name = "regular", .data = @embedFile("fonts/InterTight-Regular.ttf") },
    .{ .name = "semibold", .data = @embedFile("fonts/InterTight-SemiBold.ttf") },
    .{ .name = "bold", .data = @embedFile("fonts/InterTight-Bold.ttf") },
    .{ .name = "mono", .data = @embedFile("fonts/MapleMono-Regular.ttf") },
    .{ .name = "glicons", .data = @embedFile("fonts/Gliconic.ttf") },
    .{ .name = "fluent_filled", .data = @embedFile("fonts/FluentSystemIcons-Filled.ttf") },
    .{ .name = "fluent_regular", .data = @embedFile("fonts/FluentSystemIcons-Regular.ttf") },
};

pub const Regular = fonts[0].name;
pub const SemiBold = fonts[1].name;
pub const Bold = fonts[2].name;
pub const Mono = fonts[3].name;
pub const Glicons = fonts[4].name;
pub const FluentFilled = fonts[5].name;
pub const FluentRegular = fonts[6].name;
