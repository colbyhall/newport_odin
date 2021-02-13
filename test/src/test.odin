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

ray_plane_intersection :: proc(origin, dir: Vector3, p: Plane) -> (impact: Vector3, hit: bool) {
    pn := v3(p.x, p.y, p.z);
    pd := plane_dot(p, origin);

    if pd > 1e-6 {
        hit = dot(pn, dir) < 0;
        if hit do impact = origin + dir * pd;
        return;
    }

    hit = true;
    impact = origin + pn * -pd;

    return;
}

main :: proc() {
    // Setup the engine
    init_details := engine.default_init_details();
    engine.init_scoped(init_details);   

    context = engine.default_context();

    the_engine := engine.get();

    job.init_scoped();

    // Setup all the gpu stuff including the 
    device := gpu.init(&the_engine.window);
    defer gpu.shutdown();

    asset.discover();

    core.show_window(&the_engine.window, true);

    for engine.is_running() {
        engine.dispatch_input();
    }
}