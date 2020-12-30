package core

import "core:sync"
import "core:mem"

Float_Heap_Bucket :: struct(Value: typeid) {
    key   : f32,
    value : Value,
}

Float_Heap :: struct(Value: typeid) {
    buckets : [dynamic]Float_Heap_Bucket(Value),
}

make_float_heap :: proc($T: typeid, reserve := 0, allocator := context.allocator) -> Float_Heap(T) {
    buckets := make([dynamic]Float_Heap_Bucket(T), 1, reserve, allocator);
    buckets[0].key = 0;
    return Float_Heap(T) { buckets };
}

delete_float_heap :: proc(using heap: Float_Heap($E)) {
    delete(heap.buckets);
}

heap_parent  :: inline proc(index: int) -> int { return index / 2; }
heap_left    :: inline proc(index: int) -> int { return index * 2; }
heap_right   :: inline proc(index: int) -> int { return index * 2 + 1; }
heap_is_leaf :: inline proc(index, count: int) -> bool { return index >= count / 2 && index <= count; }

float_heap_minify :: proc(using heap: ^Float_Heap($E), index: int) {
    if heap_is_leaf(index, len(buckets) - 1) do return;

    if buckets[index].key > buckets[heap_left(index)].key {
        x := buckets[index];
        buckets[index] = buckets[heap_left(index)];
        buckets[heap_left(index)] = x;

        float_heap_minify(heap, heap_left(index));
    } else if buckets[index].key > buckets[heap_right(index)].key {
        x := buckets[index];
        buckets[index] = buckets[heap_right(index)];
        buckets[heap_right(index)] = x;
        
        float_heap_minify(heap, heap_right(index));
    }
}

push_min_float_heap :: proc(using heap: ^Float_Heap($E), key: f32, value: E) {
    e := Float_Heap_Bucket(E){ key, value };
    append(&buckets, e);

    index := len(buckets) - 1;

    for heap_is_leaf(index, len(buckets) - 1) && buckets[index].key < buckets[heap_parent(index)].key {
        x := buckets[index];
        buckets[index] = buckets[heap_parent(index)];
        buckets[heap_parent(index)] = x;

        index = heap_parent(index);
    }

    for i := (len(buckets) - 1) / 2; i >= 1; i -= 1 {
        float_heap_minify(heap, i);
    }
}

pop_min_float_heap :: proc(using heap: ^Float_Heap($E)) -> E {
    e := buckets[1].value;
    buckets[1] = buckets[len(buckets) - 1];
    pop(&buckets);

    for i := (len(buckets) - 1) / 2; i >= 1; i -= 1 {
        float_heap_minify(heap, i);
    }

    return e;
}

Sparse_Generation_Element :: struct(Value: typeid) {
    in_use     : bool,
    generation : i32,
    value      : Value,
}

Sparse_Generation_Array :: struct(Value: typeid) {
    array  : [dynamic]Sparse_Generation_Element(Value),
    unused : [dynamic]i32, // Index into array 
}

Sparse_Generation_Id :: struct #raw_union {
    using _ : struct {
        index      : i32,
        generation : i32,
    },
    whole : int,
}
nil_sga_id :: 0;

make_sga_cap :: proc($T: typeid, cap: int, allocator := context.allocator) -> Sparse_Generation_Element(T) {
    array := make([dynamic]Sparse_Generation_Element(T), cap, allocator);
    unused := make([dynamic]int, 0, cap, allocator);

    for i in 0..<cap do append(&unused, i);

    return Sparse_Generation_Array(Value){ array, unused };
}

make_sga_empty :: proc($T: typeid, allocator := context.allocator) -> Sparse_Generation_Element(T) {
    return make_sparse_generation_array_cap(T, 0, allocator);
}

make_sga :: proc{ make_sga_cap, make_sga_empty };

insert_sga :: proc(using sga: ^Sparse_Generation_Array($E), e: E) -> Sparse_Generation_Id {
    if len(unused) > 0 {
        index := pop(&unused);

        elem := &array[index];
        assert(!elem.in_use);

        elem.in_use = true;
        elem.generation += 1;
        elem.value = e;

        result : Sparse_Generation_Id;
        result.index = index;
        result.generation = elem.generation;
        return result;
    }

    elem := Sparse_Generation_Element(E){ true, 1, e };
    append(&array, elem);
    
    result : Sparse_Generation_Id;    
    result.index = i32(len(array) - 1);
    result.generation = 1;
    return result;
}

remove_sga :: proc(using sga: ^Sparse_Generation_Array($E), id: Sparse_Generation_Id) -> bool {
    if id.whole == 0 || id.generation == 0 do return false;

    if id.index >= i32(len(array)) || id.index < 0 do return false;

    elem := &array[id.index];
    if !elem.in_use || elem.generation != id.generation do return false;

    elem.in_use = false;
    append(&unused, id.index);
    return true;
}

find_sga_ptr :: proc(using sga: Sparse_Generation_Array($E), id: Sparse_Generation_Id) -> ^E {
    if id.whole == 0 || id.generation == 0 do return nil;

    if id.index >= i32(len(array)) || id.index < 0 do return nil;

    elem := &array[id.index];
    if !elem.in_use || elem.generation != id.generation do return nil;

    return &elem.value;
}

find_sga_value :: proc(using sga: Sparse_Generation_Array($E), id: Sparse_Generation_Id) -> (value: E, ok: bool) {
    elem := find_sga_ptr(sga, id);
    if elem == nil {
        ok = false;
        return;
    }

    ok = true;
    value = elem^;
    return;
}

step_sga :: proc(using sga: ^Sparse_Generation_Array($E), id: Sparse_Generation_Id) -> (Sparse_Generation_Id, bool) {
    if id.whole == 0 || id.generation == 0 do return id, false;

    if id.index >= i32(len(array)) || id.index < 0 do return id, false;

    elem := &array[id.index];
    if !elem.in_use || elem.generation != id.generation do return id, false;
    elem.generation += 1;

    id := id;
    id.generation = elem.generation;
    return id, true;
}

Sparse_Generation_Array_Iterator :: struct(Value: typeid) {
    index : int,
    sga   : ^Sparse_Generation_Array(Value),
}

make_sga_iterator :: proc(sga: ^Sparse_Generation_Array($E)) -> Sparse_Generation_Array_Iterator(E) {
    return Sparse_Generation_Array_Iterator(E){ 0, sga };
}

sga_iterator :: proc(using it: ^Sparse_Generation_Array_Iterator($E)) -> (val: ^E, idx: int, cond: bool) {
    for index < len(sga.array) {
        e := &sga.array[index];

        index += 1;
        
        if !e.in_use do continue;
        
        val = &e.value;
        idx = index;
        cond = true;

        return;
    }

    cond = false;
    return;
}

// Source: Dmitry Vyukov's MPMC
// http://www.1024cores.net/home/lock-free-algorithms/queues/bounded-mpmc-queue

// TODO: Use the core's implementation. I just didn't want to mess with the whole -llvm-api thing
Cache_Line_Pad :: struct {_: [64]byte};

MPMC_Cell :: struct(T: typeid) {
    sequence : int,
    data     : T,
}

MPMC_Queue :: struct(T: typeid) {
    using pad0  : Cache_Line_Pad,
    buffer      : ^MPMC_Cell(T),
    buffer_mask : int,
    using pad1  : Cache_Line_Pad,
    enqueue_pos : int,
    using pad2  : Cache_Line_Pad,
    dequeue_pos : int,
    using pad3  : Cache_Line_Pad,
}

make_mpmc_queue :: proc($T: typeid, size: int) -> MPMC_Queue(T) {
    assert(size >= 2 && (size & (size - 1)) == 0);

    buffer := cast(^MPMC_Cell(T))mem.alloc(size_of(MPMC_Cell(T)) * size);
    for i in 0..<size {
        it := mem.ptr_offset(buffer, i);
        sync.atomic_store(&it.sequence, i, .Relaxed); // TODO(colby): Determine if i have to use atomics during construction?
    }

    result : MPMC_Queue(T);
    result.buffer = buffer;
    result.buffer_mask = size - 1;
    return result;
}

delete_mpmc_queue :: proc(using q: ^MPMC_Queue($E)) {
    free(buffer);
}

enqueue_mpmc :: proc(q: ^MPMC_Queue($E), e: E) -> bool {
    cell : ^MPMC_Cell(E);
    pos  := sync.atomic_load(&q.enqueue_pos, .Relaxed);
    for {
        cell = mem.ptr_offset(q.buffer, pos & q.buffer_mask);
        seq := sync.atomic_load(&cell.sequence, .Acquire);
        dif := seq - pos;

        if dif == 0 {
            if _, ok := sync.atomic_compare_exchange_weak(&q.enqueue_pos, pos, pos + 1, .Relaxed, .Relaxed); ok do break;
        } else if dif < 0 do return false;
        else do pos = sync.atomic_load(&q.enqueue_pos, .Relaxed);
    }
    cell.data = e;
    sync.atomic_store(&cell.sequence, pos + 1, .Release);
    return true;
}

dequeue_mpmc :: proc(q: ^MPMC_Queue($E)) -> (data: E, ok: bool) {
    cell : ^MPMC_Cell(E);
    pos  := sync.atomic_load(&q.dequeue_pos, .Relaxed);
    for {
        cell = mem.ptr_offset(q.buffer, pos & q.buffer_mask);
        seq := sync.atomic_load(&cell.sequence, .Acquire);
        dif := seq - (pos + 1);

        if dif == 0 {
            if _, ok := sync.atomic_compare_exchange_weak(&q.dequeue_pos, pos, pos + 1, .Relaxed, .Relaxed); ok do break;
        } else if dif < 0 do return;
        else do pos = sync.atomic_load(&q.dequeue_pos, .Relaxed);
    }
    data = cell.data;
    sync.atomic_store(&cell.sequence, pos + q.buffer_mask + 1, .Release);

    ok = true;

    return;
}