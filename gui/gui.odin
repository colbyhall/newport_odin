package gui

import "core:reflect"
import "core:runtime"
import "core:fmt"

import "../core"
import "../draw"

Rect :: core.Rect;
Linear_Color :: core.Linear_Color;
Vector3 :: core.Vector3;
Vector2 :: core.Vector2;
v2 :: core.v2;
v3 :: core.v3;

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
    to_hash := fmt.tprint(loc);

    id : Id;
    id.whole = int(runtime.default_hash_string(to_hash));
    return id;
}

id :: proc{ id_any, id_any_index, id_int, id_loc };

id_equals :: proc(a, b: Id) -> bool { return a.whole == b.whole; }

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
    font      : draw.Font,
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

    mouse_pos  : Vector2,
    current_mb : [3]bool,    
    old_mb     : [3]bool,

    text_input     : [dynamic]rune,
    keys_went_down : [255]bool,
    keys_down      : [255]bool,

    frame : int,

    scale : f32,
}

@private the_gui : Gui;

begin :: proc(viewport: Rect) {
    using the_gui;

    focus_was_set = false;
}

end :: proc(dt: f32, viewport: Rect) {
    using the_gui;

    clear(&widgets);
    clear(&layouts);
    frame += 1;

    // TODO(colby): Destroy control state after a frame is missed
}

@(deferred_out=end)
scoped :: proc(dt: f32, viewport: Rect) -> (f32, Rect) {
    begin(viewport);
    return dt, viewport;
}

make_control :: proc(id: Id, $T: typeid) -> ^T {
    using the_gui;

    t := new(T);
    t.variant = t^;
    t.frame   = frame;

    controls[id.whole] = t;
    return t;
}

delete_control :: proc(id: Id) -> bool {
    using the_gui;

    c := controls[id.whole];
    if c == nil do return false;
    free(c);
    delete_key(&controls, id.whole);
    return true;
}

find_control :: proc(id: Id) -> ^Control {
    using the_gui;

    return controls[id.whole];
}

find_or_make_control :: proc(id: Id, $T: typeid) -> ^T {
    t := find_control(id);
    if t == nil do t = make_control(id, T);
    return &t.variant.(T);
}

set_focus :: proc(id: Id) {
    using the_gui;
    focused = id;
    focus_was_set = true;
}