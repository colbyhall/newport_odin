// +build windows
package job

foreign import "system:kernel32.lib"

LPTHREAD_START_ROUTINE :: #type proc "stdcall" (lpThreadParameter: rawptr) -> u32;

@(default_calling_convention = "std")
foreign kernel32 {
    CreateFiber          :: proc(dwStackSize: uint, lpStartAddress: LPTHREAD_START_ROUTINE, lpParameter: rawptr) -> rawptr ---;
    DeleteFiber          :: proc(lpFiber: rawptr) ---;
    ConvertThreadToFiber :: proc(lpParameter: uintptr) -> rawptr ---;
    SwitchToFiber        :: proc(lpFiber: rawptr) ---;
}

make_fiber :: proc(procedure: Thread_Proc, allocator := context.allocator) -> ^Fiber {
    __windows_fiber_entry_proc :: proc "stdcall" (f: ^Fiber) -> u32 {
        context = f.init_context;
        f.procedure(f);
        return 0;
    }

    f := new(Fiber, allocator);
    f.handle = CreateFiber(0, auto_cast __windows_fiber_entry_proc, f);
    f.procedure = procedure;
    f.init_context = context;
    f.allocator = context.allocator;

    return f;
}

fiber_from_current :: proc(allocator := context.allocator) -> ^Fiber {
    f := new(Fiber, allocator);

    f.handle = ConvertThreadToFiber(nil);
    f.init_context = context;
    f.allocator = allocator;
    f.is_threads = true;

    return f;
}

delete_fiber :: proc(fiber: ^Fiber) {
    if !fiber.is_threads do DeleteFiber(fiber.handle);
    free(fiber, fiber.allocator);
}

switch_to_fiber :: proc(fiber: ^Fiber, data : rawptr = nil) {
    fiber.data = data;

    SwitchToFiber(fiber.handle);
}