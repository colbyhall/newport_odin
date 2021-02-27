package asset

import path_lib "core:path"
import "core:path/filepath"
import "core:os"
import "core:mem"
import "core:reflect"
import "core:strings"
import "core:slice"
import "core:log"
import "core:encoding/json"
import "core:sync"
import "core:runtime"
import "core:time"
import "core:fmt"

import "../core"

ASSETS_PATH :: "assets";

Flags :: enum {
    Registered,
}

// Base structure for all assets to use
Asset :: struct {
    path : string,

    // Updated by atomics
    loaded  : bool, 
    loading : bool,
    refs    : int,
    
    last_write_time : time.Time,

    flags : bit_set[Flags],

    derived : any,
}

Test :: struct {
    using _ : Asset,

    using _ : struct {
        testing123: string,
        mymy: f32,
    },

    foo : int, 
    bar : f32,
    
    boop : string,
    other : ^Test,

    array : [3]string,
    dynamic_array : [dynamic]int,
    slice : []f32,
}

Register :: #type proc(path: string, last_write_time: time.Time) -> ^Asset;
Load     :: #type proc(using asset: ^Asset) -> bool;
Unload   :: #type proc(using asset: ^Asset) -> bool;

Type_Register :: struct {
    type        : typeid,
    extensions  : []string,
    
    register : Register,
    load     : Load,
    unload   : Unload,
}

Manager :: struct {
    assets : map[string]^Asset,

    registers : [dynamic]Type_Register,
}

@private manager : Manager;

register_auto :: proc($T: typeid, extensions: []string) {
    register_proc :: proc(path: string, last_write_time: time.Time) -> ^Asset {
        // TODO: Check if this is necessary 
        it        := cast(^T)mem.alloc(reflect.size_of_typeid(T)); // Doing this to ensure type info is saved
        it.path    = path;
        it.derived = it^;
        it.last_write_time = last_write_time;
        return it;
    }

    load_proc :: proc(asset: ^Asset) -> bool {
        t := &asset.derived.(T);
        return load_from_json(t);
    }

    using manager;
    type_register := Type_Register{
        type = T,
        extensions = extensions,

        register = register_proc,
        load     = load_proc,
    };
    append(&registers, type_register);
}

register_explicit :: proc($T: typeid, extensions: []string, load: Load, unload: Unload) {
    register_proc :: proc(path: string, last_write_time: time.Time) -> ^Asset {
        // TODO: Check if this is necessary 
        it        := cast(^T)mem.alloc(reflect.size_of_typeid(T)); // Doing this to ensure type info is saved
        it.path    = path;
        it.derived = it^;
        it.last_write_time = last_write_time;
        return it;
    }
    
    using manager;
    type_register := Type_Register{
        type        = T,
        extensions  = extensions,

        register = register_proc,
        load     = load,
        unload   = unload,
    };
    append(&registers, type_register);  
}

register :: proc{ register_auto, register_explicit };

@private
register_from_extension :: proc(ext: string) -> ^Type_Register {
    using manager;

    for it in &registers {
        _, found := slice.linear_search(it.extensions, ext);
        if !found do continue;

        return &it;
    }

    return nil;
}

discover :: proc() {
    if !os.exists(ASSETS_PATH) do os.make_directory(ASSETS_PATH, 0);
    
    walk_proc :: proc(info: os.File_Info, in_err: os.Errno) -> (err: os.Errno, skip_dir: bool) {
        using manager;
        if info.is_dir do return os.ERROR_NONE, false;

        ext := path_lib.ext(info.name)[1:]; // advance past the .
        rel_path := info.fullpath[strings.index(info.fullpath, ASSETS_PATH):];

        reg := register_from_extension(ext);
        if reg == nil do return os.ERROR_NONE, false;

        path        := strings.clone(rel_path);
        asset       := reg.register(path, info.modification_time);
        asset.flags |= { .Registered };
        assets[path] = asset;

        return os.ERROR_NONE, false;
    }

    filepath.walk(ASSETS_PATH, walk_proc);
}

is_loaded :: proc(using asset: ^Asset) -> bool {
    return sync.atomic_load(&loaded, .Relaxed);
}

is_loading :: proc(using asset: ^Asset) -> bool {
    return sync.atomic_load(&loading, .Relaxed);
}

load_from_json :: proc(asset: ^$T) -> bool {
    source, found := os.read_entire_file(asset.path);
    if !found {
        log.errorf("[Asset] Failed to load file at path {}", asset.path);
        return false;
    }

    val, err := json.parse(source, .JSON5, true);
    defer json.destroy_value(val);

    log_error_json :: proc(error, path: string, value: json.Value) {
        log.errorf("[Asset] {}. In \"{}\" at line {} column {}", error, path, value.pos.line, value.pos.column);
    }

    // Do JSON error checking
    if err != .None {
        errors_string := [len(json.Error)]string{
            "none",
            "eof",

            "Illegal character",
            "Invalid number",
            "String not terminated",
            "Invalid string",

            "Unexpected token",
            "Expected string for object key",
            "Duplicate object key",
            "Expected colon after key"
        };

        log_error_json(errors_string[err], asset.path, val);
        return false;
    }

    unmarshal_value :: proc(value_ptr: rawptr, type_info: ^reflect.Type_Info, path: string, val: json.Value) -> bool {
        using reflect;

        #partial switch v in type_info.variant {
        case Type_Info_Integer:
            result, ok := val.value.(json.Integer);
            if !ok {
                log_error_json("Incorrect Type. Type should be an integer", path, val);
                return false;
            }

            if v.signed {
                switch type_info.id {
                case i8:
                    x := cast(^i8)value_ptr;
                    x^ = cast(i8)result;
                case i16:
                    x := cast(^i16)value_ptr;
                    x^ = cast(i16)result;
                case i32:
                    x := cast(^i32)value_ptr;
                    x^ = cast(i32)result;
                case i64, int:
                    x := cast(^i64)value_ptr;
                    x^ = result;
                } 
            } else {
                switch type_info.id {
                case u8:
                    x := cast(^u8)value_ptr;
                    x^ = cast(u8)result;
                case u16:
                    x := cast(^u16)value_ptr;
                    x^ = cast(u16)result;
                case u32:
                    x := cast(^u32)value_ptr;
                    x^ = cast(u32)result;
                case u64, uint:
                    x := cast(^u64)value_ptr;
                    x^ = cast(u64)result;
                } 
            }
        case Type_Info_Float:
            result, ok := val.value.(json.Float);
            if !ok {
                int_result, ok := val.value.(json.Integer);
                if !ok {
                    log_error_json("Incorrect type. Type should be a float or integer", path, val);
                    return false;
                }

                result = cast(f64)int_result;
            }

            switch type_info.id {
            case f32:
                x := cast(^f32)value_ptr;
                x^ = cast(f32)result;
            case f64:
                x := cast(^f64)value_ptr;
                x^ = result;
            }
        case Type_Info_String:
            result, ok := val.value.(json.String);
            if !ok {
                log_error_json("Incorrect type. Type should be a string", path, val);
                return false;
            }

            x := cast(^string)value_ptr;
            x^ = strings.clone(result);

        case Type_Info_Pointer:
            elem := type_info_base(v.elem);

            _, ok0 := elem.variant.(Type_Info_Struct);
            if !ok0 {
                log_error_json("Value for member with non asset ptr", path, val);
                return false;   
            }

            result, ok1 := val.value.(json.String);
            if !ok1 {
                log_error_json("Incorrect type. Type should be a string", path, val);
                return false;
            }

            found_asset := find(result);
            if found_asset == nil {
                log_error_json("Invalid path for asset ptr", path, val);
                return false;
            }

            x := cast(^rawptr)value_ptr;
            data, _ := any_data(found_asset.derived);
            x^ = data;
        case Type_Info_Array:
            array, ok := val.value.(json.Array);
            if !ok {
                log_error_json("Expected type to be \"Array\"", path, val);
                return false;
            }

            if len(array) > v.count {
                log.errorf("Array must not be over {} long. In \"{}\" at line {} column {}", v.count, path, val.pos.line, val.pos.column);
                return false;   
            }

            return unmarshal_array(rawptr(value_ptr), v.elem_size, v.elem, path, val);
        case Type_Info_Dynamic_Array:
            using runtime;

            array, ok := val.value.(json.Array);
            if !ok {
                log_error_json("Expected type to be \"Array\"", path, val);
                return false;
            }

            array_ptr := cast(^Raw_Dynamic_Array)value_ptr;
            array_ptr.data = mem.alloc(v.elem_size * len(array), type_info.align);
            array_ptr.len = len(array);
            array_ptr.cap = len(array);
            array_ptr.allocator = context.allocator;

            return unmarshal_array(array_ptr.data, v.elem_size, v.elem, path, val);
        case Type_Info_Slice:
            using runtime;

            array, ok := val.value.(json.Array);
            if !ok {
                log_error_json("Expected type to be \"Array\"", path, val);
                return false;
            }

            array_ptr := cast(^Raw_Slice)value_ptr;
            array_ptr.data = mem.alloc(v.elem_size * len(array), type_info.align);
            array_ptr.len = len(array);

            return unmarshal_array(array_ptr.data, v.elem_size, v.elem, path, val);
        case: 
            log.errorf("[Asset] Incomplete implementation. Cannot unmarshal type \"{}\". In \"{}\" at line {} column {}", type_info.id, path, val.pos.line, val.pos.column);
            return false;
        }   

        return true;
    }

    unmarshal_array :: proc(base: rawptr, elem_size: int, type_info: ^reflect.Type_Info, path: string, val: json.Value) -> bool{
        array, ok := val.value.(json.Array);
        assert(ok);

        for val, i in array {
            value_ptr := uintptr(base) + uintptr(elem_size * i);
            ok := unmarshal_value(rawptr(value_ptr), type_info, path, val);
            if !ok do return false;
        }
        return true;
    }

    unmarshal_struct :: proc(base: rawptr, type_info: ^reflect.Type_Info, path: string, val: json.Value) -> bool {
        Member :: struct {
            type     : ^reflect.Type_Info,
            offset   : uintptr,
        };

        // We need an easy way to access all members of T's struct. This includes the 
        // members inside a 'using' struct. We dont want to force the json object to
        // members to be in the same order as T's 
        // - CHall 1/21/2021
        members := make(map[string]Member);
        defer delete(members);
        {
            using reflect;

            struct_info, ok := type_info.variant.(Type_Info_Struct);
            assert(ok); // asset should obviously be a struct

            recursive_fill_members :: proc(members: ^map[string]Member, struct_info: ^reflect.Type_Info_Struct, offset: uintptr) {
                for name, i in struct_info.names {
                    base_type_info := type_info_base(struct_info.types[i]);

                    offset := offset + struct_info.offsets[i];

                    if struct_info.usings[i] {
                        new_struct_info, ok := base_type_info.variant.(Type_Info_Struct);
                        assert(ok);
                        recursive_fill_members(members, &new_struct_info, offset);
                        continue;
                    }

                    member := Member{
                        type   = base_type_info,
                        offset = offset,
                    };
                    (members^)[name] = member;
                }
            }

            recursive_fill_members(&members, &struct_info, 0);
        }

        obj, ok := val.value.(json.Object);
        if !ok {
            log_error_json("Expected type to be \"Object\"", path, val);
            return false;
        }

        for key, value in obj {
            member, found := members[key];
            if !found {
                log.warnf("[Asset] Unknown member \"{}\" in {}", key, path);
                continue;
            }

            value_ptr := uintptr(base) + member.offset;
            unmarshal_value(rawptr(value_ptr), member.type, path, value);
        }

        return true;
    }

    obj, ok := val.value.(json.Object);
    if !ok {
        log_error_json("Initial type must be object", asset.path, val);
        return false;
    }

    type_info := reflect.type_info_base(type_info_of(T));
    unmarshal_struct(asset, type_info, asset.path, val);

    return true;
}

acquire_asset :: proc(asset: ^Asset) -> bool {
    using manager;

    if asset == nil do return false;

    sync.atomic_add(&asset.refs, 1, .Relaxed);

    if is_loaded(asset) do return true;

    if is_loading(asset) {
        log.errorf("[Asset] {} is already being loaded", asset.path);
        return false;
    }

    ext := path_lib.ext(asset.path)[1:];
    reg := register_from_extension(ext);
    assert(reg != nil);

    _, ok := sync.atomic_compare_exchange_weak(&asset.loading, false, true, .Sequentially_Consistent, .Relaxed);
    if !ok do return false;

    loaded := reg.load(asset);
    if !loaded {
        sync.atomic_store(&asset.loading, false, .Relaxed);
        log.errorf("[Asset] Failed to load asset \"{}\"", asset.path);
        return false;
    }

    sync.atomic_store(&asset.loaded, true, .Relaxed);
    sync.atomic_store(&asset.loading, false, .Relaxed);

    return true;
}

acquire_asset_by_path :: proc(path: string) -> (^Asset, bool) {
    using manager;

    asset := find_asset(path);
    loaded := acquire_asset(asset);
    return asset, loaded;
}

acquire_casted :: proc(asset: ^$T) -> bool {
    return acquire_asset(asset);
}

acquire_casted_by_path :: proc(path: string, $T: typeid) -> (^T, bool) {
    using manager;

    t := find_casted(path, T);
    loaded := acquire_casted(t);

    return t, loaded;
}

acquire :: proc{ acquire_asset, acquire_casted, acquire_asset_by_path, acquire_casted_by_path };

release :: proc(asset: ^Asset) -> bool {
    using manager;

    if asset == nil do return false;

    assert(is_loaded(asset), "Releasing should only happen after an asset is acquired");

    refs := sync.atomic_sub(&asset.refs, 1, .Relaxed);

    if refs == 0 {
        ext := path_lib.ext(asset.path)[1:];
        reg := register_from_extension(ext);
        assert(reg != nil);

        _, ok := sync.atomic_compare_exchange_weak(&asset.loading, false, true, .Sequentially_Consistent, .Relaxed);
        if !ok {
            log.error("[Asset] Failed to unload asset \"{}\"!!!!!", asset.path);
            return false;
        }

        unloaded := reg.unload(asset);
        if !unloaded {
            sync.atomic_store(&asset.loading, false, .Relaxed);
            log.error("[Asset] Failed to unload asset \"{}\"!!!!!", asset.path);
            return false;
        }

        sync.atomic_store(&asset.loaded, false, .Relaxed);
        sync.atomic_store(&asset.loading, false, .Relaxed);
        return true;
    }

    return false;

}

find_asset :: proc(path: string) -> ^Asset {
    using manager;

    path := strings.clone(path, context.temp_allocator);

    // TODO: Make sure the path is right and correct it
    bytes := transmute([]byte)path;
    for b in &bytes {
        if b == '/' do b = '\\';
    }

    asset := assets[path];
    return asset;
}

find_casted :: proc(path: string, $T: typeid) -> ^T {
    asset := find_asset(path);
    if asset == nil do return nil;

    t := &asset.derived.(T);
    return t;
}

find :: proc{ find_asset, find_casted };