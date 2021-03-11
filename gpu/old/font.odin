package graphics

import "../asset"
import "../deps/stb/stbtt"
import "../core"

import "core:os"
import "core:mem"
import "core:fmt"

Font_Collection :: struct {
    using asset : asset.Asset,

    info  : stbtt.Font_Info,
    fonts : map[f32]Font,

    codepoint_indices : []i32,
}

Font :: struct {
    size : f32,
    ascent, descent, line_gap : f32,

    glyphs : []Font_Glyph,
    atlas  : Texture2d,
    owner  : ^Font_Collection,
}

Font_Glyph :: struct {
    width, height : f32,
    bearing_x, bearing_y : f32,
    advance : f32,
    uv : Rect,
}

Font_Collection_Catalog :: asset.Catalog(Font_Collection);
font_collection_catalog: Font_Collection_Catalog;

init_font_collection_catalog :: proc() {
    append(&font_collection_catalog.extensions, "ttf");

    asset.init_catalog(&font_collection_catalog, "Font Collection Catalog", register_font_collection, reload_font_collection);
}

register_font_collection :: proc(cat: ^asset.Catalog_Base, name: string, path: string) {
    fc         := new(Font_Collection);
    fc.name    = name;
    fc.path    = path;
    fc.derived = fc^;

    cat := cast(^Font_Collection_Catalog)cat;
    cat.assets[name] = fc;
    asset.asset_catalog.assets[name] = fc;
}

reload_font_collection :: proc(cat: ^asset.Catalog_Base, name: string, path: string, unload: bool) -> bool {
    cat := cast(^Font_Collection_Catalog)cat;

    using os;
    using stbtt;

    source, found := read_entire_file(path);
    if !found do return false;
    defer delete(source);

    file := make([]byte, len(source) + 1);
    copy(file, source);
    file[len(source)] = 0;

    fc := cat.assets[name];

    if !init_font(&fc.info, file, get_font_offset_for_index(file, 0)) do return false;

    fc.codepoint_indices = make([]i32, int(fc.info.numGlyphs));

    for c := 0; c < 0x110000; c += 1 {
        i := find_glyph_index(&fc.info, c);
        if i <= 0 do continue;
        fc.codepoint_indices[i] = i32(c);
    }

    return true;
}

font_at_size :: proc(using collection: ^Font_Collection, size: f32) -> Font {
    result, found := fonts[size];
    if found do return result;

    using stbtt;

    ascent, descent, line_gap := get_font_v_metrics(&info);
    scale := scale_for_pixel_height(&info, size);

    font : Font;

    font.size  = size;
    font.owner = collection;

    font.ascent   = f32(ascent) * scale;
    font.descent  = f32(descent) * scale;
    font.line_gap = f32(line_gap) * scale;

    ATLAS_SIZE :: 4096; // @TODO(colby): Properly calculate this
    atlas := &font.atlas;
    atlas.width  = ATLAS_SIZE; 
    atlas.height = ATLAS_SIZE;
    atlas.depth  = 1;
    atlas.pixels = make([]u32, atlas.width * atlas.height); // @Leak

    oversample := 1;
    switch {
    case size <= 36: oversample = 2;
    case size <= 12: oversample = 4;
    case size <= 8:  oversample = 8;
    }

    spc, _ := pack_begin(atlas.pixels, atlas.width, atlas.height, 0, 1);
    
    pack_set_skip_missing_codepoints(&spc, true);
    pack_set_oversampling(&spc, oversample, oversample);

    packed_chars := make([]Packed_Char, len(codepoint_indices)); // @Leak
    range := Pack_Range{ 
        font_size = size,
        first_unicode_codepoint_in_range = 0,
        array_of_unicode_codepoints = &codepoint_indices[0],
        num_chars = i32(len(codepoint_indices)),
        chardata_for_range = &packed_chars[0],
    };
    ranges := [1]Pack_Range{range};
    pack_font_ranges(&spc, mem.slice_ptr(info.data, 1), 0, ranges[:]);

    // pack_end(&spc); @LEAK @LEAK

    upload_texture(atlas);

    font.glyphs = make([]Font_Glyph, len(codepoint_indices));
    for _, i in font.glyphs {
        pc := packed_chars[i];

        width := f32(pc.x1 - pc.x0) / f32(oversample);
        height := f32(pc.y1 - pc.y0) / f32(oversample);

        bearing_x := pc.xoff;
        bearing_y := pc.yoff;
        advance := pc.xadvance;

        uv0 := v2(f32(pc.x0) / f32(atlas.width), f32(pc.y1) / f32(atlas.height));
        uv1 := v2(f32(pc.x1) / f32(atlas.width), f32(pc.y0) / f32(atlas.height));
        
        font.glyphs[i] = Font_Glyph{ width, height, bearing_x, bearing_y, advance, Rect{ uv0, uv1 } };
    }

    fonts[size] = font;
    return fonts[size];
}

glyph_from_rune :: proc(using font: Font, r: rune) -> (Font_Glyph, bool) {
    i := stbtt.find_glyph_index(&owner.info, int(r));
    if i > 0 {
        assert(i < len(glyphs));
        return glyphs[i], true;
    }

    return Font_Glyph{}, false;
}
