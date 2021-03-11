package draw

import "../core"

Vector2 :: core.Vector2;
v2 :: core.v2;

Rect :: core.Rect;

Bitmap :: struct(T: typeid) {
    pixels : []T,
    
    width  : int,
    height : int,
    depth  : int,
}

index_bitmap :: proc(using it: Bitmap($T), auto_cast x: int, auto_cast y: int, auto_cast z: int = 0) -> ^T {
    assert(x >= 0 && x < width && y >= 0 && y < height && z >= 0 && z < depth);

    return &pixels[x + y * width + z * width * height];
}

make_bitmap :: proc($T: typeid, auto_cast width: int, auto_cast height: int, auto_cast depth: int = 1, allocator := context.allocator) -> Bitmap(T) {
    pixels := make([]T, width * height * depth, allocator);
    return Bitmap(T){
        pixels = pixels,
        width  = width,
        height = height,
        depth  = depth,
    };
}

delete_bitmap :: proc(using it: Bitmap($T)) {
    delete(pixels);
}