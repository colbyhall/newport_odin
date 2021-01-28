package gpu

import "../core"
import "../engine"
import "../asset"

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

// Shader Cache Section

import "core:strings"
import "core:os"
import "core:sys/win32"
import "core:time"

import "../deps/dxc"

Shader_Cache_Entry :: struct {
    path     : uintptr,
    path_len : int,

    contents : uintptr,
    contents_len : int,

    last_write_time : time.Time,

    next     : uintptr,
}

SHADER_CACHE_FILE_VERSION :: 2;

Shader_Cache_File :: struct {
    entries : uintptr,
    current : uintptr,
    version : int,
}

Shader_Cache :: struct {
    path_map : map[string]^Shader_Cache_Entry,
    should_save : bool,

    using file : ^Shader_Cache_File,
    
    arena : mem.Arena,
}

shader_cache : Shader_Cache;

SHADER_CACHE_PATH :: "cache/shaders.cache";

init_shader_cache :: proc() {
    if !os.exists("cache/") do os.make_directory("cache/", 0);

    read_entire_file_into_buffer :: proc(name: string, buffer: []u8) -> int {
        using os;

        fd, err := open(name, O_RDONLY, 0);
        if err != 0 {
            return 0;
        }
        defer close(fd);

        length: i64;
        if length, err = file_size(fd); err != 0 {
            return 0;
        }

        if length <= 0 {
            return 0;
        }

        data := buffer[:length];
        if data == nil {
            return 0;
        }

        bytes_read, read_err := read(fd, data);
        if read_err != ERROR_NONE {
            return 0;
        }

        return bytes_read;
    }

    using shader_cache;

    arena.data = make([]byte, mem.megabytes(512));
    arena.offset = read_entire_file_into_buffer(SHADER_CACHE_PATH, arena.data);
    file = cast(^Shader_Cache_File)&arena.data[0];

    cache := &shader_cache;

    if arena.offset == 0 || version != SHADER_CACHE_FILE_VERSION {
        arena.offset = size_of(Shader_Cache_File);
        should_save = true;
        file.version = SHADER_CACHE_FILE_VERSION;
        return;
    }

    num_cooked : int;
    current = entries;
    for {
        num_cooked += 1;
        cur := cast(^Shader_Cache_Entry)core.arena_ptr_from_offset(&arena, current);

        path := transmute(string)mem.Raw_String{ cast(^byte)core.arena_ptr_from_offset(&arena, cur.path), cur.path_len };
        path_map[path] = cur;

        if cur.next == 0 do break;
        current = cur.next;
    }

    log.infof("[GPU] Initialized shader cache with {} precompiled.", num_cooked);
}

find_in_shader_cache :: proc(using shader: ^Shader) -> (contents: []u8, found: bool) {
    using shader_cache;
    
    entry := path_map[path];
    if entry == nil do return;

    if entry.last_write_time._nsec != last_write_time._nsec {
        log.infof("[GPU] Shader \"{}\" is out of date", path);
        return;
    }

    found = true;

    contents = transmute([]u8)mem.Raw_Slice{ cast(^u8)core.arena_ptr_from_offset(&arena, entry.contents), entry.contents_len };
    return;
}

compile_into_shader_cache :: proc(source: []u8, using shader: ^Shader) -> (contents: []u8, success: bool) {
    using dxc;

    log.infof("[GPU] Compiling a {} shader at \"{}\" and saving in cache", type, path);

    // Setup the original COM objects
    utils: ^IDxcUtils;
    err := DxcCreateInstance(&CLSID_DxcUtils, &IDxcUtils_GUID, auto_cast &utils);
    assert(err == 0);
    defer utils->Release();

    compiler: ^IDxcCompiler3;
    err = DxcCreateInstance(&CLSID_DxcCompiler, &IDxcCompiler3_GUID, auto_cast &compiler);
    assert(err == 0);
    defer compiler->Release();

    // This creates a blob from our source memory location
    // TODO: Check if this is still needed with DxcBuffer
    source_blob : ^IDxcBlobEncoding;
    err = utils->CreateBlobFromPinned(&source[0], u32(len(source)), CP_UTF8, &source_blob);
    assert(err == 0);
    defer source_blob->Release();

    buffer : DxcBuffer;
    buffer.Ptr = source_blob->GetBufferPointer();
    buffer.Size = source_blob->GetBufferSize();
    buffer.Encoding = CP_UTF8;

    // Bild the arguments list
    arguments := make([dynamic]win32.Wstring, 0, 12);
    defer delete(arguments);
    {
        append(&arguments, win32.utf8_to_wstring("-E"));
        append(&arguments, win32.utf8_to_wstring("main"));
        append(&arguments, win32.utf8_to_wstring("-T"));
        switch type {
        case .Pixel: append(&arguments, win32.utf8_to_wstring("ps_6_6"));
        case .Vertex: append(&arguments, win32.utf8_to_wstring("vs_6_6"));
        }

        // For vulkan
        append(&arguments, win32.utf8_to_wstring("-spirv"));

        // O3 optimization
        append(&arguments, win32.utf8_to_wstring("-O3"));
    }

    // Compile the actual HLSL using our arguments
    // TODO: Include Handlers
    result : ^IDxcResult;
    err = compiler->Compile(&buffer, &arguments[0], u32(len(arguments)), nil, &IDxcResult_GUID, auto_cast &result);
    assert(err == 0);
    defer result->Release();

    // Do error handling if any
    errors : ^IDxcBlobEncoding;

    compile_err : HRESULT;
    err = result->GetStatus(&compile_err);
    assert(err == 0);

    err = result->GetErrorBuffer(&errors);
    assert(err == 0);
    if compile_err != 0 {
        defer errors->Release();

        error := cast(cstring)errors->GetBufferPointer();
        log.error("[DXC] Compilation Error\n", error);
        return;
    }
    
    success = true;

    // Retrieve the contents into a blob
    contents_blob : ^IDxcBlob;
    err = result->GetResult(&contents_blob);
    assert(err == 0);
    defer contents_blob->Release();

    using shader_cache;

    arena_allocator := core.thread_safe_arena_allocator(&arena);

    // Allocate the entry in the cache memory and update current
    entry := new(Shader_Cache_Entry, arena_allocator);
    entry_offset := core.arena_offset_from_ptr(&arena, entry);
    if entries == 0 do entries = entry_offset;
    if current != 0 {
        cur := cast(^Shader_Cache_Entry)core.arena_ptr_from_offset(&arena, current);
        cur.next = entry_offset;
    }
    current = entry_offset;

    // Create a copy of paths in our cache memory
    path_copy := strings.clone(path, arena_allocator);
    entry.path = core.arena_offset_from_ptr(&arena, &(transmute([]byte)path_copy)[0]); // This is gross
    entry.path_len = len(path_copy);

    // Allocate the contents in cache memory
    contents_len := int(contents_blob->GetBufferSize());
    contents = make([]u8, contents_len, arena_allocator);

    // Copy contents into cache memory and update entry
    mem.copy(&contents[0], contents_blob->GetBufferPointer(), contents_len);
    entry.contents = core.arena_offset_from_ptr(&arena, &contents[0]);
    entry.contents_len = contents_len;
    entry.last_write_time = last_write_time;

    should_save = true;

    path_map[path] = entry;

    return;
}

import "core:fmt"

shutdown_shader_cache :: proc() {
    cache := &shader_cache;
    using shader_cache;

    if arena.offset == 0 || !should_save do return;

    log.infof("[GPU] Saving shader cache. Cache is {} bytes", arena.offset);

    success := os.write_entire_file(SHADER_CACHE_PATH, arena.data[:arena.offset]);
    assert(success);
}

// Shader asset handling

import path_lib "core:path"

register_shader :: proc() {
    load :: proc(using shader: ^Shader) -> bool {
        ext := path_lib.ext(path)[1:];
        switch ext {
        case "hlps": type = .Pixel;
        case "hlvs": type = .Vertex;
        case: assert(false);
        }

        contents, found := find_in_shader_cache(shader);
        if !found {
            source, found := os.read_entire_file(path);
            if !found do return false;
            defer delete(source);

            success : bool;
            contents, success = compile_into_shader_cache(source, shader);
            if !success do return false;
        }

        init_shader(shader, contents);

        return true;
    }

    unload :: proc(using shader: ^Shader) -> bool {
        // INCOMPLETE
        return true;
    }

    @static extensions := [?]string{
        "hlps", // Pixel shader
        "hlvs", // Vertex shader
    };

    asset.register(Shader, extensions[:], auto_cast load, auto_cast unload);
}