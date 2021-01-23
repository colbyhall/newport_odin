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

ASSETS_PATH :: "assets";

// Base structure for all assets to use
Asset :: struct {
    path : string,

    loaded  : bool,
    loading : bool,

    derived : any,
}

Test :: struct {
    using _ : Asset,

    foo : int, 
    bar : f32,
    
    boop : string,
    other : ^Test,
}

Register :: #type proc(path: string) -> ^Asset;
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
    register_proc :: proc(path: string) -> ^Asset {
        // TODO: Check if this is necessary 
        it        := cast(^T)mem.alloc(reflect.size_of_typeid(T)); // Doing this to ensure type info is saved
        it.path    = path;
        it.derived = it^;
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
    register_proc :: proc(path: string) -> ^Asset {
        // TODO: Check if this is necessary 
        it        := cast(^T)mem.alloc(reflect.size_of_typeid(T)); // Doing this to ensure type info is saved
        it.path    = path;
        it.derived = it^;
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
    walk_proc :: proc(info: os.File_Info, in_err: os.Errno) -> (err: os.Errno, skip_dir: bool) {
        using manager;
        if info.is_dir do return os.ERROR_NONE, false;

        ext := path_lib.ext(info.name)[1:]; // advance past the .
        rel_path := info.fullpath[strings.index(info.fullpath, ASSETS_PATH):];

        reg := register_from_extension(ext);
        if reg == nil do return os.ERROR_NONE, false;

        path := strings.clone(rel_path);
        assets[path] = reg.register(path);

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
    if err != .None {
        errors_string := [len(json.Error)]string{
            "none",
            "eof",

            "illegal character",
            "invalid number",
            "string not terminated",
            "invalid string",

            "unexpected token",
            "expected string for object key",
            "duplicate object key",
            "expected colon after key"
        };

        log.errorf("[Asset] Error \"{}\" in {} at line {} column {}", errors_string[err], asset.path, val.pos.line, val.pos.column);
        return false;
    }
    defer json.destroy_value(val);

    Member :: struct {
        type     : ^reflect.Type_Info,
        offset   : uintptr,
    };

    members := make(map[string]Member);
    defer delete(members);

    // Fill members info
    {
        using reflect;

        type_info := type_info_base(type_info_of(T));
        struct_info, ok := type_info.variant.(Type_Info_Struct);
        assert(ok); // asset should obviously be a struct

        recursive_fill_member :: proc(members: ^map[string]Member, struct_info: ^reflect.Type_Info_Struct) {
            for name, i in struct_info.names {
                base_type_info := type_info_base(struct_info.types[i]);

                if struct_info.usings[i] {
                    new_struct_info, ok := base_type_info.variant.(Type_Info_Struct);
                    assert(ok);
                    recursive_fill_member(members, &new_struct_info);
                    continue;
                }

                member := Member{
                    type   = base_type_info,
                    offset = struct_info.offsets[i],
                };
                (members^)[name] = member;
            }
        }

        recursive_fill_member(&members, &struct_info);
    }

    // TODO: Make this recursive so we can have nested structures to fill
    #partial switch v in val.value {
    case json.Object:
        using reflect;

        for key, val in v {
            member, found := members[key];
            if !found {
                log.warnf("[Asset] Unknown member \"{}\" in {}", key, asset.path);
                continue;
            }

            value_ptr := uintptr(asset) + member.offset;

            #partial switch v in member.type.variant {
            case Type_Info_Integer:
                result, ok := val.value.(json.Integer);
                if !ok {
                    log.errorf("[Asset] Error \"Incorrect type. Type should be an integer\" in {} at line {} column {}", asset.path, val.pos.line, val.pos.column);
                    continue;
                }

                if v.signed {
                    switch member.type.id {
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
                    switch member.type.id {
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
                    log.errorf("[Asset] Error \"Incorrect type. Type should be a float\" in {} at line {} column {}", asset.path, val.pos.line, val.pos.column);
                    continue;
                }

                switch member.type.id {
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
                    log.errorf("[Asset] Error \"Incorrect type. Type should be a string\" in {} at line {} column {}", asset.path, val.pos.line, val.pos.column);
                    continue;
                }

                x := cast(^string)value_ptr;
                x^ = strings.clone(result);

            case Type_Info_Pointer:
                elem := type_info_base(v.elem);

                _, ok0 := elem.variant.(Type_Info_Struct);
                if !ok0 {
                    log.errorf("[Asset] Error \"Value for member with non asset ptr\" in {} at line {} column {} of member {}", asset.path, val.pos.line, val.pos.column, key);
                    continue;   
                }

                result, ok1 := val.value.(json.String);
                if !ok1 {
                    log.errorf("[Asset] Error \"Incorrect type. Type should be a string\" in {} at line {} column {}", asset.path, val.pos.line, val.pos.column);
                    continue;
                }

                found_asset := find(result);
                if found_asset == nil {
                    log.errorf("[Asset] Error \"Invalid path for asset ptr\" in {} at line {} column {}", asset.path, val.pos.line, val.pos.column);
                    continue;
                }

                x := cast(^rawptr)value_ptr;
                data, _ := any_data(found_asset.derived);
                x^ = data;
            case: 
                log.errorf("[Asset] Incomplete implementation. Cannot unmarshal type \"{}\" for member \"{}\" in {}", member.type.id, key, asset.path);
                continue;
            }
        }
    case:
        log.errorf("[Asset] Error \"initial type must be object\" in {}", asset.path);
        return false;
    }

    return true;
}

load_asset :: proc(asset: ^Asset) -> bool {
    using manager;

    if asset == nil do return false;

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
        return false;
    }

    sync.atomic_store(&asset.loaded, true, .Relaxed);
    sync.atomic_store(&asset.loading, false, .Relaxed);

    return true;
}

load_asset_by_path :: proc(path: string) -> (^Asset, bool) {
    using manager;

    asset := find_asset(path);
    loaded := load_asset(asset);
    return asset, loaded;
}

load_casted :: proc(asset: ^$T) -> bool {
    return load_asset(asset);
}

load_casted_by_path :: proc(path: string, $T: typeid) -> (^T, bool) {
    using manager;

    t := find_casted(path, T);
    loaded := load_casted(t);

    return t, loaded;
}

load :: proc{ load_asset, load_casted, load_asset_by_path, load_casted_by_path };

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