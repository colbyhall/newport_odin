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

    log_json_error :: proc(val: json.Value, err: json.Error, path: string) {
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

        log.errorf("[Asset] Error \"{}\" in {} at line {} column {}", errors_string[err], path, val.pos.line, val.pos.column);
    }

    val, err := json.parse(source, .JSON5, true);
    if err != .None {
        log_json_error(val, err, asset.path);
        return false;
    }
    defer json.destroy_value(val);

    log.warn(val.value);
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