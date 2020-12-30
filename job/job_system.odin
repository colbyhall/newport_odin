package job

import "core:thread"
import "core:sync"
import "core:log"
import "core:time"
import "core:os"

// FOR DEBUG ONLY
import "core:fmt"

import "../core"

Job_Proc :: #type proc(data: rawptr);

Job :: struct {
    procedure : Job_Proc,
    data      : rawptr,
}

create :: proc(procedure: Job_Proc, data : rawptr = nil) -> Job {
    return Job { procedure, data };
}

Job_Priority :: enum {
    High,
    Normal,
    Low,
}

Job_System :: struct {
    threads : []^thread.Thread,

    high_priority   : core.MPMC_Queue(Job),
    normal_priority : core.MPMC_Queue(Job),
    low_priority    : core.MPMC_Queue(Job),

    fibers           : []^Fiber,
    active_fibers    : []bool,

    is_shutdown : bool,
}

NUM_FIBERS :: 256;

HIGH_PRIORITY_SIZE   :: 256;
NORMAL_PRIORITY_SIZE :: 512;
LOW_PRIORITY_SIZE    :: 1024;

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

    fibers = make([]^Fiber, NUM_FIBERS);
    active_fibers = make([]bool, NUM_FIBERS);

    fiber_proc :: proc(fiber: ^Fiber) {
        wait_for_work();

        index := thread_index();
        fiber := system.fibers[index];
        switch_to_fiber(fiber);
    }

    for i in core_count..<len(fibers) {
        fiber := make_fiber(fiber_proc);
        fibers[i] = fiber;
    }

    high_priority   = core.make_mpmc_queue(Job, HIGH_PRIORITY_SIZE);
    normal_priority = core.make_mpmc_queue(Job, NORMAL_PRIORITY_SIZE);
    low_priority    = core.make_mpmc_queue(Job, LOW_PRIORITY_SIZE);

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
find_work :: proc() -> (job: Job, ok: bool) {
    using core;

    // Always do high priority jobs first
    if job, ok = dequeue_mpmc(&system.high_priority); ok do return;

    // TODO: Check for waiting jobs

    if job, ok = dequeue_mpmc(&system.normal_priority); ok do return;
    if job, ok = dequeue_mpmc(&system.low_priority); ok do return;

    return;
}

schedule :: proc(job: Job, priority := Job_Priority.Normal) {
    queue : ^core.MPMC_Queue(Job);
    switch priority {
    case .High:   queue = &system.high_priority;
    case .Normal: queue = &system.normal_priority;
    case .Low:    queue = &system.low_priority;
    }

    ok := core.enqueue_mpmc(queue, job);
    assert(ok);
}

try_work :: proc() -> bool {
    if job, ok := find_work(); ok {
        job.procedure(job.data);
        return true;
    }
    return false;
}

wait_for_work :: proc() {
    for !sync.atomic_load(&system.is_shutdown, .Relaxed) {
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

