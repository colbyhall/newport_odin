package job

import "core:thread"
import "core:sync"
import "core:container"
import "core:log"
import "core:time"
import "core:os"

import "../core"

Queue :: container.Queue;

Job_Proc :: #type proc(data: rawptr);

Job :: struct {
    procedure : Job_Proc,
    data      : rawptr,
}

Job_System :: struct {
    threads : []^thread.Thread,

    high_priority   : Queue(Job),
    normal_priority : Queue(Job),
    low_priority    : Queue(Job),

    fibers           : []^Fiber,
    active_fibers    : []bool,

    is_shutdown : bool,
}

@private system: Job_System;

init :: proc() {
    using system;

    core_count := core.logical_core_count();

    // Apparently core 0 is used for interupts
    // @TODO: Disable this for non debug cooked builds
    when ODIN_OS == "windows" {
        core_count -= 1;
    }

    threads = make([]^thread.Thread, core_count);

    // Setup the main thread as its unique
    threads[0] = core.current_thread();
    main_thread := threads[0];

    core.set_affinity(main_thread, 0);

    NUM_FIBERS :: 256;

    fibers = make([]^Fiber, NUM_FIBERS);
    active_fibers = make([]bool, NUM_FIBERS);

    fiber_proc :: proc(fiber: ^Fiber) {
        wait_for_work();
    }

    for i in core_count..<len(fibers) {
        fiber := make_fiber(fiber_proc);
        fibers[i] = fiber;
    }

    thread_proc :: proc(thread: ^thread.Thread) {
        index := thread_index();
        fibers[index] = fiber_from_current();

        wait_for_work();
    }

    for i in 1..<len(threads) {
        thread := thread.create_and_start(thread_proc, context);
        core.set_affinity(thread, i);
        threads[i] = thread;
    }
}

shutdown :: proc() {

}

@private
find_fiber :: proc() -> ^Fiber {
    for {
        for fiber, i in system.fibers {
            if sync.atomic_load(&system.active_fibers[i], .Relaxed) do continue;

            if _, ok := sync.atomic_compare_exchange_weak(&system.active_fibers[i], false, true, .Release, .Relaxed); ok {
                return fiber;
            }
        }
    }

    return nil;
}

@private
find_next :: proc() -> (job: Job, ok: bool) {
    return;
}

try_work :: proc() -> bool {
    if job, ok := find_next(); ok {
        job.procedure(job.data);
        return true;
    }
    return false;
}

wait_for_work :: proc() {
    for sync.atomic_load(&system.is_shutdown, .Relaxed) {
        if !try_work() do time.sleep(1);
    }
}

@(deferred_out=shutdown)
init_scoped :: proc() {
    init();
}

thread_index :: proc() -> int {
    id := os.current_thread_id();

    for thread, i in system.threads {
        if id == core.thread_id(thread) do return i;
    }

    return -1;
}

