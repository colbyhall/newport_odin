package core

import "core:math"
import la "core:math/linalg"

TAU :: math.TAU;
PI  :: math.PI;

TO_RAD :: PI / 180;
TO_DEF :: 180 / PI;

acos  :: math.acos;
cos   :: math.cos;
sin   :: math.sin;
sqrt  :: math.sqrt;
round :: math.round;
atan2 :: math.atan2;
lerp  :: math.lerp;

length_sq    :: la.length2;
length       :: la.length;
norm         :: la.normalize;
dot          :: la.dot;
cross        :: la.vector_cross;

Vector2 :: la.Vector2;

v2xy :: inline proc(x, y: f32) -> Vector2 {
    return Vector2 { x, y };
}

v2s :: inline proc(xy: f32) -> Vector2 {
    return v2xy(xy, xy);
}

v2z :: inline proc() -> Vector2 {
    return v2s(0);
}

v2xyi :: inline proc(auto_cast x, y: int) -> Vector2 {
    return v2xy(f32(x), f32(y));
}

v2 :: proc { v2xy, v2s, v2z, v2xyi };

Vector3 :: la.Vector3;

v3xyz :: inline proc(x, y, z: f32) -> Vector3 {
    return Vector3 { x, y, z };
}

v3s :: inline proc(xyz: f32) -> Vector3 {
    return v3xyz(xyz, xyz, xyz);
}

v3z :: inline proc() -> Vector3 {
    return v3s(0.0);
}

v3xy_z :: inline proc(xy: Vector2, z: f32) -> Vector3 {
    return v3xyz(xy.x, xy.y, z);
}

v3 :: proc { v3xyz, v3s, v3z, v3xy_z };

Vector4 :: la.Vector4;

v4xyzw :: inline proc(x, y, z, w: f32) -> Vector4 {
    return Vector4{ x, y, z, w };
}

v4 :: proc { v4s, v4xyzw };

Matrix4 :: la.Matrix4;

m4_ortho :: proc(size, aspect_ratio, near, far: f32, flip_z_axis := true) -> Matrix4 {
    right := size * aspect_ratio;
    left  := -right;
    
    top   := size;
    bot   := -top;

    return la.matrix_ortho3d(left, right, bot, top, near, far, flip_z_axis);
}

ortho        :: proc { la.matrix_ortho3d, m4_ortho };
persp        :: la.matrix4_perspective;
transpose    :: la.transpose;
translate    :: la.matrix4_translate;
scale        :: la.matrix4_scale;
inverse      :: la.matrix4_inverse;
quat_to_mat4 :: la.matrix4_from_quaternion;
mul          :: la.mul;

Quaternion   :: la.Quaternion;

slerp        :: la.quaternion_slerp;
angle_axis   :: la.quaternion_angle_axis;
identity     :: la.identity;

Rect :: struct {
    min, max : Vector2,
}

rect_pos_size :: inline proc(using rect: Rect) -> (pos: Vector2, size: Vector2) {
    size = v2(max.x - min.x, max.y - min.y);
    pos  = min + size / 2;
    return;
}

rect_overlaps_point :: proc(a: Rect, b: Vector2) -> bool {
    return !(b.x < a.min.x || b.x > a.max.x || b.y < a.min.y || b.y > a.max.y);
}

rect_from_two_points :: proc(a, b: Vector2) -> Rect {
    min := a;
    max := b;

    if min.x > max.x {
        min.x = b.x;
        max.x = a.x;
    }

    if min.y > max.y {
        min.y = b.y;
        max.y = a.y;
    }

    return Rect{ min, max };
}

rect_overlaps_rect :: proc(a, b: Rect) -> (overlap: Rect, ok: bool) {
    min_x := a.min.x; 
    if a.min.x < b.min.x do min_x = b.min.x;

    min_y := a.min.y;
    if a.min.y < b.min.y do min_y =  b.min.y;

    max_x := a.max.x;
    if a.max.x > b.max.x do max_x = b.max.x;

    max_y := a.max.y;
    if a.max.y > b.max.y do max_y = b.max.y;

    overlap.min = v2(min_x, min_y);
    overlap.max = v2(max_x, max_y);

    ok = !(b.min.x > a.max.x || b.max.x < a.min.x || b.max.y < a.min.y || b.min.y > a.max.y);
    return;
}

Linear_Color :: struct {
    r, g, b, a : f32,
}

rgb :: proc(c: u32, a: f32 = 1.0) -> Linear_Color {
    r := (c & 0x00FF0000) >> 16;
    g := (c & 0x0000FF00) >> 8;
    b := c & 0x000000FF;

    return Linear_Color{ f32(r) / 0xFF, f32(g) / 0xFF, f32(b) / 0xFF, a };
}

rgba :: proc(c: u32) -> Linear_Color {
    r := (c & 0xFF000000) >> 24;
    g := (c & 0x00FF0000) >> 16;
    b := (c & 0x0000FF00) >> 8;
    a := c & 0x000000FF;

    return Linear_Color{ f32(r) / 0xFF, f32(g) / 0xFF, f32(b) / 0xFF, f32(a) / 0xFF };
}

// TODO: Do more colors
white :: Linear_Color{ 1, 1, 1, 1 };
black :: Linear_Color{ 0, 0, 0, 1 };
red   :: Linear_Color{ 1, 0, 0, 1 };
blue  :: Linear_Color{ 0, 1, 0, 1 };
green :: Linear_Color{ 0, 0, 1, 1 };