package test

import "newport:core"
import "newport:engine"
import "newport:graphics"
import "newport:graphics/draw"
import "newport:asset"
import "newport:job"

import "core:encoding/json"
import "core:os"
import "core:fmt"

main :: proc() {
    using core;

    init_details := engine.default_init_details("test");
    engine.init_scoped(init_details);   

    context = engine.default_context();

    the_engine := engine.get();

    graphics.init(graphics.default_init_details());
    asset.discover();

    job.init_scoped();

    show_window(&the_engine.window, true);

    pipeline_details := graphics.default_pipeline_details();
    pipeline_details.shader = asset.find(&graphics.shader_catalog, "basic2d");
    pipeline_details.vertex = typeid_of(draw.Immediate_Vertex);
    pipeline_details.viewport = engine.viewport();

    pipeline_id := graphics.make_pipeline(pipeline_details);

    imm := draw.make_immediate_renderer();

    counter : job.Counter;

    for _ in 0..<64 {
        j := job.create(proc(data: rawptr) {
            x := 0;
            for _ in 0..<1000000 {
                x += x * x;
            }

            fmt.println(x);
        });

        job.schedule(j, &counter);
    }

    job.wait(&counter);

    for engine.is_running() {
        engine.dispatch_input();

        viewport := engine.viewport();

        graphics.clear(Linear_Color{ 0.1, 0.1, 0.1, 1 });

        proj, view := draw.render_right_handed(viewport);

        uniforms := graphics.Uniform_Map{
            "projection" = proj,
            "view" = view,
        };

        graphics.set_pipeline(pipeline_id, uniforms);
        draw.begin(&imm);

        draw.rect(&imm, viewport, -5, core.white);

        draw.flush(&imm);

        engine.display();
    }
}