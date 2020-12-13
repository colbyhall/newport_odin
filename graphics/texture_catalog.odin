package graphics

import "../asset"

import "../deps/stb/stbi"

import "core:strings"
import "core:mem"
import "core:log"

Texture_Catalog :: asset.Catalog(Texture2d);
texture_catalog : Texture_Catalog;

init_texture_catalog :: proc() {
    append(&texture_catalog.extensions, "png");
    append(&texture_catalog.extensions, "jpg");
    append(&texture_catalog.extensions, "psd");

    asset.init_catalog(&texture_catalog, "Texture Catalog", register_texture, reload_texture);
}

register_texture :: proc(cat: ^asset.Catalog_Base, name: string, path: string) {
    texture     := new(Texture2d);
    texture.name = name;
    texture.path = path;
    texture.derived = texture^;

    cat := cast(^Texture_Catalog)cat;
    cat.assets[name] = texture;
    asset.asset_catalog.assets[name] = texture;
}

reload_texture :: proc(cat: ^asset.Catalog_Base, name: string, path: string, unload: bool) -> bool {
    cat := cast(^Texture_Catalog)cat;

    stbi.set_flip_vertically_on_load(1);

    cstring_path := strings.clone_to_cstring(path, context.temp_allocator);

    width, height, depth : i32;
    buffer := stbi.load(cstring_path, &width, &height, &depth, 0);
    if buffer == nil do return false;

    texture := cat.assets[name];

    texture.pixels = mem.slice_ptr(buffer, (int)(width * height * depth));
    texture.width  = int(width);
    texture.height = int(height);
    texture.depth  = int(depth);

    if !upload_texture(texture) {
        log.infof("[Asset] Failed to load texture \"{}\"", path);
        return false;
    }

    log.infof("[Asset] Loaded texture \"{}\"", path);

    return true;
}