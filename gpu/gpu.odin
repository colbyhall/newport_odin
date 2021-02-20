package gpu

import "../core"
import "../asset"

import "core:log"
import "core:reflect"
import "core:runtime"
import "core:mem"

// This is the HAL for the GPU. Currently Vulkan is the only back end available. The design and architecture
//  was originally concepted after reading http://alextardif.com/RenderingAbstractionLayers.html
//
// WARNING: This package is still in a very early state. The API is currently super volatile. I would not 
//          recommend using this package if you don't plan on handling the unknown future changes. 
// 
// GOALS: 
//  - Abstraction layer should be as lightweight as possible. As many API layer specfic concepts should be 
//    hidden from the user
//
// - Abstraction layer should be as simple as possible. There will be code complexity that is unavoidable but 
//   they should be rare. If the user ends up spending too much time debugging just to get to the meat of 
//   their calls then we have failed
// 
// - Abstraction layer should be easy to maintain and add on. The hope is that the above points aid this goal
//
// NEEDS: 
//   - Ability to create multiple devices to allow multiple GPU work if desired
//   - Create, upload, and destroy resources (buffers, textures, shaders, pipelines, etc)
//   - Gather, submit, and wait on command work from various passes, in a multicore-compatible way
//   - Automatic device memory management

Supported_Back_End :: enum {
    Vulkan,
    // DirectX12,
}

BACK_END :: Supported_Back_End.Vulkan;

Vector2 :: core.Vector2;
Vector3 :: core.Vector3;
Vector4 :: core.Vector4;
Matrix4 :: core.Matrix4;
Rect    :: core.Rect;
Linear_Color :: core.Linear_Color;

v2 :: core.v2;
rect_pos_size :: core.rect_pos_size;

// Holds state on devices and api instances
//
// TODO: Handle multiple physical devices and logical devices
GPU_State :: struct {
    current : ^Device, // This will probably be changed to some map that allows the user to use multiple GPU's

    derived : any,
}

// Global gpu state that contains information about back end instances and devices
@private 
state : ^GPU_State; 

// Initializing the GPU api returns a Device ptr
// @see Device
init :: proc(window: ^core.Window) -> ^Device {
    result := init_vulkan(window);
    init_shader_cache();

    // Register assets
    register_shader();

    return result;
}

// Is required to be call if the shader cache is going to be updated. 
shutdown :: proc() {
    shutdown_shader_cache();
}

// Returns the GPU state ptr casted to T
get_casted :: proc($T: typeid) -> ^T {
    data, id := reflect.any_data(state.derived);
    if id != T do return nil;

    return cast(^T)data;
}

// Returns the GPU state ptr
get_base :: proc() -> ^GPU_State { 
    return state;
}

get :: proc{ get_base, get_casted };

// 
// Device API
////////////////////////////////////////////////////

// Type of memory allocations that buffers or textures can be allocated from
Memory_Type :: enum {
    Host_Visible, // Able to be uploaded to by mapping memory. Slower to access. Faster to write to
    Device_Local, // Able to be uploaded to by using commands. Faster to access. Slower to write to
}

// A Device represents all the data used to submit work, handling of resources, and communicating to the display
// Device :: struct { ... }

//
// Context API
////////////////////////////////////////////////////

// Context essentially function as command buffers. They're split up via type to help distinguish functionality
// Context :: struct { ... }

// Start recording a context
// begin :: proc(using ctx: ^Context)

// Stop recording a context
// end :: proc(using ctx: ^Context)

// Starts recording a context and stops at the end of scope
// @(deferred_out=end)
// record :: proc(using ctx: ^Context) -> ^Context

//
// Graphics Context API
////////////////////////////////////////////////////

// Capable of recording graphics and compute work. Child of Context
// Graphics_Context :: struct { ... }

// make_graphics_context :: proc(using device: ^Device) -> Graphics_Context
// delete_graphics_context :: proc(using ctx: ^Graphics_Context)

//
// Compute Context API
////////////////////////////////////////////////////

// Capable of recording async compute work. Child of Context
// Compute_Context :: struct { ... }

//
// Upload Context API
////////////////////////////////////////////////////

// Capable of recording copy work. Child of Context
// Upload_Context :: struct { ... }

//
// Buffer API
////////////////////////////////////////////////////

// TODO: Document
Buffer_Usage :: enum {
    Transfer_Src,
    Transfer_Dst,
    Vertex,
    Index,
    Constants,
}

// TODO: Document
Buffer_Description :: struct {
    usage  : bit_set[Buffer_Usage],
    memory : Memory_Type,
    size   : int,
}

// A Buffer represents linear arrays of data which are used for graphics or compute work
// Buffer :: struct { ... }

// Creates a buffer object on the given device. Buffer is defined from the given description
// make_buffer :: proc(using device: ^Device, desc: Buffer_Description) -> Buffer

// Destroys api specific buffer objects and resets struct memory
// delete_buffer :: proc(using buffer: ^Buffer)

//
// Render Pass API
////////////////////////////////////////////////////

Attachment :: struct {
    format: Format,
}

Render_Pass_Description :: struct {
    colors : []Attachment,
    depth  : Maybe(Attachment),
}

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
    // ^Texture2d,
}

Format :: enum {
    Undefined,

    RGB_U8,
    RGBA_U8,
    RGBA_U8_SRGB,
    
    RGBA_F16,

    BGR_U8_SRGB,
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

// Pipelines describe how the graphics API will "do" something. This "do" includes graphics and computing
//
// Each underlying API has a different way of doing pipelines. So we want to abstract it out
Pipeline_Description :: struct {
    shaders : []^Shader,

    vertex : typeid,
    render_pass   : ^Render_Pass,

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

make_pipeline_description_graphics :: proc(render_pass: ^Render_Pass, vertex: typeid, shaders: []^Shader) -> Pipeline_Description {
    return Pipeline_Description{
        render_pass = render_pass,

        vertex = vertex,
        shaders = shaders,
        
        draw_mode  = .Fill,
        line_width = 1.0,

        cull_mode  = { },

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

make_pipeline_description :: proc{ make_pipeline_description_graphics };

Command_Allocator_Type :: enum {
    Graphics,
}

Texture_Layout :: enum {
    Undefined,
    General,
    Color_Attachment,
    Depth_Attachment,
    Transfer_Src,
    Transfer_Dst,
    Shader_Read_Only,
    Present,
}


// Texture2d_Shared :: struct {
//     using asset : asset.Asset,

//     data_path : string,
//     srgb      : bool,
// }

// import "../deps/stb/stbi"
// import "core:os"

// register_texture2d :: proc() {
//     load :: proc(tex: ^Texture2d) -> bool {
//         ok := asset.load_from_json(tex);
//         if !ok do return false;

//         raw, found := os.read_entire_file(tex.data_path);
//         if !found do return false; // TODO: Cleanup data loaded from json
//         defer delete(raw);

//         width, height, depth : i32;
//         pixels := stbi.load_from_memory(&raw[0], i32(len(raw)), &width, &height, &depth, 0);
//         if pixels == nil do return false; // TODO: Cleanup data loaded from json

//         tex.pixels = mem.slice_ptr(pixels, (int)(width * height * depth));
//         tex.width  = int(width);
//         tex.height = int(height);
//         tex.depth  = int(depth);

//         // TODO: Loading the actual texture

//         return true;
//     }

//     unload :: proc(using tex: ^Texture2d) -> bool {
//         // INCOMPLETE
//         return true;
//     }

//     @static extensions := []string{
//         "tex2d",
//         "texture2d",
//         "t2d",
//     };

//     asset.register(Texture2d, extensions, auto_cast load, auto_cast unload);
// }