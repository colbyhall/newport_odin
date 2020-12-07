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