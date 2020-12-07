package asset

import "core:path"
import "core:path/filepath"
import "core:os"
import "core:fmt"
import "core:slice"
import "core:strings"
import "core:reflect"

DATA_PATH :: "data/";

Asset :: struct {
    name   : string,
    path   : string,
    loaded : bool,

    derived : any,
}

Register :: #type proc(using catalog: ^Catalog_Base, name: string, path: string);
Reload   :: #type proc(using catalog: ^Catalog_Base, name: string, path: string, unload: bool) -> bool;

Catalog_Base :: struct {
    name       : string,
    extensions : [dynamic]string,
    type       : typeid,

    register : Register,
    reload   : Reload,
}

Catalog :: struct(T: typeid) {
    using base : Catalog_Base,
    assets     : map[string]^T,
}

Asset_Catalog :: Catalog(Asset);
asset_catalog : Asset_Catalog;

all_catalogs : [dynamic]^Catalog_Base;

init_catalog :: proc(catalog: ^$T/Catalog($E), name: string, register: Register, reload: Reload) {
    catalog.name     = name;
    catalog.register = register;
    catalog.reload   = reload;
    catalog.type     = E;

    append(&all_catalogs, catalog);
}

find :: proc(catalog: ^$T/Catalog($E), name: string) -> ^E {
    asset, found := catalog.assets[name];

    if !found do return nil; 

    if !asset.loaded {
        if catalog.reload(catalog, asset.name, asset.path, false) do asset.loaded = true;
    }

    return asset;
}

find_in_all :: proc(name: string) -> ^Asset {
    asset, found := asset_catalog.assets[name];

    if !found do return nil;

    using reflect;

    if !asset.loaded {
        _, id := any_data(asset.derived);
        for it in all_catalogs {
            if it.type == id {
                if it.reload(it, asset.name, asset.path, false) do asset.loaded = true;
                break;
            }
        }
    }

    return asset;
}

discover :: proc() {
    walk_proc :: proc(info: os.File_Info, in_error: os.Errno) -> (err: os.Errno, skip_dir: bool) {
        if info.is_dir { return 0, false; }

        my_ext  := path.ext(info.name)[1:]; // advance past the .
        my_name := path.name(info.name);

        for catalog in all_catalogs {
            _, has_ext := slice.linear_search(catalog.extensions[:], my_ext);

            if !has_ext do continue;

            catalog.register(catalog, strings.clone(my_name), strings.clone(info.fullpath));
        }

        return 0, false;
    }

    filepath.walk(DATA_PATH, walk_proc);
}