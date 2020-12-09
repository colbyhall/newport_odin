package graphics

// This is the graphics api implementation for opengl
// As I add more graphics api's this will change but 
// this will not compile while doing other apis

import "gl"

import "../asset"
import "../core"

import "core:log"
import "core:mem"

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
    using gl;
    using extensions;

    check(loc);

    if shader != nil {
        glUseProgram(shader.id);
        // ctx.bound_shader = shader;
    } else {
        glUseProgram(0);
        // ctx.bound_shader = nil;
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

    check(loc);

    bound = nil; // ctx.bound_shader;
    if bound == nil {
        log.errorf("[OpenGL] Tried to find uniform \"{}\" when no shader was bound in {} at line {}", name, loc.file_path, loc.line);
        return;
    }

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

set_uniform_tex :: proc(name: string, t: ^Texture, loc := #caller_location) -> bool {
    using gl;
    using extensions;

    bound, uniform := _set_uniform(name, GL_SAMPLER_2D, loc);
    if bound == nil || uniform == nil do return false;

    glActiveTexture(u32(GL_TEXTURE0 + uniform.location));
    set_texture(t);
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

set_uniform :: proc { set_uniform_mat4, set_uniform_tex, set_uniform_vec2 };

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

begin_pipeline :: proc(id: Pipeline_Id, loc := #caller_location) {
    check(loc);
    using state; 

    using gl;
    using extensions;

    pipeline, ok := pipeline_manager.pipelines[id];
    if !ok {
        log.errorf("[Graphics] Failed to find pipeline with id of {} from {} {}", id, loc.file_path, file.line);
        return;
    }

    viewport := pipeline.viewport;
    glViewport(viewport.min.x, viewport.min.y, viewport.max.x, viewport.max.y);
    // TODO(colby): Scissor test

    draw_mode : GLenum;
    switch pipeline.draw_mode {
    case .Fill:  draw_mode = GL_FILL;
    case .Line:  draw_mode = GL_LINE;
    case .Point: draw_mode = GL_POINT;
    }
    glPolygonMode(GL_FRONT_AND_BACK, draw_mode);

    // front_cull := 
}

end_pipeline :: proc(loc := #caller_location) {
    // Do nothing because this is opengl son
}

Texture :: struct {
    using _ : asset.Asset,

    id      : gl.GLuint,
    pixels  : []u8,
    width   : int,
    height  : int,
    depth   : int, 
}

set_texture :: proc(texture: ^Texture, loc := #caller_location) {
    using gl;
    using extensions;

    check(loc);

    if texture == nil {
        glBindTexture(GL_TEXTURE_2D, 0);
        // ctx.bound_texture = nil;
    } else {
        glBindTexture(GL_TEXTURE_2D, texture.id);
        // ctx.bound_texture = texture;
    }
}

// TODO(colby): Handle all the different formatting info and such
upload_texture :: proc(texture: ^Texture) -> bool {
    using gl;
    using extensions;

    if texture.id == 0 do glGenTextures(1, auto_cast &texture.id);

    set_texture(texture);
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
