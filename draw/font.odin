package draw

import "../asset"
import "../deps/stb/stbtt"
import "../gpu"
import "../core"

import "core:os"
import "core:mem"
import "core:fmt"
import "core:log"

Font_Collection :: struct {
    using asset : asset.Asset,

    info  : stbtt.Font_Info,
    fonts : map[f32]^Font,

    codepoint_indices : []i32,

    device : ^gpu.Device,
}

Font :: struct {
    size : f32,
    ascent, descent, line_gap : f32,

    glyphs : []Font_Glyph,
    atlas  : ^gpu.Texture,
    owner  : ^Font_Collection,
}

Font_Glyph :: struct {
    width  : f32,
    height : f32,

    bearing_x : f32,
    bearing_y : f32,
    advance   : f32,

    uv : core.Rect,
}

register_font_collection :: proc() {
    load :: proc(using fc: ^Font_Collection) -> bool {
        source, found := os.read_entire_file(path);
        if !found do return false;
        defer delete(source);

        file := make([]byte, len(source) + 1); // Leak
        copy(file, source);
        file[len(source)] = 0;

        if !stbtt.init_font(&info, file, stbtt.get_font_offset_for_index(file, 0)) do return false;

        codepoint_indices = make([]i32, int(fc.info.numGlyphs));

        for c := 0; c < 0x110000; c += 1 {
            i := stbtt.find_glyph_index(&fc.info, c);
            if i <= 0 do continue;
            codepoint_indices[i] = i32(c);
        }

        device = gpu.get().current;

        return true;
    }

    unload :: proc(using fc: ^Font_Collection) -> bool {
        // INCOMPLETE
        return true;
    }

    @static extensions := []string{
        "ttf",
    };

    asset.register(Font_Collection, extensions, auto_cast load, auto_cast unload);
}

font_at_size :: proc(using owner: ^Font_Collection, size: f32, dpi: f32 = 1) -> ^Font {
    result, found := fonts[size];
    if found do return result;

    ascent, descent, line_gap := stbtt.get_font_v_metrics(&info);
    scale := stbtt.scale_for_pixel_height(&info, size);

    BITMAP_SIZE :: 4096;
    atlas_bitmap := make_bitmap(u8, BITMAP_SIZE, BITMAP_SIZE);
    defer delete_bitmap(atlas_bitmap);

    oversample := 1;
    switch {
    case size <= 36: oversample = 2;
    case size <= 12: oversample = 4;
    case size <= 8:  oversample = 8;
    }

    spc, ok := stbtt.pack_begin(atlas_bitmap.pixels, atlas_bitmap.width, atlas_bitmap.height, 0, 1);
    assert(ok);

    stbtt.pack_set_skip_missing_codepoints(&spc, true);
    stbtt.pack_set_oversampling(&spc, oversample, oversample);
    
    packed_chars := make([]stbtt.Packed_Char, len(codepoint_indices)); // @Leak
    range := stbtt.Pack_Range{ 
        font_size = size,
        first_unicode_codepoint_in_range = 0,
        array_of_unicode_codepoints = &codepoint_indices[0],
        num_chars = i32(len(codepoint_indices)),
        chardata_for_range = &packed_chars[0],
    };
    ranges := [1]stbtt.Pack_Range{range};
    stbtt.pack_font_ranges(&spc, mem.slice_ptr(info.data, 1), 0, ranges[:]);

    // pack_end(&spc); LEAK 

    // SPEED!!!!!
    // HACK!!!!
    pixels := make([]u32, atlas_bitmap.width * atlas_bitmap.height);
    defer delete(pixels);
    for it, i in &pixels do it = u32(atlas_bitmap.pixels[i]);

    pixel_buffer := gpu.make_buffer(device, gpu.Buffer_Description{ 
        usage  = { .Transfer_Src }, 
        memory = .Host_Visible,
        size   = len(pixels) * 4,
    });
    gpu.copy_to_buffer(pixel_buffer, pixels);

    atlas := gpu.make_texture(device, gpu.Texture_Description{
        usage       = { .Transfer_Dst, .Sampled },
        memory_type = .Device_Local,
        
        format = .RGBA_U8,

        width  = atlas_bitmap.width,
        height = atlas_bitmap.height,
        depth  = 1,
    });

    gfx := gpu.make_graphics_context(device); // Leak
    {
        gpu.record(gfx);

        gpu.resource_barrier(gfx, atlas, .Undefined, .Transfer_Dst);
        gpu.copy(gfx, atlas, pixel_buffer);
        gpu.resource_barrier(gfx, atlas, .Transfer_Dst, .Shader_Read_Only);
    }

    gpu.submit(device, gfx);
    gpu.wait(device);// TODO: Use a fence here

    glyphs := make([]Font_Glyph, len(codepoint_indices));
    for it, i in &glyphs {
        pc := packed_chars[i];

        width := f32(pc.x1 - pc.x0) / f32(oversample);
        height := f32(pc.y1 - pc.y0) / f32(oversample);

        bearing_x := pc.xoff;
        bearing_y := pc.yoff;
        advance := pc.xadvance;

        uv0 := v2(f32(pc.x0) / f32(atlas.width), f32(pc.y1) / f32(atlas.height));
        uv1 := v2(f32(pc.x1) / f32(atlas.width), f32(pc.y0) / f32(atlas.height));
        
        it = Font_Glyph{ width, height, bearing_x, bearing_y, advance, Rect{ uv0, uv1 } };
    }

    font := new(Font);
    font^ = Font{
        size     = size,
        ascent   = f32(ascent) * scale,
        descent  = f32(descent) * scale,
        line_gap = f32(line_gap) * scale,

        glyphs   = glyphs,
        atlas    = atlas,
        owner    = owner,
    };

    fonts[size] = font;

    return font;
}
