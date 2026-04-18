const std = @import("std");

// Using 'opaque' gives us type safety so we don't mix up
// Classes, Selectors, and Instances.
pub const Class = opaque {};
pub const Sel = opaque {};
pub const Object = opaque {};
pub const ID = ?*anyopaque;

// These are the actual symbols exported by /usr/lib/libobjc.A.dylib
pub extern "c" fn objc_getClass(name: [*c]const u8) ?*Class;
pub extern "c" fn sel_registerName(name: [*c]const u8) ?*Sel;

// Note: On ARM64 (Apple Silicon), this simple signature works for most things.
// On x86_64, you'd need different variants for different return types.
pub extern "c" fn objc_msgSend(self: ?*anyopaque, op: ?*Sel, ...) ?*anyopaque;

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
    ptr: ID,

    pub fn init() App {
        const cls = objc_getClass("NSApplication");
        const app = objc_msgSend(cls, sel_registerName("sharedApplication"));

        // 1. Make it a regular GUI app
        const setPolicyFn = *const fn (?*anyopaque, ?*Sel, isize) callconv(.c) void;
        const msgSendPolicy: setPolicyFn = @ptrCast(&objc_msgSend);
        msgSendPolicy(app, sel_registerName("setActivationPolicy:"), 0);

        // 2. Force it to the front
        const activateFn = *const fn (?*anyopaque, ?*Sel, u8) callconv(.c) void;
        const msgSendActivate: activateFn = @ptrCast(&objc_msgSend);
        msgSendActivate(app, sel_registerName("activateIgnoringOtherApps:"), 1);

        return .{ .ptr = app };
    }

    pub fn run(self: App) void {
        const sel = sel_registerName("run");
        _ = objc_msgSend(self.ptr, sel);
    }
};

pub const Window = struct {
    ptr: ID,

    pub fn init(rect: NSRect) Window {
        const cls = objc_getClass("NSWindow");
        const sel_alloc = sel_registerName("alloc");
        const sel_init = sel_registerName("initWithContentRect:styleMask:backing:defer:");

        const instance = objc_msgSend(cls, sel_alloc);

        // 1. Define the EXACT function signature for this specific call
        const InitFn = *const fn (
            ?*anyopaque, // self
            ?*Sel, // _cmd
            NSRect, // contentRect
            usize, // styleMask
            usize, // backing
            u8, // defer
        ) callconv(.c) ?*anyopaque;

        // 2. Cast objc_msgSend to that signature
        const msgSendInit: InitFn = @ptrCast(&objc_msgSend);

        // 3. Call it
        const window = msgSendInit(instance, sel_init, rect, @as(usize, 15), @as(usize, 2), @as(u8, 0));

        return .{ .ptr = window };
    }

    pub fn show(self: Window) void {
        const sel = sel_registerName("makeKeyAndOrderFront:");
        _ = objc_msgSend(self.ptr, sel, @as(ID, null));
    }

    pub fn setTitle(self: Window, title: [:0]const u8) void {
        const cls_string = objc_getClass("NSString");
        const sel_utf8 = sel_registerName("stringWithUTF8String:");
        const sel_set_title = sel_registerName("setTitle:");

        // 1. Create the NSString (Foundation Object)
        // We cast msgSend to ensure the return is treated as a pointer
        const CreateStrFn = *const fn (?*anyopaque, ?*Sel, [*c]const u8) callconv(.c) ?*anyopaque;
        const msgSendCreate: CreateStrFn = @ptrCast(&objc_msgSend);

        const ns_title = msgSendCreate(cls_string, sel_utf8, title.ptr) orelse return; // Safety check: if string creation fails, don't set it.

        // 2. Pass the NSString to the Window
        const SetTitleFn = *const fn (?*anyopaque, ?*Sel, ?*anyopaque) callconv(.c) void;
        const msgSendSetTitle: SetTitleFn = @ptrCast(&objc_msgSend);

        msgSendSetTitle(self.ptr, sel_set_title, ns_title);
    }
};
