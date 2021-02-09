package test

import "newport:core"
import "newport:engine"
import "newport:asset"
import "newport:job"
import "newport:gpu"

import "core:encoding/json"
import "core:os"
import "core:fmt"

Vector3 :: core.Vector3;
v3 :: core.v3;
dot :: core.dot;
cross :: core.cross;
norm :: core.norm;
length :: core.length;

// ax + bx + dx = w
Plane :: core.Vector4;

plane_dot :: proc(a: Plane, b: Vector3) -> f32 {
    return a.x * b.x + a.y * b.y + a.z * b.z - a.w;
}

// ray_plane_intersection :: proc(origin, dir: Vector3, p: Plane) -> 

main :: proc() {
    // Setup the engine
    init_details := engine.default_init_details();
    engine.init_scoped(init_details);   

    context = engine.default_context();

    the_engine := engine.get();

    a := v3(10, 43, 5);
    b := v3(23, -123, 234);
    c := v3(234, 13, 23);

    ab := b - a;
    bc := c - b;

    d := norm(cross(ab, bc));
    w := dot(a, d);

    p := Plane{ d.x, d.y, d.z, w };
    fmt.println(p, plane_dot(p, d * w));

    // Setup all the gpu stuff including the 
    // device := gpu.init(&the_engine.window);
    // defer gpu.shutdown();

    // asset.discover();

    // core.show_window(&the_engine.window, true);

    // for engine.is_running() {
    //     engine.dispatch_input();
    // }
}