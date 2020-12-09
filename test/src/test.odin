package test

import "newport:core"
import "newport:engine"
import "newport:graphics"
import "newport:asset"

main :: proc() {
    using core;

    init_details := engine.default_init_details("test");
    engine.init_scoped(init_details);   

    context = engine.default_context();

    the_engine := engine.get();

    graphics.init(graphics.default_init_details());
    asset.discover();

    show_window(&the_engine.window, true);

    for engine.is_running() {
        engine.dispatch_input();

        graphics.clear(Linear_Color{ 0.1, 0.1, 0.1, 1 });

        engine.display();
    }
}