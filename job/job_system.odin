package job

import "core:thread"
import "core:sync"
import "core:log"
import "core:time"
import "core:os"
import "core:slice"

// FOR DEBUG ONLY
import "core:fmt"

import "../core"

Counter :: distinct u32; // Will be used strictly as an atomic

wait :: proc(counter: ^Counter, auto_cast target : Counter = 0, stay_on_thread := false) {
    c := counter;

    index := thread_index();

    if sync.atomic_load(c, .Relaxed) == target do return;

    for _, i in system.waiting {
        it := &system.waiting[i];

        if sync.atomic_load(&it.active, .Relaxed) do continue;

        _, ok0 := sync.atomic_compare_exchange_weak(&it.in_use, false, true, .Sequentially_Consistent, .Relaxed);
        if !ok0 do continue;

        sync.atomic_store(&it.active, true, .Relaxed);

        it.fiber  = system.fibers_on_thread[index];
        it.target = target;
        it.counter = c;
        if stay_on_thread do it.thread = index;
        else do it.thread = -1;

        sync.atomic_store(&it.in_use, false, .Relaxed);

        if check_waiting() do return;
        free_fiber := find_fiber();

        {
            index, _ := slice.linear_search(system.fibers, free_fiber);
            sync.atomic_store(&system.active_fibers[index], true, .Relaxed);
        }

        system.fibers_on_thread[index] = free_fiber;
        switch_to_fiber(free_fiber);
        return;
    }

    panic("Didn't have a large enough wait buffer");
}

Job_Proc :: #type proc(data: rawptr);

Job :: struct {
    procedure : Job_Proc,
    data      : rawptr,
    counter   : ^Counter,
}

create :: proc(procedure: Job_Proc, data : rawptr = nil) -> Job {
    return Job { procedure, data, nil };
}

Job_Priority :: enum {
    High,
    Normal,
    Low,
}

Waiting_Fiber :: struct {
    fiber   : ^Fiber,
    counter : ^Counter,
    target  : Counter,
    thread  : int,

    active  : bool,
    in_use  : bool, // Used for thread safety
}

Job_System :: struct {
    threads : []^thread.Thread,
    fibers_on_thread : []^Fiber,

    high_priority   : core.MPMC_Queue(Job),
    normal_priority : core.MPMC_Queue(Job),
    low_priority    : core.MPMC_Queue(Job),

    fibers           : []^Fiber,
    active_fibers    : []bool,

    waiting : []Waiting_Fiber,

    is_shutdown : bool,
}

NUM_FIBERS :: 256;

NUM_WAITING :: 256;

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
    fibers_on_thread = make([]^Fiber, core_count);
    waiting = make([]Waiting_Fiber, NUM_WAITING);

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

        fibers_on_thread[index] = fiber;
        switch_to_fiber(fiber);
    }

    fibers[0] = fiber_from_current();
    fibers_on_thread[0] = fibers[0];

    sync.atomic_store(&active_fibers[0], true, .Relaxed);

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
        fibers_on_thread[index] = fibers[index];
        sync.atomic_store(&active_fibers[index], true, .Relaxed);

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

            if _, ok := sync.atomic_compare_exchange_weak(&system.active_fibers[i], false, true, .Sequentially_Consistent, .Relaxed); ok {
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

    if check_waiting() do return;

    if job, ok = dequeue_mpmc(&system.normal_priority); ok do return;
    if job, ok = dequeue_mpmc(&system.low_priority); ok do return;

    return;
}

schedule_single :: proc(job: Job, counter: ^Counter = nil, priority := Job_Priority.Normal) {
    queue : ^core.MPMC_Queue(Job);
    switch priority {
    case .High:   queue = &system.high_priority;
    case .Normal: queue = &system.normal_priority;
    case .Low:    queue = &system.low_priority;
    }

    job := job;
    job.counter = counter;

    sync.atomic_add(counter, 1, .Relaxed);

    ok := core.enqueue_mpmc(queue, job);
    assert(ok);
}

schedule_slice :: proc(jobs: []Job, counter: ^Counter = nil, priority := Job_Priority.Normal) {
    for it in jobs do schedule_single(it, counter, priority);
}

schedule :: proc{ schedule_single, schedule_slice };

@private
check_waiting :: proc(is_trying_work := false) -> bool {
    ti := thread_index();
    index, _ := slice.linear_search(system.fibers, system.fibers_on_thread[ti]);

    for _, i in &system.waiting {
        it := &system.waiting[i];

        if !sync.atomic_load(&it.active, .Relaxed) do continue;
        
        _, ok0 := sync.atomic_compare_exchange_weak(&it.in_use, false, true, .Sequentially_Consistent, .Relaxed);
        if !ok0 do continue;

        if sync.atomic_load(it.counter, .Relaxed) != it.target {
            sync.atomic_store(&it.in_use, false, .Relaxed);
            continue;
        }

        if it.thread != -1 && it.thread != ti {
            sync.atomic_store(&it.in_use, false, .Relaxed);
            continue;
        }
        
        sync.atomic_store(&it.active, false, .Relaxed);
        sync.atomic_store(&it.in_use, false, .Relaxed);

        if is_trying_work do sync.atomic_store(&system.active_fibers[index], false, .Relaxed);

        system.fibers_on_thread[thread_index()] = it.fiber;
        switch_to_fiber(it.fiber);
        return true;
    }

    return false;
}

try_work :: proc() -> bool {
    if check_waiting(true) do return true;

    if job, ok := find_work(); ok {
        job.procedure(job.data);

        if job.counter != nil {
            sync.atomic_sub(job.counter, 1, .Relaxed);
            check_waiting(true);
        }

        return true;
    }
    return false;
}

wait_for_work :: proc() {
    for !sync.atomic_load(&system.is_shutdown, .Relaxed) {
        if !try_work() do time.sleep(100);
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

