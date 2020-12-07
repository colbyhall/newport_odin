// +build windows
package gl

import "core:sys/win32"
import "core:reflect"
import "core:strings"
import "core:log"

import "../../core"

WGL_DRAW_TO_WINDOW_ARB           :: 0x2001;
WGL_ACCELERATION_ARB             :: 0x2003;
WGL_FULL_ACCELERATION_ARB        :: 0x2027;
WGL_SUPPORT_OPENGL_ARB           :: 0x2010;
WGL_DOUBLE_BUFFER_ARB            :: 0x2011;
WGL_PIXEL_TYPE_ARB               :: 0x2013;
WGL_TYPE_RGBA_ARB                :: 0x202B;
WGL_FRAMEBUFFER_SRGB_CAPABLE_ARB :: 0x20A9;

WGL_COLOR_BITS_ARB :: 0x2014;
WGL_DEPTH_BITS_ARB :: 0x2022;
WGL_STENCIL_BITS_ARB :: 0x2023;

WGL_SAMPLE_BUFFERS_ARB :: 0x2041;
WGL_SAMPLES_ARB :: 0x2042;

load :: proc() -> bool {
    window, ok := core.make_window("gl window", 20, 20);
    if !ok do return false;
    defer core.delete_window(&window);

    window_context := win32.get_dc(window.handle);
    defer win32.release_dc(window.handle, window_context);

    pfd : win32.Pixel_Format_Descriptor;
    pfd.size        = size_of(pfd);
    pfd.version     = 1;
    pfd.pixel_type  = win32.PFD_TYPE_RGBA;
    pfd.flags       = win32.PFD_SUPPORT_OPENGL | win32.PFD_DRAW_TO_WINDOW | win32.PFD_DOUBLEBUFFER;
    pfd.color_bits  = 32;
    pfd.depth_bits  = 24;
    pfd.alpha_bits  = 8;
    pfd.layer_type  = win32.PFD_MAIN_PLANE;

    suggested_pixel_format_index := win32.choose_pixel_format(window_context, &pfd);

    win32.describe_pixel_format(window_context, suggested_pixel_format_index, size_of(pfd), &pfd);
    win32.set_pixel_format(window_context, suggested_pixel_format_index, &pfd);

    glrc := win32.create_context(window_context);
    defer win32.delete_context(glrc);

    if win32.make_current(window_context, glrc) {
        defer win32.make_current(window_context, nil);
        
        win32.choose_pixel_format_arb    = auto_cast win32.get_gl_proc_address("wglChoosePixelFormatARB");
        win32.create_context_attribs_arb = auto_cast win32.get_gl_proc_address("wglCreateContextAttribsARB");
        win32.swap_interval_ext          = auto_cast win32.get_gl_proc_address("wglSwapIntervalEXT");

        using reflect;

        // TODO: Redo this in a good way. I was a baby when i wrote this
        id := typeid_of(type_of(extensions));
        num_fields := len(struct_field_names(id));
        for i in 0..<num_fields {
            field := struct_field_at(id, i);
            cstr := strings.clone_to_cstring(field.name, context.temp_allocator); 

            val  := (^u64)(uintptr(&extensions) + field.offset);
            val^ = auto_cast uintptr(win32.get_gl_proc_address(cstr));
            if val^ == 0 do return false;
        }
    }

    return true;
}

@private 
pixel_format_attribs := []i32 {
    WGL_DRAW_TO_WINDOW_ARB,           GL_TRUE,
    WGL_ACCELERATION_ARB,             WGL_FULL_ACCELERATION_ARB,
    WGL_SUPPORT_OPENGL_ARB,           GL_TRUE,
    WGL_DOUBLE_BUFFER_ARB,            GL_TRUE,
    
    WGL_PIXEL_TYPE_ARB,               WGL_TYPE_RGBA_ARB,
    WGL_COLOR_BITS_ARB,               32,
    WGL_DEPTH_BITS_ARB,               24,
    WGL_STENCIL_BITS_ARB,             8,

    WGL_FRAMEBUFFER_SRGB_CAPABLE_ARB, GL_TRUE,
    WGL_SAMPLE_BUFFERS_ARB,           GL_TRUE,
    WGL_SAMPLES_ARB,                  4,
    0,
};

create_surface :: proc(using window: ^core.Window) {
    window_context := win32.get_dc(handle);
    defer win32.release_dc(handle, window_context);

    pixel_format : i32 = ---;
    num_formats  : u32 = ---;
    win32.choose_pixel_format_arb(window_context, &pixel_format_attribs[0], nil, 1, &pixel_format, &num_formats);

    pfd : win32.Pixel_Format_Descriptor;
    win32.describe_pixel_format(window_context, pixel_format, size_of(pfd), &pfd);
    win32.set_pixel_format(window_context, pixel_format, &pfd);
}

make_current :: proc(window: core.Window, maj_version := 3, min_version := 3) -> bool {
    context_attribs := []i32 {
        win32.CONTEXT_MAJOR_VERSION_ARB, cast(i32)maj_version,
        win32.CONTEXT_MINOR_VERSION_ARB, cast(i32)min_version,
        win32.CONTEXT_FLAGS_ARB, win32.CONTEXT_FORWARD_COMPATIBLE_BIT_ARB,
        win32.CONTEXT_PROFILE_MASK_ARB, win32.CONTEXT_CORE_PROFILE_BIT_ARB,
        0,
    };
    
    window_context := win32.get_dc(window.handle);
    defer win32.release_dc(window.handle, window_context);

    win32.swap_interval_ext(0);

    glrc := win32.create_context_attribs_arb(window_context, nil, &context_attribs[0]);
    if win32.make_current(window_context, glrc) {
        ctx.is_valid = true;

        glGetIntegerv(GL_MAJOR_VERSION, &ctx.maj_version);
        glGetIntegerv(GL_MINOR_VERSION, &ctx.min_version);

        log.info("[OpenGL]", cstring(glGetString(GL_VENDOR)), cstring(glGetString(GL_RENDERER)));

        return true;
    }


    return false;
}