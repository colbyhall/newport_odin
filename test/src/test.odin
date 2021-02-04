package test

import "newport:core"
import "newport:engine"
import "newport:asset"
import "newport:job"
import "newport:gpu"

import "core:encoding/json"
import "core:os"
import "core:fmt"

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