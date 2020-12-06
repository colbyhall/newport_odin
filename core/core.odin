package core

import "core:reflect"
import "core:intrinsics"
import "core:mem"
import "core:log"
import "core:os"
import "core:runtime"
import "core:time"
import "core:fmt"

// Abstract event type to be derived
//
// @see Test_Event for an example of an event
Event :: struct {
    handled : bool,
    derived : any,
}

Test_Event :: struct {
    using base : Event,

    foo : int,
    bar : string,
}

// Procedure that processes an event
// 
// @param owner - Pointer to the owning object. its generally expected this will be casted when given as a listener
// @param event - Child of Event with custom data about that event
// @return Whether this procedure was "handled" or not
Event_Proc :: #type proc(owner: rawptr, event: ^Event) -> bool;

// Holds data about what is lisenting and how to process the event
Event_Listener :: struct {
    owner    : any,
    process  : Event_Proc,
    priority : int,
}

// Dispatches events to all its listeners
Event_Dispatcher :: struct {
    listeners : [dynamic]Event_Listener, // Ordered based off of listener priority
}

// Inserts a listener with the params provided sorted by priority descending
add_event_listener :: proc(using dis: ^Event_Dispatcher, owner: any, process: Event_Proc, priority := 0) {
    listener := Event_Listener { owner, process, priority };

    for it, i in listeners {
        if it.priority < priority do insert_at(&listeners, i, listener);
    }

    append(&listeners, listener);
}

// Removes a listener by its given owner
//
// @returns true if the listener was removed
remove_event_listener :: proc(using dis: ^Event_Dispatcher, owner: any) -> bool {
    owner, _ := reflect.any_data(owner);

    for it, i in listeners {
        it_owner, _ := reflect.any_data(it.owner);

        if it_owner == owner {
            ordered_remove(&listeners, i);
            return true;
        }
    }

    return false;
}

// Runs through all listeners and calls their event proc
dispatch_event :: proc(dispatcher: ^Event_Dispatcher, e: ^$T) {
    e.derived = e^;

    for it in dispatcher.listeners {
        data, _ := reflect.any_data(it.owner);

        // Use rawptr for process func for auto casting
        handled := it.process(data, e);
        if handled do e.handled = true;
    }
}

// Encompassing engine data structure that can be derived
Engine :: struct {
    dt    : f32,
    frame : int,
    fps   : int,

    // Context stuff
    frame_arena : mem.Arena,
    logger      : log.Logger,
    log_file    : os.Handle,

    window    : Window,
    dpi_scale : f32,

    project_name : string,
}

@private engine : ^Engine; // This is a ptr because the user may want to extend this

// @returns the engine ptr casted to type T
get_engine_casted :: proc($T: typeid) -> ^T {
    return cast(^T)engine;
}

// @returns the base engine ptr
get_engine_base :: proc() -> ^Engine {
    return engine;
}

get_engine :: proc{ get_engine_casted, get_engine_base };

default_context :: proc() -> runtime.Context {
    c := runtime.default_context();

    c.temp_allocator = mem.arena_allocator(&engine.frame_arena);

    return c;
}

// Core's initialization details
Init_Details :: struct {
    engine_type      : typeid,
    frame_arena_size : int,
    project_name     : string,
}

default_init_details :: proc(project_name := "game") -> Init_Details {
    return Init_Details{
        engine_type = typeid_of(Engine),
        frame_arena_size = mem.gigabytes(4),
        project_name = project_name,
    };
}

init :: proc(details: Init_Details) {
    engine = cast(^Engine)mem.alloc(reflect.size_of_typeid(details.engine_type));
    using engine;

    mem.init_arena(&frame_arena, make([]byte, details.frame_arena_size));

    sys_init();

    // Change directory to base project dir
    exe_path := exe_path();
    for i := len(exe_path) - 1; i > 0; i -= 1 {
        if exe_path[i] == '\\' || exe_path[i] == '/' {
            exe_path = exe_path[0:i];
            break;
        }
    }
    os.set_current_directory(exe_path);
    os.set_current_directory("..");

    terminal_logger := log.create_console_logger(opt = log.Options{ .Level });
        
    if !os.exists("logs") do os.make_directory("logs", 0);

    t := time.now();
    y, m, d := time.date(t);
    h, min, s := time.clock(t);
    
    file_string := fmt.tprintf("logs\\{}_%d_%02d_%02d_%02d_%02d_%02d.log", project_name, y, m, d, h, min, s);
    log_file, _ = os.open(file_string, os.O_WRONLY | os.O_CREATE); // TODO: Error handling

    file_logger := log.create_file_logger(h = log_file, opt = log.Options{ .Level } | log.Full_Timestamp_Opts);

    logger = log.create_multi_logger(terminal_logger, file_logger);
}

shutdown :: proc() {
    os.close(engine.log_file);
}

@(deferred_out=shutdown)
init_scoped :: proc(details: Init_Details) {
    init(details);
}