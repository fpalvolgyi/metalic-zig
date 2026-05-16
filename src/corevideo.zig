// Minimal CoreVideo bindings — CVDisplayLink only.
// CVDisplayLink fires its callback on a private thread, synchronized to the
// display hardware refresh rate.  On ProMotion displays this is up to 120 Hz.

pub const CVDisplayLinkRef = ?*anyopaque;
pub const CVReturn = i32;
pub const CVOptionFlags = u64;

pub const CVDisplayLinkOutputCallback = *const fn (
    link: CVDisplayLinkRef,
    now: ?*const anyopaque,        // const CVTimeStamp* — ignored for basic use
    output_time: ?*const anyopaque, // const CVTimeStamp*
    flags_in: CVOptionFlags,
    flags_out: ?*CVOptionFlags,
    ctx: ?*anyopaque,
) callconv(.c) CVReturn;

pub extern "c" fn CVDisplayLinkCreateWithActiveCGDisplays(link_out: *CVDisplayLinkRef) CVReturn;
pub extern "c" fn CVDisplayLinkSetOutputCallback(link: CVDisplayLinkRef, cb: CVDisplayLinkOutputCallback, ctx: ?*anyopaque) CVReturn;
pub extern "c" fn CVDisplayLinkStart(link: CVDisplayLinkRef) CVReturn;
pub extern "c" fn CVDisplayLinkStop(link: CVDisplayLinkRef) CVReturn;
