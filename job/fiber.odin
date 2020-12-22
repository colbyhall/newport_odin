package job

import "core:runtime"
import "core:mem"

Fiber_Proc :: #type proc(^Fiber);

MAX_USER_ARGUMENTS :: 8;

Fiber :: struct {
    handle     : rawptr,
    is_threads : bool,

    procedure  : Fiber_Proc,
    data       : rawptr,

    user_index : int,
    user_args  : [MAX_USER_ARGUMENTS]rawptr,

    init_context : runtime.Context,
    allocator    : mem.Allocator,
}

// Fiber API
//
// make_fiber
// fiber_from_current
// delete_fiber
//
// switch_to_fiber