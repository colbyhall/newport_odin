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

imm_glyph :: proc(imm: ^Immediate_Renderer, glyph: graphics.Font_Glyph, font: graphics.Font, xy: Vector2, z: f32, color: Linear_Color, loc := #caller_location) {
    xy := xy - v2(0, font.descent);
    x0 := xy.x + glyph.bearing_x;
    y1 := xy.y - glyph.bearing_y;
    x1 := x0 + glyph.width;
    y0 := y1 - glyph.height;

    rect := Rect{ v2(x0, y0), v2(x1, y1) };

    imm_rect(imm, rect, z, glyph.uv, Rect{}, color, loc);
}

glyph :: imm_glyph;

imm_rune :: proc(imm: ^Immediate_Renderer, r: rune, font: graphics.Font, xy: Vector2, z: f32, color: Linear_Color, loc := #caller_location) -> (graphics.Font_Glyph, bool) {
    glyph, ok := graphics.glyph_from_rune(font, r);
    if ok do imm_glyph(imm, glyph, font, xy, z, color, loc);
    return glyph, ok;
}

imm_string :: proc(imm: ^Immediate_Renderer, s: string, f: graphics.Font, xy: Vector2, z: f32, color: Linear_Color, max_width := 0.0, loc := #caller_location) {
    orig_xy := xy;

    xy := xy;

    space_g, _ := graphics.glyph_from_rune(f, ' ');
    for r in s {
        /*
        if max_width > 0 && xy.x + space_g.advance > orig_xy.x + max_width {
            xy.x = orig_xy.x;
            xy.y -= f.size;
        }
        */

        switch r {
        case '\n': 
            xy.x = orig_xy.x;
            xy.y -= f.size;
        case '\r':
            xy.x = orig_xy.x;
        case '\t':
            xy.x += space_g.advance * 4.0;
        case:
            g, ok := imm_rune(imm, r, f, xy, z, color, loc);
            if ok do xy.x += g.advance;
        }
    }
}

render_right_handed :: proc(viewport: Rect, near : f32 = 0.1, far : f32 = 1000.0) -> (proj: Matrix4, view: Matrix4) {
    using core;

    _, draw_size := rect_pos_size(viewport);
    aspect_ratio := draw_size.x / draw_size.y;
    ortho_size   := draw_size.y / 2;

    proj = ortho(ortho_size, aspect_ratio, near, far);
    view = translate(v3(-draw_size.x / 2.0, -ortho_size, 0));
    return;
}