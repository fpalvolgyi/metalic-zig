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

pub const App = struct {
    ptr: objc.ID,

    pub fn init() App {
        const cls = objc.objc_getClass("NSApplication");
        const app = objc.objc_msgSend(cls, objc.sel_registerName("sharedApplication"));

        // 1. Make it a regular GUI app
        const setPolicyFn = *const fn (?*anyopaque, ?*objc.Sel, isize) callconv(.c) void;
        const msgSendPolicy: setPolicyFn = @ptrCast(&objc.objc_msgSend);
        msgSendPolicy(app, objc.sel_registerName("setActivationPolicy:"), 0);

        // 2. Force it to the front
        const activateFn = *const fn (?*anyopaque, ?*objc.Sel, u8) callconv(.c) void;
        const msgSendActivate: activateFn = @ptrCast(&objc.objc_msgSend);
        msgSendActivate(app, objc.sel_registerName("activateIgnoringOtherApps:"), 1);

        return .{ .ptr = app };
    }

    pub fn run(self: App) void {
        const sel = objc.sel_registerName("run");
        _ = objc.objc_msgSend(self.ptr, sel);
    }
};

pub const Window = struct {
    ptr: objc.ID,

    pub fn init(rect: NSRect) Window {
        const cls = objc.objc_getClass("NSWindow");
        const sel_alloc = objc.sel_registerName("alloc");
        const sel_init = objc.sel_registerName("initWithContentRect:styleMask:backing:defer:");

        const instance = objc.objc_msgSend(cls, sel_alloc);

        // 1. Define the EXACT function signature for this specific call
        const InitFn = *const fn (
            ?*anyopaque, // self
            ?*objc.Sel, // _cmd
            NSRect, // contentRect
            usize, // styleMask
            usize, // backing
            u8, // defer
        ) callconv(.c) ?*anyopaque;

        // 2. Cast objc_msgSend to that signature
        const msgSendInit: InitFn = @ptrCast(&objc.objc_msgSend);

        // 3. Call it
        const window = msgSendInit(instance, sel_init, rect, @as(usize, 15), @as(usize, 2), @as(u8, 0));

        return .{ .ptr = window };
    }

    pub fn show(self: Window) void {
        const sel = objc.sel_registerName("makeKeyAndOrderFront:");
        _ = objc.objc_msgSend(self.ptr, sel, @as(objc.ID, null));
    }

    pub fn setTitle(self: Window, title: [:0]const u8) void {
        const cls_string = objc.objc_getClass("NSString");
        const sel_utf8 = objc.sel_registerName("stringWithUTF8String:");
        const sel_set_title = objc.sel_registerName("setTitle:");

        // 1. Create the NSString (Foundation Object)
        // We cast msgSend to ensure the return is treated as a pointer
        const CreateStrFn = *const fn (?*anyopaque, ?*objc.Sel, [*c]const u8) callconv(.c) ?*anyopaque;
        const msgSendCreate: CreateStrFn = @ptrCast(&objc.objc_msgSend);

        const ns_title = msgSendCreate(cls_string, sel_utf8, title.ptr) orelse return; // Safety check: if string creation fails, don't set it.

        // 2. Pass the NSString to the Window
        const SetTitleFn = *const fn (?*anyopaque, ?*objc.Sel, ?*anyopaque) callconv(.c) void;
        const msgSendSetTitle: SetTitleFn = @ptrCast(&objc.objc_msgSend);

        msgSendSetTitle(self.ptr, sel_set_title, ns_title);
    }
};
