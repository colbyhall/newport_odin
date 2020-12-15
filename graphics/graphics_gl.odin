package graphics

// This is the graphics api implementation for opengl
// As I add more graphics api's this will change but 
// this will not compile while doing other apis

import "gl"

import "../asset"
import "../core"

import "core:log"
import "core:mem"
import "core:runtime"

clear :: proc(c: core.Linear_Color, loc := #caller_location) {
    gl.check(loc);
    
    gl.glClearColor(c.r, c.g, c.b, c.a);
    gl.glClear(gl.GL_COLOR_BUFFER_BIT | gl.GL_DEPTH_BUFFER_BIT | gl.GL_STENCIL_BUFFER_BIT);
}

Shader_Variable :: struct {
    name     : string,
    type     : gl.GLenum,
    location : gl.GLint,
}

// Wrapper structure around GL's shaders
// 
// @note contains data about uniforms and attributes
Shader :: struct {
    using _ : asset.Asset,

    id : gl.GLuint,

    attributes : []Shader_Variable,
    uniforms   : []Shader_Variable,
}

// Compiles and uploads the shader to the gpu
//
// @returns true if the shader was compile and uploaded
compile_shader :: proc(using shader: ^Shader, source: cstring) -> bool {
    using gl;
    using extensions;

    check();

    if source == nil {
        log.error("Tried to compile shader with no source given");
        return false;
    }
    
    id = glCreateProgram();

    vert_id := glCreateShader(GL_VERTEX_SHADER);
    defer glDeleteShader(vert_id);

    frag_id := glCreateShader(GL_FRAGMENT_SHADER);
    defer glDeleteShader(frag_id);

    // This allows us to pack vert and frag shaders in a single file
    shader_header : cstring = "#version 330 core\n#extension GL_ARB_seperate_shader_objects: enable\n";
    vert_shader   := []cstring { shader_header, "#define VERTEX 1\n", source };
    frag_shader   := []cstring { shader_header, "#define FRAGMENT 1\n", source };

    glShaderSource(vert_id, 3, &vert_shader[0], nil);
    glShaderSource(frag_id, 3, &frag_shader[0], nil);

    glCompileShader(vert_id);
    glCompileShader(frag_id);

    glAttachShader(id, vert_id);
    glAttachShader(id, frag_id);

    glLinkProgram(id);
    glValidateProgram(id);

    is_linked : GLint;
    glGetProgramiv(id, GL_LINK_STATUS, &is_linked);
    if is_linked == 0 {
        ignore : GLsizei;
        vert_errors : [4096]u8;
        frag_errors : [4096]u8;
        prog_errors : [4096]u8;

        glGetShaderInfoLog(vert_id, 4096, &ignore, &vert_errors[0]);
        glGetShaderInfoLog(frag_id, 4096, &ignore, &frag_errors[0]);
        glGetProgramInfoLog(id, 4096, &ignore, &prog_errors[0]);

        log.error("[OpenGL] Shader compile failed");

        if vert_errors[0] != 0 do log.error(cstring(&vert_errors[0]));
        if frag_errors[0] != 0 do log.error(cstring(&frag_errors[0]));
        if prog_errors[0] != 0 do log.error(cstring(&prog_errors[0]));

        return false;
    }

    // Gather up all the shaders attributes
    num_attributes : GLint;
    glGetProgramiv(id, GL_ACTIVE_ATTRIBUTES, &num_attributes);
    attributes = make([]Shader_Variable, int(num_attributes));
    for i in 0..<num_attributes {
        length : GLsizei;
        size   : GLint;
        type   : GLenum;
        name   : [1024]u8;
        glGetActiveAttrib(id, auto_cast i, 1024, &length, &size, &type, auto_cast &name[0]);

        attrib := &attributes[i];

        name_len := len(cstring(&name[0]));
        buffer := make([]byte, name_len + 1);
        mem.copy(raw_data(buffer[:]), raw_data(name[:]), name_len);
        buffer[name_len] = 0;

        attrib.name     = string(buffer[:name_len]);
        attrib.type     = type;
        attrib.location = glGetAttribLocation(id, auto_cast &name[0]);
    }

    // Gather up all the shaders uniforms
    num_uniforms : GLint;
    glGetProgramiv(id, GL_ACTIVE_UNIFORMS, &num_uniforms);
    uniforms = make([]Shader_Variable, int(num_attributes));
    for i in 0..<num_uniforms {
        length : GLsizei;
        size   : GLint;
        type   : GLenum;
        name   : [1024]u8;
        glGetActiveUniform(id, auto_cast i, 1024, &length, &size, &type, auto_cast &name[0]);

        uniform := &uniforms[i];

        name_len := len(cstring(&name[0]));
        buffer := make([]byte, name_len + 1);
        mem.copy(raw_data(buffer[:]), raw_data(name[:]), name_len);
        buffer[name_len] = 0;

        uniform.name     = string(buffer[:name_len]);
        uniform.type     = type;
        uniform.location = glGetUniformLocation(id, auto_cast &name[0]);
    }

    return true;
}


// Sets the shader and updates our gl context
set_shader :: proc(shader: ^Shader, loc := #caller_location) {
    gl.check(loc);
    using gl;
    using extensions;

    check(loc);

    if shader != nil {
        glUseProgram(shader.id);
    } else {
        glUseProgram(0);
    }
}

find_attribute :: proc(shader: ^Shader, name: string) -> ^Shader_Variable {
    for it, i in shader.attributes {
        if it.name == name do return &shader.attributes[i];
    }

    return nil;
}

find_uniform :: proc(shader: ^Shader, name: string, type: gl.GLenum) -> ^Shader_Variable {
    for it, i in shader.uniforms {
        if it.name == name && it.type == type do return &shader.uniforms[i];
    }

    return nil;
}

_set_uniform :: proc(name: string, type: gl.GLenum, loc := #caller_location) -> (bound: ^Shader, uniform: ^Shader_Variable) {
    using gl;
    using state;

    check(loc);

    pipeline, ok := pipeline_manager.pipelines[pipeline_manager.active];
    if !ok {
        log.errorf("[OpenGL] Tried to find uniform \"{}\" when no pipeline was bound in {} at line {}", name, loc.file_path, loc.line);
        return;
    }

    bound = pipeline.details.shader;

    uniform = find_uniform(bound, name, type);
    if uniform == nil {
        log.errorf("[OpenGL] Could not find uniform \"{}\" in shader {} called in {} at line {}", name, bound.name, loc.file_path, loc.line);
        return;
    }

    return;
}

set_uniform_mat4 :: proc(name: string, m: core.Matrix4, loc := #caller_location) -> bool {
    using gl;
    using extensions;

    bound, uniform := _set_uniform(name, GL_FLOAT_MAT4, loc);
    if bound == nil || uniform == nil do return false;

    matrix := m;
    glUniformMatrix4fv(uniform.location, 1, GL_FALSE, &matrix[0][0]);
    return true;
}

set_uniform_texture2d :: proc(name: string, t: ^Texture2d, loc := #caller_location) -> bool {
    using gl;
    using extensions;

    bound, uniform := _set_uniform(name, GL_SAMPLER_2D, loc);
    if bound == nil || uniform == nil do return false;

    glActiveTexture(u32(GL_TEXTURE0 + uniform.location));
    set_texture2d(t);
    glUniform1i(uniform.location, uniform.location);

    return true;
}

set_uniform_vec2 :: proc(name: string, a: core.Vector2, loc := #caller_location) -> bool {
    using gl;
    using extensions;

    bound, uniform := _set_uniform(name, GL_FLOAT_VEC2, loc);
    if bound == nil || uniform == nil do return false;

    glUniform2f(uniform.location, a.x, a.y);
    return true;
}

set_uniform :: proc { set_uniform_mat4, set_uniform_texture2d, set_uniform_vec2 };

// Pipeline structure which is used to set pipeline state
//
// @see begin_pipeline
// @note This structure is here for easier api design with vulkan and such
Pipeline :: struct {
    details : Pipeline_Details,
}

make_pipeline :: proc(details: Pipeline_Details, loc := #caller_location) -> Pipeline_Id {
    pipeline := Pipeline{ details };
    return _add_pipeline(pipeline, loc);
}

delete_pipeline :: proc(id: Pipeline_Id, loc := #caller_location) -> bool {
    _, found := _remove_pipeline(id, loc);
    return found;
}

begin_pipeline :: proc(id: Pipeline_Id, uniforms: Uniform_Map, loc := #caller_location) {
    check(loc);
    gl.check(loc);
    using state; 

    using gl;
    using extensions;

    pipeline, ok := pipeline_manager.pipelines[id];
    if !ok {
        log.errorf("[Graphics] Failed to find pipeline with id of {} from {} {}", id, loc.file_path, loc.line);
        return;
    }

    if pipeline.details.shader == nil {
        log.errorf("[Graphics] Failed to start pipeline with id of {} due to it not having a set shader. Called from {} {}", id, loc.file_path, loc.line);
        return;   
    }

    details := pipeline.details;

    viewport := details.viewport;
    glViewport(auto_cast viewport.min.x, auto_cast viewport.min.y, auto_cast viewport.max.x, auto_cast viewport.max.y);
    // TODO(colby): Scissor test

    // Set the gl draw mode
    draw_mode : GLenum;
    switch details.draw_mode {
    case .Fill:  draw_mode = GL_FILL;
    case .Line:  draw_mode = GL_LINE;
    case .Point: draw_mode = GL_POINT;
    }
    glPolygonMode(GL_FRONT_AND_BACK, draw_mode);

    // Update the line width
    glLineWidth(details.line_width);

    // Set the gl cull mode
    front_cull := .Front in details.cull_mode;
    back_cull  := .Back in details.cull_mode;
    cull_mode : GLenum;

    if front_cull && back_cull do cull_mode = GL_FRONT_AND_BACK;
    else if front_cull do cull_mode = GL_FRONT;
    else if back_cull do cull_mode = GL_BACK;

    if cull_mode == 0 do glDisable(GL_CULL_FACE);
    else {
        glEnable(GL_CULL_FACE);
        glCullFace(cull_mode);
    }

    // Set the color mask
    color_mask := details.color_mask;
    mask_r := .Red in color_mask;
    mask_g := .Green in color_mask;
    mask_b := .Blue in color_mask;
    mask_a := .Alpha in color_mask;
    glColorMask(auto_cast mask_r, auto_cast mask_g, auto_cast mask_b, auto_cast mask_a);

    // Set up all the blending
    if details.blend_enabled {
        glEnable(GL_BLEND);

        blend_factor_to_gl :: proc(factor: Blend_Factor) -> GLenum {
            switch factor {
            case .Zero: return GL_ZERO;
            case .One:  return GL_ONE;
            case .Src_Color: return GL_SRC_COLOR;
            case .Dst_Color: return GL_DST_COLOR;
            case .Src_Alpha: return GL_SRC_ALPHA;
            case .One_Minus_Src_Color: return GL_ONE_MINUS_SRC_COLOR;
            case .One_Minus_Dst_Color: return GL_ONE_MINUS_DST_COLOR;
            case .One_Minus_Src_Alpha: return GL_ONE_MINUS_SRC_ALPHA;
            }
            return 0;
        }

        // TODO(colby): Do the blend ops
        glBlendFunc(GL_SRC_COLOR, blend_factor_to_gl(details.src_color_blend_factor));
        glBlendFunc(GL_DST_COLOR, blend_factor_to_gl(details.dst_color_blend_factor));

        glBlendFunc(GL_SRC_ALPHA, blend_factor_to_gl(details.src_alpha_blend_factor));
        glBlendFunc(GL_DST_ALPHA, blend_factor_to_gl(details.dst_alpha_blend_factor));
    } else {
        glDisable(GL_BLEND);
    }

    // Setup the depth testing and blend functions
    if details.depth_test {
        glEnable(GL_DEPTH_TEST);

        func : GLenum;
        switch details.depth_compare {
        case .Never: func = GL_NEVER;
        case .Less:  func = GL_LESS;
        case .Equal: func = GL_EQUAL;
        case .Greater: func = GL_GREATER;
        case .Not_Equal: func = GL_NOTEQUAL;
        case .Always: func = GL_ALWAYS;

        case .Less_Or_Equal: func = GL_LEQUAL;
        case .Greater_Or_Equal: func = GL_GEQUAL;
        }

        glDepthFunc(func);
    } else do glDisable(GL_DEPTH_TEST);

    // Set the depth mask
    depth_mask : GLboolean = GL_FALSE;
    if details.depth_write do depth_mask = GL_TRUE;
    glDepthMask(depth_mask);

    set_shader(details.shader);

    for key, value in uniforms {
        #partial switch u in value {
        case Matrix4:   set_uniform(key, u, loc);
        case ^Texture2d: set_uniform(key, u, loc);
        }
    }

    // Setup the vertex attrib info
    // TODO(colby): Do all vertex attrb in graphics.odin
    // TODO(colby): Check if info is allowed


    vertex_base_info := runtime.type_info_base(type_info_of(details.vertex));
    vertex_struct_info := vertex_base_info.variant.(runtime.Type_Info_Struct);
    vertex_size := GLsizei(vertex_base_info.size);

    for type, i in vertex_struct_info.types {
        offset := u64(vertex_struct_info.offsets[i]);

        found := false;
        for it in details.shader.attributes {
            if it.name == vertex_struct_info.names[i] do found = true;
        }
        if !found do continue;

        switch type.id {
        case Vector2:      glVertexAttribPointer(auto_cast i, 2, GL_FLOAT, GL_FALSE, vertex_size, offset);
        case Vector3:      glVertexAttribPointer(auto_cast i, 3, GL_FLOAT, GL_FALSE, vertex_size, offset);
        case Vector4:      glVertexAttribPointer(auto_cast i, 4, GL_FLOAT, GL_FALSE, vertex_size, offset);
        case Linear_Color: glVertexAttribPointer(auto_cast i, 4, GL_FLOAT, GL_FALSE, vertex_size, offset);
        }

        glEnableVertexAttribArray(auto_cast i);
    }
}

end_pipeline :: proc(loc := #caller_location) {
    // Do nothing because this is opengl son
}

Texture2d :: struct {
    using _ : asset.Asset,

    id      : gl.GLuint,
    pixels  : []u8,
    width   : int,
    height  : int,
    depth   : int, 
}

set_texture2d :: proc(texture: ^Texture2d, loc := #caller_location) {
    gl.check(loc);
    check(loc);

    using gl;
    using extensions;

    if texture == nil do glBindTexture(GL_TEXTURE_2D, 0);
    else do glBindTexture(GL_TEXTURE_2D, texture.id);
}

// TODO(colby): Handle all the different formatting info and such
upload_texture :: proc(texture: ^Texture2d) -> bool {
    using gl;
    using extensions;

    if texture.id == 0 do glGenTextures(1, auto_cast &texture.id);

    set_texture2d(texture);
    using texture;

    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);

    format : i32;
    switch depth {
    case 1:
        format = GL_RED;
    case 3:
        format = GL_RGB;
    case 4:
        format = GL_RGBA;
    case: 
        panic("Unreachable");
    }

    a := format;
    // if depth == 4 do a = GL_SRGB_ALPHA;

    glTexImage2D(GL_TEXTURE_2D, 0, auto_cast a, auto_cast width, auto_cast height, 0, auto_cast format, GL_UNSIGNED_BYTE, &pixels[0]);
    return true;
}

/*
Framebuffer :: struct {
    id       : gl.GLuint,
    
    colors   : [Framebuffer_Colors_Index.Count]Texture2d,
    depth    : Texture2d,

    width    : int,
    height   : int,
    flags    : bit_set[Framebuffer_Flags],
}

make_framebuffer :: proc(width, height: int, flags: bit_set[Framebuffer_Flags], loc := #caller_location) -> (fb: Framebuffer, ok: bool) {
    gl.check(loc);
    check(loc);

    using gl;
    using extensions;

    id : GLuint;
    glGenFramebuffers(1, &id);
    glBindFramebuffer(GL_FRAMEBUFFER, id);

    fb.id     = id;
    fb.width  = width;
    fb.height = height;
    fb.flags  = flags;

    if .Albedo in flags && .HDR in flags {
        log.errorf("[Graphics] Created a framebuffer with HDR and Albedo buffer. This is impossible. In {} at {}", loc.file_path, loc.line);
        assert(false);
    }

    if .Position in flags {
        position_texture : GLuint;
        glGenTextures(1, &position_texture);
        glBindTexture(GL_TEXTURE_2D, position_texture);
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA16F, width, height, 0, GL_RGBA, GL_FLOAT, 0);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
        glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0 + FCI_Position, GL_TEXTURE_2D, position_texture, 0);
        fb.color[Framebuffer_Colors_Index.Position] = Texture2d {  
            width  = width, 
            height = height, 
            depth  = 4, 
            id     = position_texture,
        };
    }

    if ((flags & FF_Normal) != 0) {
        GLuint normal_texture;
        glGenTextures(1, &normal_texture);
        glBindTexture(GL_TEXTURE_2D, normal_texture);
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA16F, width, height, 0, GL_RGBA, GL_FLOAT, 0);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
        glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0 + FCI_Normal, GL_TEXTURE_2D, normal_texture, 0);
        result.color[FCI_Normal] = (Texture2d) {  
            .width  = width, 
            .height = height, 
            .depth  = 4, 
            .id     = normal_texture,
        };
    }


    if ((flags & FF_Depth) != 0) {
        GLuint depth_texture;
        glGenTextures(1, &depth_texture);
        glBindTexture(GL_TEXTURE_2D, depth_texture);
        glTexImage2D(GL_TEXTURE_2D, 0, GL_DEPTH_COMPONENT16, width, height, 0, GL_DEPTH_COMPONENT, GL_UNSIGNED_SHORT, 0);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_COMPARE_FUNC, GL_LEQUAL);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_COMPARE_MODE, GL_COMPARE_R_TO_TEXTURE);
        glFramebufferTexture2D(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_TEXTURE_2D, depth_texture, 0);
        result.depth = (Texture2d) {  
            .width  = width, 
            .height = height, 
            .depth  = 1, 
            .id     = depth_texture,
        };
    }

    if ((flags & FF_Albedo) != 0) {
        GLuint albedo_texture;
        glGenTextures(1, &albedo_texture);
        glBindTexture(GL_TEXTURE_2D, albedo_texture);
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, width, height, 0, GL_RGBA, GL_UNSIGNED_BYTE, 0);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
        glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0 + FCI_Albedo, GL_TEXTURE_2D, albedo_texture, 0);
        result.color[FCI_Albedo] = (Texture2d) {  
            .width = width, 
            .height = height, 
            .depth = 4, 
            .id = albedo_texture,
        };
    }

    if ((flags & FF_HDR) != 0) {
        GLuint hdr_texture;
        glGenTextures(1, &hdr_texture);
        glBindTexture(GL_TEXTURE_2D, hdr_texture);
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA16F, width, height, 0, GL_RGBA, GL_FLOAT, 0);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
        glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0 + FCI_HDR, GL_TEXTURE_2D, hdr_texture, 0);
        result.color[FCI_HDR] = (Texture2d) {
            .width  = width,
            .height = height,
            .depth  = 4,
            .id     = hdr_texture,
        };
    }

    return;
}
*/

Vertex_Buffer :: struct(Vertex: typeid) {
    vao, vbo, vio : gl.GLuint,

    vertices : []Vertex,
    indices  : []u32,
}

make_vertex_buffer :: proc($Vertex: typeid, has_indices := true, loc := #caller_location) -> Vertex_Buffer(Vertex) {
    gl.check(loc);
    check(loc);

    using gl;
    using extensions;

    vao, vbo, vio: GLuint;
    glGenVertexArrays(1, &vao);
    // glBindVertexArray(vao);

    glGenBuffers(1, &vbo);
    // glBindBuffer(GL_ARRAY_BUFFER, vbo);

    glGenBuffers(1, &vio);
    // glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, vio);

    return Vertex_Buffer(Vertex){ vao = vao, vbo = vbo, vio = vio };
}

upload_vertex_buffer :: proc(vb: ^Vertex_Buffer($Vertex), vertices: []Vertex, indices: []u32, loc := #caller_location) {
    gl.check(loc);
    check(loc);

    using gl;
    using extensions;

    glBindVertexArray(vb.vao);

    glBindBuffer(GL_ARRAY_BUFFER, vb.vbo);
    glBufferData(GL_ARRAY_BUFFER, auto_cast (size_of(Vertex) * len(vertices)), &vertices[0], GL_STREAM_DRAW);

    vb.vertices = vertices;

    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, vb.vio);
    glBufferData(GL_ELEMENT_ARRAY_BUFFER, auto_cast (size_of(u32) * len(indices)), &indices[0], GL_STREAM_DRAW);

    vb.indices = indices;
}

draw_vertex_buffer :: proc(using vb: ^Vertex_Buffer($Vertex), loc := #caller_location) {
    if len(vertices) == 0 do return;

    gl.check(loc);
    check(loc);

    using gl;
    using extensions;

    glBindVertexArray(vao);
    glBindBuffer(GL_ARRAY_BUFFER, vbo);
    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, vio);

    if len(indices) > 0 do glDrawElements(GL_TRIANGLES, auto_cast len(indices), GL_UNSIGNED_INT, nil);
    else do glDrawArrays(GL_TRIANGLES, 0, auto_cast len(vertices));
}