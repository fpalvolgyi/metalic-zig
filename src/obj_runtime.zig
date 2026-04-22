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

pub fn stringWithUTF8String(text: [:0]const u8) ID {
    const cls_string = objc_getClass("NSString");
    const sel_utf8 = sel_registerName("stringWithUTF8String:");

    // 1. Create the NSString (Foundation Object)
    // We cast msgSend to ensure the return is treated as a pointer
    const CreateStrFn = *const fn (?*anyopaque, ?*Sel, [*c]const u8) callconv(.c) ?*anyopaque;
    const msgSendCreate: CreateStrFn = @ptrCast(&objc_msgSend);

    return msgSendCreate(cls_string, sel_utf8, text.ptr);
}
