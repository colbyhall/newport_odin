package gui

import "../draw"
import "../gpu"

Vertex_Type :: enum u32 {
    Solid_Color,
    Textured,
    Font,
}

Vertex :: struct {
    position  : Vector3,
    uv0, uv1  : Vector2,
    
    tex  : u32,
    type : Vertex_Type,
}

