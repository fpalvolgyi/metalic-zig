const std = @import("std");
const appkit = @import("appkit.zig");

pub fn main() !void {
    const my_app = appkit.App.init();

    const win_rect = appkit.NSRect{ .x = 300, .y = 300, .w = 400, .h = 300 };
    const my_window = appkit.Window.init(win_rect);

    my_window.setTitle("Metal computer");
    my_window.show();

    my_app.run();
}
