package draw

import ".."
import "../../core"

import "core:log"

Vector2 :: core.Vector2;
v2 :: core.v2;

Vector3 :: core.Vector3;
Vector4 :: core.Vector4;
Matrix4 :: core.Matrix4;
Rect    :: core.Rect;
Linear_Color :: core.Linear_Color;

Immediate_Vertex :: struct {
    position : Vector3,
    normal   : Vector2,
    uv0, uv1 : Vector2,
    color    : Linear_Color,
}

Immediate_Renderer :: struct {
    vertices : [dynamic]Immediate_Vertex,
    indices  : [dynamic]u32,

    buffer   : graphics.Vertex_Buffer(Immediate_Vertex),
}

make_immediate_renderer :: proc(cap := 1024 * 3, loc := #caller_location) -> Immediate_Renderer {
    graphics.check(loc);

    vertices := make([dynamic]Immediate_Vertex, 0, cap);
    indices  := make([dynamic]u32, 0, cap / 3);
    buffer   := graphics.make_vertex_buffer(Immediate_Vertex, true, loc);

    return Immediate_Renderer{ vertices, indices, buffer };
}

imm_begin :: proc(using imm: ^Immediate_Renderer) {
    clear(&vertices);
    clear(&indices);
}

begin :: imm_begin;

imm_flush :: proc(using imm: ^Immediate_Renderer, loc := #caller_location) {
    graphics.check(loc);

    gfx_state := graphics.get();

    if !graphics.is_pipeline_active() {
        log.errorf("[Draw] To flush an Immediate_Renderer a pipeline must be active. Called from {} at {}", loc.file_path, loc.line);
        assert(false);
    }

    graphics.upload_vertex_buffer(&buffer, vertices[:], indices[:], loc);
    graphics.draw_vertex_buffer(&buffer, loc);
}

flush :: imm_flush;

imm_textured_rect :: proc(using imm: ^Immediate_Renderer, rect: Rect, z: f32, uv0: Rect, uv1: Rect, color: Linear_Color, loc := #caller_location) {
    graphics.check(loc);

    base_index := u32(len(vertices));

    using core;

    bot_left := Immediate_Vertex{
        position = v3(rect.min, z),
        normal   = v2(-1, 0),
        uv0      = uv0.min,
        uv1      = uv1.min,
        color    = color,
    };
    append(&vertices, bot_left);

    top_left := Immediate_Vertex{
        position = v3(rect.min.x, rect.max.y, z),
        normal   = v2(0, 1),
        uv0      = v2(uv0.min.x, uv0.max.y),
        uv1      = v2(uv1.min.x, uv1.max.y),
        color    = color,
    };
    append(&vertices, top_left);

    top_right := Immediate_Vertex{
        position = v3(rect.max, z),
        normal   = v2(1, 0),
        uv0      = uv0.max,
        uv1      = uv1.max,
        color    = color,
    };
    append(&vertices, top_right);

    bot_right := Immediate_Vertex{
        position = v3(rect.max.x, rect.min.y, z),
        normal   = v2(0, -1),
        uv0      = v2(uv0.max.x, uv0.min.y),
        uv1      = v2(uv1.max.x, uv1.min.y),
        color    = color,
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

imm_solid_rect :: proc(using imm: ^Immediate_Renderer, rect: Rect, z: f32, color: Linear_Color, loc := #caller_location) {
    uv := Rect{ v2(-1), v2(-1) };
    imm_textured_rect(imm, rect, z, uv, uv, color, loc);
}

imm_rect :: proc{ imm_textured_rect, imm_solid_rect };

rect :: imm_rect;

render_right_handed :: proc(viewport: Rect, near : f32 = 0.1, far : f32 = 1000.0) -> (proj: Matrix4, view: Matrix4) {
    using core;

    _, draw_size := rect_pos_size(viewport);
    aspect_ratio := draw_size.x / draw_size.y;
    ortho_size   := draw_size.y / 2;

    proj = ortho(ortho_size, aspect_ratio, near, far);
    view = translate(v3(-draw_size.x / 2.0, -ortho_size, 0));
    return;
}