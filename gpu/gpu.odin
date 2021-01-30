package gpu

import "../core"
import "../engine"
import "../asset"

import "core:log"
import "core:reflect"
import "core:runtime"
import "core:mem"

USE_VULKAN :: true;

Vector2 :: core.Vector2;
Vector3 :: core.Vector3;
Vector4 :: core.Vector4;
Matrix4 :: core.Matrix4;
Rect    :: core.Rect;
Linear_Color :: core.Linear_Color;

v2 :: core.v2;
rect_pos_size :: core.rect_pos_size;

// All supported types of shaders
Shader_Type :: enum {
    Pixel,
    Vertex,
    // TODO(colby): Compute
}

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
// TODO(colby): Add more of these
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

// Pipelines describe how the graphics API will draw something.
//
// Each underlying API has a different way of doing pipelines. So we want to abstract it out
Graphics_Pipeline_Description :: struct {
    shaders : []^Shader,
    vertex : typeid,

    render_pass   : ^Render_Pass,
    subpass_index : int,

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

default_graphics_pipeline_description :: proc(render_pass: ^Render_Pass) -> Graphics_Pipeline_Description {
    return Graphics_Pipeline_Description{
        render_pass = render_pass,
        
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

Command_Allocator_Type :: enum {
    Graphics,
}

// Global graphics state which contains managers and other info about graphics
//
// @see Pipeline_Manager
Graphics :: struct {
    swapchain : Swapchain,
}

@private state : ^Graphics; // This is a ptr because the api may want to extend this in a child struct

check :: proc(loc := #caller_location) {
    if state == nil {
        log.errorf("[Graphics] Can't do graphics work if graphics is not initiallized. Call graphics.init before {} {}", loc.file_path, loc.line);
        assert(false);
    }
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

init :: proc() {
    assert(engine.get() != nil);
    
    init_vulkan();
    init_shader_cache();

    // Asset format registration
    register_shader();

    // init_shader_catalog();
    // init_texture_catalog();
    // init_font_collection_catalog();
}

shutdown :: proc() {
    shutdown_shader_cache();
}

@(deferred_out=shutdown)
init_scoped :: proc() {
    init();
}