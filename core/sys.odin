package core


// An OS Window
// 
// @see create_window
// @see delete_window
// @see show_window
// @see swap_window_buffer
Window :: struct {
    handle : Window_Handle,
    width  : int,
    height : int,

    dispatcher : Event_Dispatcher,
}

// Event for when the program is requested to exit
Exit_Request_Event :: struct {
    using base : Event,

    window : ^Window,
}

// Event for when a key is pressed or released. Used for key input
Key_Event :: struct {
    using base : Event,

    window  : ^Window,
    key     : u8,
    pressed : bool,
}

// Event for when a char is typed. Used for text input
Char_Event :: struct {
    using base : Event,

    window : ^Window,
    char   : rune,
}

// Event for when a mouse button is pressed or released
Mouse_Button_Event :: struct {
    using base : Event,
    
    window       : ^Window,
    mouse_button : u8,
    pressed      : bool,
}

// Event for when the mouse is moved
Mouse_Move_Event :: struct {
    using base : Event,

    window  : ^Window,
    mouse_x : int,
    mouse_y : int,
}

// Event for when mouse wheel is scrolled
Mouse_Wheel_Event :: struct {
    using base : Event,

    window : ^Window,
    delta  : i16,
}

// Event for when the window is resized
Window_Resize_Event :: struct {
    using base : Event,

    window     : ^Window,
    old_width  : int,
    old_height : int,
}