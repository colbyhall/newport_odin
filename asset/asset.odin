package asset

import "core:mem"
import "core:reflect"

// Base structure for all assets to use
Asset :: struct {
    path   : string,
    loaded : bool,

    derived : any,
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

    using manager;
    type_register := Type_Register{
        type = T,
        extensions = extensions,

        register = register_proc,
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