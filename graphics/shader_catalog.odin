package graphics

import "../asset"

import "core:os"
import "core:log"

Shader_Catalog :: asset.Catalog(Shader);
shader_catalog : Shader_Catalog;

init_shader_catalog :: proc() {
    append(&shader_catalog.extensions, "glsl");

    asset.init_catalog(&shader_catalog, "Shader Catalog", register_shader, reload_shader);
}

register_shader :: proc(cat: ^asset.Catalog_Base, name: string, path: string) {
    shader     := new(Shader);
    shader.name = name;
    shader.path = path;
    shader.derived = shader^;

    cat := cast(^Shader_Catalog)cat;
    cat.assets[name] = shader;
    asset.asset_catalog.assets[name] = shader;
}

reload_shader :: proc(cat: ^asset.Catalog_Base, name: string, path: string, unload: bool) -> bool {
    cat := cast(^Shader_Catalog)cat;

    source, found := os.read_entire_file(path);
    if !found do return false;
    defer delete(source);

    shader := cat.assets[name];

    if !compile_shader(shader, cstring(&source[0])) {
        log.infof("[Asset] Failed to compile shader \"{}\"", path);
        return false;
    }

    log.infof("[Asset] Loaded shader \"{}\"", path);

    return true;
}
