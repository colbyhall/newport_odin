package engine

import "core:reflect"
import "core:intrinsics"
import "core:mem"
import "core:log"
import "core:os"
import "core:runtime"
import "core:time"
import "core:fmt"

import "../core"

// Encompassing engine data structure that can be derived
Engine :: struct {
    dt    : f32,
    frame : int,
    fps   : int,

    // Context stuff
    logger      : log.Logger,
    log_file    : os.Handle,

    window        : core.Window,
    wants_to_quit : bool,

    project_name : string,
}

@private the_engine : ^Engine; // This is a ptr because the user may want to extend this

// @returns the engine ptr casted to type T
get_casted :: proc($T: typeid) -> ^T {
    return cast(^T)the_engine;
}

// @returns the base engine ptr
get_base :: proc() -> ^Engine {
    return the_engine;
}

get :: proc{ get_casted, get_base };

default_context :: proc() -> runtime.Context {
    c := runtime.default_context();

    c.logger = the_engine.logger;

    return c;
}

// Core's initialization details
Init_Details :: struct {
    engine_type      : typeid,
    project_name     : string,
}

default_init_details :: proc(project_name := "game") -> Init_Details {
    return Init_Details{
        engine_type = typeid_of(Engine),
        project_name = project_name,
    };
}

INPUT_PRIORITY :: 100;

window_input :: proc(owner: rawptr, event: ^core.Event) -> bool {
    using core;

    switch event in event.derived {
    case Exit_Request_Event:
        the_engine.wants_to_quit = true;
        return true;
    }

    return false;
}

init :: proc(details: Init_Details) {
    the_engine = cast(^Engine)mem.alloc(reflect.size_of_typeid(details.engine_type));
    using the_engine;

    project_name = details.project_name;

    // TODO: Should this be moved to the user code? This is making a decision about code structure 
    // Change directory to base project dir
    exe_path := core.exe_path();
    for i := len(exe_path) - 1; i > 0; i -= 1 {
        if exe_path[i] == '\\' || exe_path[i] == '/' {
            exe_path = exe_path[0:i];
            break;
        }
    }
    os.set_current_directory(exe_path);
    os.set_current_directory("..");

    terminal_logger := log.create_console_logger(opt = log.Options{ .Level });
        
    // Create a logs directory if we do not have one
    if !os.exists("logs") do os.make_directory("logs", 0);

    t := time.now();
    y, m, d := time.date(t);
    h, min, s := time.clock(t);
    
    // Create a file logger with a unique file name
    file_string := fmt.tprintf("logs\\{}_%d_%02d_%02d_%02d_%02d_%02d.log", project_name, y, m, d, h, min, s);
    log_file, _ = os.open(file_string, os.O_WRONLY | os.O_CREATE); // TODO: Error handling
    file_logger := log.create_file_logger(h = log_file, opt = log.Options{ .Level } | log.Full_Timestamp_Opts);

    // This logger will also be extendable after this procedure is complete
    logger = log.create_multi_logger(terminal_logger, file_logger);

    context = default_context();

    window_failed := false;
    window, window_failed = core.make_window(details.project_name, 1280, 720);

    if !window_failed do fmt.assertf(false, "[Engine] Failed to create game window");

    core.add_event_listener(dispatcher(), the_engine^, window_input, INPUT_PRIORITY);
}

shutdown :: proc() {
    os.close(the_engine.log_file);
}

@(deferred_out=shutdown)
init_scoped :: proc(details: Init_Details) {
    init(details);
}

dispatcher :: proc() -> ^core.Event_Dispatcher {
    return &the_engine.window.dispatcher;
}

is_running :: proc() -> bool {
    return !the_engine.wants_to_quit;
}

dispatch_input :: proc() {
    core.poll_events(&the_engine.window);
}

viewport :: proc() -> core.Rect {
    using core;

    window := the_engine.window;
    return Rect{ v2(0), v2(window.width, window.height) };
}