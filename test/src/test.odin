package test

import "newport:core"
import "newport:engine"
import "newport:graphics"
import "newport:asset"

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

    show_window(&the_engine.window, true);

    shader := asset.find(&graphics.shader_catalog, "basic2d");
    fmt.print(shader);

    for engine.is_running() {
        engine.dispatch_input();

        graphics.clear(Linear_Color{ 0.1, 0.1, 0.1, 1 });



        engine.display();
    }
}