package test

import "newport:core"
import "newport:engine"
import "newport:graphics/gl"

main :: proc() {
    using core;
    using gl;
    using extensions;

    init_details := engine.default_init_details("test");
    engine.init_scoped(init_details);   

    context = engine.default_context();

    the_engine := engine.get();

    show_window(&the_engine.window, true);

    for engine.is_running() {
        poll_events(&the_engine.window);

        glClearColor(0.1, 0.1, 0.1, 1);
        glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);

        swap_window_buffer(&the_engine.window);
    }
}