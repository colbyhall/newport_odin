package core

import "core:mem"
import "core:sync"

thread_safe_arena_allocator :: proc(arena: ^mem.Arena) -> mem.Allocator {
    return mem.Allocator{
        procedure = arena_allocator_proc,
        data = arena,
    };
}

arena_offset_from_ptr :: proc(arena: ^mem.Arena, data: rawptr) -> uintptr {
    return uintptr(data) - uintptr(&arena.data[0]);
}

arena_ptr_from_offset :: proc(arena: ^mem.Arena, offset: uintptr) -> rawptr {
    return rawptr(uintptr(&arena.data[0]) + offset);
}

arena_allocator_proc :: proc(allocator_data: rawptr, mode: mem.Allocator_Mode,
                             size, alignment: int,
                             old_memory: rawptr, old_size: int, flags: u64, location := #caller_location) -> rawptr {
    using mem;

    arena := cast(^Arena)allocator_data;

    switch mode {
    case .Alloc:
        total_size := size + alignment;

        old_offset := sync.atomic_add(&arena.offset, total_size, .Relaxed);

        if old_offset + total_size > len(arena.data) {
            return nil;
        }

        #no_bounds_check end := &arena.data[old_offset];
        ptr := align_forward(end, uintptr(alignment));

        return zero(ptr, size);
    case .Free:
        // NOTE(bill): Free all at once
        // Use Arena_Temp_Memory if you want to free a block

    case .Free_All:
        sync.atomic_store(&arena.offset, 0, .Relaxed);

    case .Resize:
        return default_resize_align(old_memory, old_size, size, alignment, arena_allocator(arena));

    case .Query_Features:
        set := (^Allocator_Mode_Set)(old_memory);
        if set != nil {
            set^ = {.Alloc, .Free_All, .Resize, .Query_Features};
        }
        return set;

    case .Query_Info:
        return nil;
    }

    return nil;
}