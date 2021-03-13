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

reset_builder :: proc(b: ^Builder) {
    clear(&vertices);
    clear(&indices);
}

builder_len :: proc(b: Builder) -> int {
    return len(b.vertices);
}

@builder
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

    vertex = make_buffer(device, vertex_desc);
    index  = make_buffer(device, index_desc);
    return;
}

Draw :: struct {
    pipeline : ^gpu.Pipeline,
    vertex_shader, pixel_shader : ^gpu.Shader,
}

@private
draw: ^Draw;

init_draw :: proc(device: ^gpu.Device) {
    vertex_shader_source := "
        Texture2D    all_textures[] : register(t0);
        SamplerState all_samplers[] : register(s1);

        struct Vertex {
            float3 position : POSITION;
            float4 color    : COLOR;
            
            float2 uv       : TEXCOORD0;
            uint   tex;

            uint   type;
        };

        struct Vertex_Output {
            float2 uv   : TEXCOORD0;
            float4 color    : COLOR;

            uint tex;
            uint type;

            float4 position : SV_Position;
        };

        struct Constants {
            float4x4 render;
        };
        [[vk::push_constant]] ConstantBuffer<Constants> constants;

        Vertex_Output main( Vertex IN ) {
            Vertex_Output OUT;

            OUT.position = mul(constants.render, float4(IN.position.xyz, 1.0));
            
            OUT.color = IN.color;
            OUT.uv    = IN.uv;
            OUT.tex   = IN.tex;
            OUT.type  = IN.type;

            return OUT;
        }
    ";

    pixel_shader_source := "
        Texture2D    all_textures[] : register(t0);
        SamplerState all_samplers[] : register(s1);

        #define VT_SOLID_COLOR 1
        #define VT_TEXTURED 1
        #define VT_FONT 1

        struct Pixel_Input {
            float2 uv   : TEXCOORD0;
            float4 color: COLOR;

            uint tex;
            uint type;
        };

        struct Constants {
            float4x4 render;
        };
        [[vk::push_constant]] ConstantBuffer<Constants> constants;

        float4 main( Pixel_Input IN ) : SV_TARGET {
            Texture2D    my_texture = all_textures[IN.tex];
            SamplerState my_sampler = all_samplers[IN.tex];

            float color = float4(1, 0, 1, 1);

            if (IN.type == VT_SOLID_COLOR) {
                color = IN.color;
            } else if (VT_TEXTURED) {
                color = my_texture.Sample(my_sampler, IN.uv, 0);
            } else if (VT_FONT) {
                // TODO
            }

            return color;
        }
    ";

    draw = new(Draw);

    using draw;

    vertex_shader = gpu.make_shader_from_string(device, vertex_shader_source, .Vertex);
    pixel_shader = gpu.make_shader_from_string(device, pixel_shader_source, .Pixel);
    assert(vertex_shader != nil && pixel_shader != nil);

    shaders := []^gpu.Shader{ vertex_shader, pixel_shader};

    pipeline_desc := gpu.Pipeline_Description{
        shaders = shaders,

        vertex  = type
    };
}


