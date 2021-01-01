package gui

import "core:reflect"

import "../core"

Rect :: core.Rect;
Linear_Color :: core.Linear_Color;

// Unique Id for an instance of widget control
// 
// 64 bit long with union for unique data
//
// @see id
// @see id_equals
Id :: struct #raw_union {
    using _ : struct {
        owner : i32,
        index : i32,
    },
    whole : int,
}

id_any :: proc(owner: any) -> Id {
    ptr, _ := reflect.any_data(owner);

    id : Id;
    id.whole = int(uintptr(ptr));
    return id;
}

id_any_index :: proc(owner: any, auto_cast index: int) -> Id {
    ptr, _ := reflect.any_data(owner);

    id : Id;
    id.owner = i32(uintptr(ptr));
    id.index = i32(index);
    return id;
}

id_int :: proc(auto_cast whole: int) -> Id {
    id : Id;
    id.whole = whole;
    return id;
}

id_loc :: proc(loc := #caller_location) -> Id {
    id : Id;
    id.whole = int(loc.hash);
    return id;
}

id :: proc{ id_any, id_any_index, id_int, id_loc };

id_equals :: inline proc(a, b: Id) -> bool { return a.whole == b.whole; }

nil_id :: Id{};

Widget_Type :: enum {
    Panel,
    Label,
    Text_Input,
}

Text_Alignment :: enum {
    Left,
    Center,
    Right,
}

// Per frame draw info
Widget :: struct {
    rect : Rect,
    id   : Id,
    clip : Rect,

    type : Widget_Type,

    label     : string,
    alignment : string,
    color     : Linear_Color,

    // Scaled to the UI scale
    // font : Font,
    padding   : Vector2,
    roundness : f32,
}

// Retained state created at use and removed after use is over
Control :: struct {
    frame   : int,
    variant : any,
}

Layout_Type :: enum {
    Left,
    Right,
    Up,
    Down,
}

// Layouts allow the programmer to not have to calculate the widget rects
// Using layouts you can easily do any type of list in any direction
//
// Can go in 4 directions
Layout :: struct {
    rect    : Rect,
    current : f32,
    type    : Layout_Type,
    id      : Id,
}

// All of the gui state
// 
// @note: Not thread safe
Gui :: struct {
    widgets  : [dynamic]Widget,
    controls : map[int]^Control,
    layouts  : [dynamic]Layout,

    hovered : Id,
    focused : Id,
    focus_was_set : bool,
    ignore_input  : bool,

    
}

@private gui : Gui;