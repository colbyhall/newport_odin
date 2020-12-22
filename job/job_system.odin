package job

import "core:thread"
import "core:sync"
import "core:container"

Job :: struct {

}

Job_System :: struct {
    threads : []^thread.Thread,

    high_priority   : container.Queue(Job),
    normal_priority : container.Queue(Job),
    low_priority    : container.Queue(Job),

    fibers           : []^Fiber
    available_fibers : []bool,
}

@private system: Job_System;

init :: proc() {
    thread_proc :: proc(thread: ^Thread) {
        
    }
}

shutdown :: proc() {

}

