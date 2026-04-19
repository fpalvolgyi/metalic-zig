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
