// +build windows
package core

import "core:sys/win32"
import "core:fmt"
import "core:strings"
import "core:runtime"
import "core:dynlib"
import "core:time"

foreign import "system:user32.lib"

Window_Handle :: win32.Hwnd;

@export NvOptimusEnablement : u32 = 0x01;
@export AmdPowerXpressRequestHighPerformance : u32 = 0x01;

win_proc :: proc "c" (hwnd: win32.Hwnd, msg: u32, wparam: win32.Wparam, lparam: win32.Lparam) -> win32.Lresult {
    c : ^runtime.Context = cast(^runtime.Context)uintptr(win32.get_window_long_ptr_a(hwnd, win32.GWLP_USERDATA));

    if c == nil do return win32.def_window_proc_a(hwnd, msg, wparam, lparam);

    context = c^;

    window : ^Window = cast(^Window)context.user_ptr;

    if window == nil do return win32.def_window_proc_a(hwnd, msg, wparam, lparam);

    @static surrogate_pair_first : u32 = 0;

    switch msg {
    case win32.WM_DESTROY:
        e : Exit_Request_Event;

        e.window = window;

        dispatch_event(&window.dispatcher, &e);
    case win32.WM_SIZING, win32.WM_SIZE:
        e : Window_Resize_Event;
        
        e.window     = window;
        e.old_width  = window.width;
        e.old_height = window.height;

        rect : win32.Rect;
        win32.get_client_rect(window.handle, &rect);

        window.width  = cast(int)(rect.right - rect.left);
        window.height = cast(int)(rect.bottom - rect.top);

        dispatch_event(&window.dispatcher, &e);
    case win32.WM_SYSKEYDOWN, win32.WM_KEYDOWN, win32.WM_SYSKEYUP, win32.WM_KEYUP:
        e : Key_Event;

        e.window  = window;
        e.key     = cast(u8)wparam;
        e.pressed = !cast(bool)((lparam >> 31) & 0x1); // 31st bit of lparam is transition state

        dispatch_event(&window.dispatcher, &e);
    case win32.WM_LBUTTONDOWN, win32.WM_RBUTTONDOWN, win32.WM_MBUTTONDOWN:
        e : Mouse_Button_Event;

        e.window  = window;
        e.pressed = true; 

        switch msg {
        case win32.WM_LBUTTONDOWN:
            e.mouse_button = 0;
        case win32.WM_MBUTTONDOWN:
            e.mouse_button = 1;
        case win32.WM_RBUTTONDOWN:
            e.mouse_button = 2;
        }

        SetCapture(hwnd);

        dispatch_event(&window.dispatcher, &e);
    case win32.WM_LBUTTONUP, win32.WM_RBUTTONUP, win32.WM_MBUTTONUP:
        e : Mouse_Button_Event;

        e.window  = window;
        e.pressed = false;

        switch msg {
        case win32.WM_LBUTTONUP:
            e.mouse_button = 0;
        case win32.WM_MBUTTONUP:
            e.mouse_button = 1;
        case win32.WM_RBUTTONUP:
            e.mouse_button = 2;
        }

        ReleaseCapture();

        dispatch_event(&window.dispatcher, &e);
    case win32.WM_MOUSEMOVE: 
        e : Mouse_Move_Event;

        e.window  = window;
        e.mouse_x = cast(int)(lparam & 0xffff);
        e.mouse_y = -cast(int)((lparam >> 16) & 0xffff) + window.height;

        dispatch_event(&window.dispatcher, &e);
    case win32.WM_MOUSEWHEEL:
        e : Mouse_Wheel_Event;

        e.window = window;
        e.delta = (i16)(wparam >> 16);

        dispatch_event(&window.dispatcher, &e);
    case win32.WM_CHAR:
        e : Char_Event;

        e.window = window;

        char := u32(wparam);

        if char < 32 && char != '\t' do return 0;
        if char == 127 do return 0;

        if char >= 0xd800 && char <= 0xdbff {
            surrogate_pair_first = char;
            return 0;
        } else if char >= 0xdc00 && char <= 0xdfff {
            second_pair := char;
            char = 0x10000;
            char += (surrogate_pair_first & 0x03ff) << 10;
            char += second_pair & 0x03ff;
        }

        e.char = cast(rune)char;

        dispatch_event(&window.dispatcher, &e);
    }

    return win32.def_window_proc_a(hwnd, msg, wparam, lparam); // @TODO(colby): Error handler
}

make_window :: proc(title: string, width: int, height: int) -> (window: Window, ok: bool) {
    window_class : win32.Wnd_Class_A;
    window_class.wnd_proc = auto_cast win_proc;
    window_class.instance = auto_cast win32.get_module_handle_a(nil);
    window_class.cursor   = win32.load_cursor_a(nil, win32.IDC_ARROW);

    class_name := fmt.tprint(title, "_class");
    window_class.class_name = strings.clone_to_cstring(class_name, context.temp_allocator);

    win32.register_class_a(&window_class);

    adjusted_rect := win32.Rect { 0, 0, i32(width), i32(height) };
    win32.adjust_window_rect(&adjusted_rect, win32.WS_OVERLAPPEDWINDOW, false);
    width  := int(adjusted_rect.right - adjusted_rect.left);
    height := int(adjusted_rect.bottom - adjusted_rect.top);

    monitor_width  := win32.get_system_metrics(win32.SM_CXSCREEN);
    monitor_height := win32.get_system_metrics(win32.SM_CYSCREEN);

    x := monitor_width / 2 - adjusted_rect.right / 2;
    y := monitor_height / 2 - adjusted_rect.bottom / 2;

    hwnd := win32.create_window_ex_a(
        0, 
        window_class.class_name, 
        strings.clone_to_cstring(title, context.temp_allocator), 
        win32.WS_OVERLAPPEDWINDOW,
        x, y, i32(width), i32(height),
        nil,
        nil,
        window_class.instance,
        nil
    );

    if hwnd == auto_cast win32.INVALID_HANDLE {
        ok = false;
        return;
    }

    window.handle = hwnd;
    window.width  = width;
    window.height = height;
    ok = true;
    return;
}

delete_window :: proc(window: ^Window) {
    win32.destroy_window(window.handle);
}

show_window :: proc(using window: ^Window, should_show: bool) {
    show_flag := should_show ? win32.SW_SHOW : 0;
    win32.show_window(handle, auto_cast show_flag);
}

max_window :: proc(using window: ^Window) {
    win32.show_window(handle, 3);
    
    rect : win32.Rect;
    win32.get_client_rect(handle, &rect);

    width  = cast(int)(rect.right - rect.left);
    height = cast(int)(rect.bottom - rect.top);
}

swap_window_buffer :: proc(using window: ^Window) {
    window_context := win32.get_dc(handle);
    defer win32.release_dc(handle, window_context);
    win32.swap_buffers(window_context);
}

poll_events :: proc(using window: ^Window) {
    c := context;
    c.user_ptr = rawptr(window);

    win32.set_window_long_ptr_a(handle, win32.GWLP_USERDATA, win32.Long_Ptr(uintptr(&c)));

    msg : win32.Msg;
    for win32.peek_message_a(&msg, nil, 0, 0, win32.PM_REMOVE) {
        win32.translate_message(&msg);
        win32.dispatch_message_a(&msg);
    }
}

// TODO: Do this the proper way
exe_path :: proc() -> string {
    buffer  : [1024]u8;
    buf_len := win32.get_module_file_name_a(nil, auto_cast &buffer[0], 1024);

    path := cstring(&buffer[0]);
    return fmt.tprint(path);
}

PROCESS_DPI_AWARENESS :: enum {
    PROCESS_DPI_UNAWARE,
    PROCESS_SYSTEM_DPI_AWARE,
    PROCESS_PER_MONITOR_DPI_AWARE
}

MONITOR_DPI_TYPE :: enum {
    MDT_EFFECTIVE_DPI,
    MDT_ANGULAR_DPI,
    MDT_RAW_DPI,
    MDT_DEFAULT,
}

Set_Process_DPI_Awareness :: proc "c" (v: PROCESS_DPI_AWARENESS) -> win32.Hresult;
Get_DPI_For_Monitor :: proc "c" (m: win32.Hmonitor, t: MONITOR_DPI_TYPE, dpiX: ^u32, dpiY: ^u32) -> win32.Hresult;

// TODO: Redo this as a window proc
// @private
// sys_init :: proc() {
//     using dynlib;

//     shcore, found := load_library("shcore.dll");
//     if found {
//         defer unload_library(shcore);

//         func, ok := symbol_address(shcore, "SetProcessDpiAwareness");
//         SetProcessDpiAwareness := cast(Set_Process_DPI_Awareness)func;
//         if ok do SetProcessDpiAwareness(.PROCESS_SYSTEM_DPI_AWARE);

//         monitor := win32.monitor_from_window(nil, 1);
//         func, ok = symbol_address(shcore, "GetDpiForMonitor");
//         GetDpiForMonitor := cast(Get_DPI_For_Monitor)func;
//         if ok {
//             dpiX, dpiY : u32;
//             GetDpiForMonitor(monitor, .MDT_EFFECTIVE_DPI, &dpiX, &dpiY);
//             engine.dpi_scale = f32(dpiX) / 96.0;
//         }
//     } else {
//         engine.dpi_scale = 1;
//     }
// }

// Os's caret blink time in seconds
caret_blink_time :: proc() -> f32 {
    return f32(GetCaretBlinkTime()) / 1000.0;
}

@(default_calling_convention = "std")
foreign user32 {
    SetCapture :: proc(hWnd: win32.Hwnd) -> win32.Hwnd ---;
    ReleaseCapture :: proc() -> win32.Bool ---;
    GetCaretBlinkTime :: proc() -> u32 ---;
}