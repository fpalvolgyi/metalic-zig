const std = @import("std");
const objc = @import("obj_runtime.zig");

pub const NSWindowStyleMaskTitled = 1 << 0;
pub const NSWindowStyleMaskClosable = 1 << 1;
pub const NSWindowStyleMaskResizable = 1 << 3;

pub const NSBackingStoreBuffered = 2;

pub const NSRect = extern struct {
    x: f64,
    y: f64,
    w: f64,
    h: f64,
};

pub const NSEventMaskAny = @as(u64, 0xFFFFFFFFFFFFFFFF);

pub const App = struct {
    ptr: objc.ID,

    pub fn init() App {
        const app = objc.send(objc.ID, objc.getClass("NSApplication"), "sharedApplication", .{});
        objc.send(void, app, "setActivationPolicy:", .{@as(isize, 0)});
        return .{ .ptr = app };
    }

    pub fn run(self: App) void {
        objc.send(void, self.ptr, "run", .{});
    }

    pub fn setDelegate(self: App, delegate: objc.ID) void {
        objc.send(void, self.ptr, "setDelegate:", .{delegate});
    }

    pub fn nextEvent(self: App) ?objc.ID {
        const mode = objc.send(objc.ID, objc.getClass("NSString"), "stringWithUTF8String:", .{@as([*c]const u8, "NSDefaultRunLoopMode")});
        const distantPast = objc.send(objc.ID, objc.getClass("NSDate"), "distantPast", .{});
        return objc.send(objc.ID, self.ptr, "nextEventMatchingMask:untilDate:inMode:dequeue:", .{
            @as(u64, 0xFFFFFFFFFFFFFFFF),
            distantPast,
            mode,
            @as(u8, 1),
        });
    }

    pub fn sendEvent(self: App, event: objc.ID) void {
        objc.send(void, self.ptr, "sendEvent:", .{event});
    }

    pub fn updateWindows(self: App) void {
        objc.send(void, self.ptr, "updateWindows", .{});
    }
};

pub const Window = struct {
    ptr: objc.ID,

    pub fn init(rect: NSRect) Window {
        const cls = objc.getClass("NSWindow");
        const instance = objc.send(objc.ID, cls, "alloc", .{});
        const window = objc.send(objc.ID, instance, "initWithContentRect:styleMask:backing:defer:", .{
            rect,
            @as(usize, 15), // Titled | Closable | Miniaturizable | Resizable
            @as(usize, 2),  // NSBackingStoreBuffered
            @as(u8, 0),
        });
        return .{ .ptr = window };
    }

    pub fn show(self: Window) void {
        objc.send(void, self.ptr, "makeKeyAndOrderFront:", .{@as(objc.ID, null)});
    }

    pub fn setTitle(self: Window, title: [:0]const u8) void {
        const ns_title = objc.send(objc.ID, objc.getClass("NSString"), "stringWithUTF8String:", .{title.ptr});
        objc.send(void, self.ptr, "setTitle:", .{ns_title});
    }
};
