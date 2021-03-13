package gui

import "../core"
import "../draw"
import "../gpu"

Vertex_Type :: enum u32 {
    Solid_Color,
    Textured,
    Font,
}

Vertex :: struct {
    position  : Vector3,
    
    color     : Linear_Color,

    uv        : Vector2,
    tex       : u32,

    type      : Vertex_Type,
}

Builder :: struct {
    vertices : [dynamic]Vertex,
    indices  : [dynamic]u32,
}

make_builder_none :: proc(allocator := context.allocator) -> Builder {
    return Builder{
        vertices = make([dynamic]Vertex, allocator),
        indices  = make([dynamic]u32, allocator),
    };
}

make_builder_cap :: proc(cap: int, allocator := context.allocator) -> Builder {
    return Builder{
        vertices = make([dynamic]Vertex, 0, cap, allocator),
        indices  = make([dynamic]u32, 0, cap, allocator),
    };
}

destroy_builder :: proc(using b: ^Builder) {
    delete(vertices);
    clear(&vertices);

    delete(indices);
    clear(&indices);
}

reset_builder :: proc(using b: ^Builder) {
    clear(&vertices);
    clear(&indices);
}

builder_len :: proc(b: Builder) -> int {
    return len(b.vertices);
}

@private
push_raw_rect :: proc(using b: ^Builder, rect: Rect, z: f32, texture: ^gpu.Texture, uv: Rect, color: Linear_Color, type: Vertex_Type) {
    base_index := u32(len(vertices));

    // tex = ???? TODO
    tex : u32 = 0;

    bot_left := Vertex{
        position = v3(rect.min, z),
        
        color    = color,

        uv       = uv.min,
        tex      = tex,

        type     = type,
    };
    append(&vertices, bot_left);

    top_left := Vertex{
        position = v3(rect.min.x, rect.max.y, z),
        
        color    = color,

        uv       = v2(uv.min.x, uv.max.y),
        tex      = tex,

        type     = type,
    };
    append(&vertices, top_left);

    top_right := Vertex{
        position = v3(rect.max, z),
        
        color    = color,

        uv       = uv.max,
        tex      = tex,

        type     = type,
    };
    append(&vertices, top_right);

    bot_right := Vertex{
        position = v3(rect.max.x, rect.min.y, z),

        color    = color,

        uv       = v2(uv.max.x, uv.min.y),
        tex      = tex,

        type     = type,
    };
    append(&vertices, bot_right);

    // First triangle
    append(&indices, base_index);
    append(&indices, base_index + 2);
    append(&indices, base_index + 1);

    // Second triangle
    append(&indices, base_index);
    append(&indices, base_index + 3);
    append(&indices, base_index + 2);
}

push_textured_rect :: proc(using b: ^Builder, rect: Rect, z: f32, texture: ^gpu.Texture, uv: Rect, color: Linear_Color) {
    push_raw_rect(b, rect, z, texture, uv, color, .Textured);
}

push_texture_rect_simple :: proc(using b: ^Builder, rect: Rect, z: f32, texture: ^gpu.Texture, color := core.white) {
    uv := Rect{ v2(0), v2(1) };
    push_raw_rect(b, rect, z, texture, uv, color, .Textured);
}

push_solid_rect :: proc(using b: ^Builder, rect: Rect, z: f32, color: Linear_Color) {
    uv := Rect{ v2(-1), v2(-1) };
    push_raw_rect(b, rect, z, nil, uv, color, .Solid_Color);
}

push_rect :: proc{ push_textured_rect };

builder_to_buffers :: proc(device: ^gpu.Device, b: ^Builder) -> (vertex, index: ^gpu.Buffer) {
    assert(builder_len(b^) > 0);

    vertex_desc := gpu.Buffer_Description{
        usage  = { .Vertex },
        memory = .Host_Visible,
        size   = size_of(Vertex) * len(b.vertices),
    };

    index_desc := gpu.Buffer_Description{
        usage  = { .Index },
        memory = .Host_Visible,
        size   = size_of(u32) * len(b.vertices),
    };

    vertex = gpu.make_buffer(device, vertex_desc);
    index  = gpu.make_buffer(device, index_desc);
    return;
}
