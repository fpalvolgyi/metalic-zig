// Opaque types give compile-time type safety — you can't mix a Class pointer
// with a Sel pointer even though both are just pointers at runtime.
pub const Class = opaque {};
pub const Sel = opaque {};
pub const Object = opaque {};
pub const ID = ?*anyopaque;

pub extern "c" fn objc_getClass(name: [*c]const u8) ?*Class;
pub extern "c" fn sel_registerName(name: [*c]const u8) ?*Sel;
pub extern "c" fn objc_msgSend(self: ?*anyopaque, op: ?*Sel, ...) ?*anyopaque;

// ObjC runtime class registration
pub extern "c" fn objc_allocateClassPair(superclass: ?*anyopaque, name: [*:0]const u8, extra_bytes: usize) ?*anyopaque;
pub extern "c" fn objc_registerClassPair(cls: ?*anyopaque) void;
pub extern "c" fn class_addMethod(cls: ?*anyopaque, name: ?*Sel, imp: *const anyopaque, types: [*:0]const u8) bool;

/// Look up a class and return it as an untyped ID so it can be passed
/// directly to `send` without an explicit @ptrCast at every call site.
pub fn getClass(name: [*c]const u8) ID {
    return @ptrCast(objc_getClass(name));
}

/// Type-safe Objective-C message send.
///
///   send(ReturnType, receiver, "selectorName:", .{ arg1, arg2 })
///
/// The selector is a comptime string so it is registered once per call site
/// and cached.  The argument tuple drives the generated C function type, so
/// the compiler catches arity and type mistakes at compile time.
///
/// Supports up to 5 extra arguments (covers all ObjC calls in this project).
pub fn send(comptime Ret: type, obj: ID, comptime sel_name: [:0]const u8, args: anytype) Ret {
    const op = sel_registerName(sel_name);

    const fields = @typeInfo(@TypeOf(args)).@"struct".fields;

    // Each branch builds a statically-typed function pointer and calls it
    // directly — no @call + tuple, which avoids argument-ordering pitfalls.
    if (fields.len == 0) {
        const F = *const fn (ID, ?*Sel) callconv(.c) Ret;
        return @as(F, @ptrCast(&objc_msgSend))(obj, op);
    } else if (fields.len == 1) {
        const F = *const fn (ID, ?*Sel, fields[0].type) callconv(.c) Ret;
        return @as(F, @ptrCast(&objc_msgSend))(obj, op,
            @field(args, fields[0].name));
    } else if (fields.len == 2) {
        const F = *const fn (ID, ?*Sel, fields[0].type, fields[1].type) callconv(.c) Ret;
        return @as(F, @ptrCast(&objc_msgSend))(obj, op,
            @field(args, fields[0].name),
            @field(args, fields[1].name));
    } else if (fields.len == 3) {
        const F = *const fn (ID, ?*Sel, fields[0].type, fields[1].type, fields[2].type) callconv(.c) Ret;
        return @as(F, @ptrCast(&objc_msgSend))(obj, op,
            @field(args, fields[0].name),
            @field(args, fields[1].name),
            @field(args, fields[2].name));
    } else if (fields.len == 4) {
        const F = *const fn (ID, ?*Sel, fields[0].type, fields[1].type, fields[2].type, fields[3].type) callconv(.c) Ret;
        return @as(F, @ptrCast(&objc_msgSend))(obj, op,
            @field(args, fields[0].name),
            @field(args, fields[1].name),
            @field(args, fields[2].name),
            @field(args, fields[3].name));
    } else if (fields.len == 5) {
        const F = *const fn (ID, ?*Sel, fields[0].type, fields[1].type, fields[2].type, fields[3].type, fields[4].type) callconv(.c) Ret;
        return @as(F, @ptrCast(&objc_msgSend))(obj, op,
            @field(args, fields[0].name),
            @field(args, fields[1].name),
            @field(args, fields[2].name),
            @field(args, fields[3].name),
            @field(args, fields[4].name));
    } else {
        @compileError("send: too many arguments (max 5)");
    }
}

pub fn stringWithUTF8String(text: [:0]const u8) ID {
    return send(ID, getClass("NSString"), "stringWithUTF8String:", .{text.ptr});
}
