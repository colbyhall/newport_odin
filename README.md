# Newport 
Newport is a modular game engine built in odin for odin. It is designed to be easily extendable and easy to use.

## Plans
* Vulkan Backend
* DX12 Backend
* Removal of OpenGL
* Serialization (JSON, Binary)
* Audio System
* Controller Input

## Features in Progress
* Custom ImGui
* General graphics api
* Custom renderers

## Features
* Modular setup for easy extension. Also allows for select parts to be used alone.
* Fiber Job System
* GL Rendering
* Asset Manager

## Setup
1. Clone the repo into a desired folder
```sh
$ git clone https://github.com/colbyhall/newport.git
```
2. Add the collection to your project build command
```sh
$ odin build example.odin -collection:newport=desired\
```
3. Import the collection into your project
```odin
package example

import "newport:core"
import "newport:engine"
import "newport:graphics"
import "newport:graphics/draw"
import "newport:asset"
import "newport:job"

import "core:fmt"

main :: proc() {
    init_details := engine.default_init_details("test");
    engine.init_scoped(init_details);

    context = engine.default_context();

    graphics.init(graphics.default_init_details());
    asset.discover();

    job.init_scoped();

    pipeline_details := graphics.default_pipeline_details();
    pipeline_details.shader = asset.find(&graphics.shader_catalog, "basic2d");
    pipeline_details.vertex = typeid_of(draw.Immediate_Vertex);
    pipeline_details.viewport = engine.viewport();

    pipeline_id := graphics.make_pipeline(pipeline_details);

    imm := draw.make_immediate_renderer();

    core.show_window(engine.get().window, true);

    for engine.is_running() {
        job := job.create(proc(job: ^Job) {
            x := 0;
            for i in 0..1000000 {
                x += i;
            }

            fmt.println(x);
        });

        counter : job.Counter;
        for _ in 0..<64 {
            job.schedule(job, &counter);
        }

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

        draw.rect(&imm, viewport, -5, core.green);

        draw.flush(&imm);

        engine.display();
        job.wait(counter = &counter, stay_on_thread = true);
    }
}
```