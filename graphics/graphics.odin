package graphics

import "../core"

import "core:log"
import "core:reflect"
import "core:runtime"
import "core:mem"

Vector2 :: core.Vector2;
Vector3 :: core.Vector3;
Vector4 :: core.Vector4;
Matrix4 :: core.Matrix4;
Rect    :: core.Rect;
Linear_Color :: core.Linear_Color;

// All supported types that can be a vertex attribute
Vertex_Attributes :: union {
    i32,
    f32,
    Vector2,
    Vector3,
    Vector4,
    Linear_Color,
}

// All supported types that can be a uniform
Uniforms :: union {
    i32,
    f32,
    Vector2,
    Vector3,
    Vector4,
    Matrix4,
    Linear_Color,
    ^Texture2d,
}

// All supported texture formats
Texture_Format :: enum {
    RGB8,
    RGBA8,
    RGBAF16,
}

// All supported texture wraps
// 
// @TODO(colby): Add more of these
Texture_Wrap :: enum {
    Clamp,
    Repeat,
}

// All supported texture filtering
Texture_Filtering :: enum {
    Nearest, // Also known as point sampling
    Linear,
}

Framebuffer_Flags :: enum {
    Position,
    Normal,
    Albedo,
    Depth,
    HDR,
}

Framebuffer_Colors_Index :: enum {
    Position,
    Normal,
    Albedo,
    Count,
    HDR = 0,
}

Draw_Mode :: enum {
    Fill,
    Line,
    Point,
}

Cull_Mode :: enum {
    Front,
    Back,
}

Compare_Op :: enum {
    Never,
    Less,             // A < B
    Equal,            // A == B
    Less_Or_Equal,    // A < B || A == B
    Greater,          // A > B
    Not_Equal,        // A != B
    Greater_Or_Equal, // A > B || A == B
    Always,
}

Blend_Op :: enum {
    Add,
    Subtract,
    Reverse_Subtract,
    Min,
    Max,
}

Blend_Factor :: enum {
    Zero,
    One,

    Src_Color,
    One_Minus_Src_Color,
    Dst_Color,
    One_Minus_Dst_Color,

    Src_Alpha,
    One_Minus_Src_Alpha,
}

Color_Mask :: enum {
    Red,
    Green,
    Blue,
    Alpha,
}

Uniform_Map :: map[string]Uniforms;

// Pipelines describe how the graphics API will draw something.
//
// Each underlying API has a different way of doing pipelines. So we want to abstract it out
Pipeline_Details :: struct {
    shader : ^Shader,
    vertex : typeid,

    viewport : Rect,
    scissor  : Rect,

    draw_mode  : Draw_Mode,
    line_width : f32,

    cull_mode : bit_set[Cull_Mode],

    color_mask : bit_set[Color_Mask],

    blend_enabled : bool,

    src_color_blend_factor : Blend_Factor,
    dst_color_blend_factor : Blend_Factor,
    color_blend_op         : Blend_Op,

    src_alpha_blend_factor : Blend_Factor,
    dst_alpha_blend_factor : Blend_Factor,
    alpha_blend_op         : Blend_Op,    

    depth_test    : bool,
    depth_write   : bool,
    depth_compare : Compare_Op,
}

default_pipeline_details :: proc() -> Pipeline_Details {
    return Pipeline_Details{
        draw_mode  = .Fill,
        line_width = 1.0,

        cull_mode  = { .Back },

        color_mask = { .Red, .Green, .Blue, .Alpha },

        blend_enabled = false,

        src_color_blend_factor = .One,
        dst_color_blend_factor = .One,
        color_blend_op = .Add,

        src_alpha_blend_factor = .One_Minus_Src_Alpha,
        dst_alpha_blend_factor = .One,
        alpha_blend_op = .Add,

        depth_test    = true,
        depth_write   = true,
        depth_compare = .Less,
    };
}

Pipeline_Id :: int;

Pipeline_Manager :: struct {
    pipelines : map[Pipeline_Id]Pipeline,

    last_id : Pipeline_Id,
    active  : Pipeline_Id,  
}

@private
_add_pipeline :: proc(pipeline: Pipeline, loc := #caller_location) -> Pipeline_Id {
    check(loc);
    using state;

    pipeline_manager.last_id += 1;
    pipeline_manager.pipelines[pipeline_manager.last_id] = pipeline;

    return pipeline_manager.last_id;
}

@private
_remove_pipeline :: proc(id: Pipeline_Id, loc := #caller_location) -> (Pipeline, bool) {
    check(loc);
    using state;

    if id == 0 do return Pipeline{}, false;

    elem, found := pipeline_manager.pipelines[id];
    if !found do return Pipeline{}, false;

    delete_key(&pipeline_manager.pipelines, id);

    return elem, true;
}

set_pipeline :: proc(id: Pipeline_Id, uniforms: Uniform_Map, loc := #caller_location) {
    state.pipeline_manager.active = id;
    begin_pipeline(id, uniforms, loc);
}

@(deferred_out=end_pipeline)
pipeline_scoped :: proc(id: Pipeline_Id, uniforms: Uniform_Map, loc := #caller_location) -> runtime.Source_Code_Location {
    begin_pipeline(id, uniforms, loc);
    return loc;
}

// Global graphics state which contains managers and other info about graphics
//
// @see Pipeline_Manager
Graphics :: struct {
    pipeline_manager : Pipeline_Manager,
}

@private state : ^Graphics; // This is a ptr because the user may want to extend this in a child struct

check :: proc(loc := #caller_location) {
    if state == nil {
        log.errorf("[Graphics] Can't do graphics work if graphics is not initiallized. Call graphics.init before {} {}", loc.file_path, loc.line);
        assert(false);
    }
}

is_pipeline_active :: proc(id : Pipeline_Id = 0, loc := #caller_location) -> bool {
    check(loc);

    if id == 0 do return state.pipeline_manager.active != 0;
    return state.pipeline_manager.active == id;
}

// @returns the graphics ptr casted to type T
get_casted :: proc($T: typeid) -> ^T {
    return cast(^T)state;
}

// @returns the base graphics ptr
get_base :: proc() -> ^Graphics {
    return state;
}

get :: proc{ get_casted, get_base };

Init_Details :: struct {
    graphics_type : typeid,
}

default_init_details :: proc() -> Init_Details {
    return Init_Details{
        graphics_type = typeid_of(Graphics),
    };
}

init :: proc(details: Init_Details) {
    state = cast(^Graphics)mem.alloc(reflect.size_of_typeid(details.graphics_type));

    init_shader_catalog();
    init_texture_catalog();
}