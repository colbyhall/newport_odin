package gl

foreign import "system:opengl32.lib"

import "core:mem"
import "core:fmt"
import "core:log"

import "../../asset"
import "../../core"

GLenum      :: u32;
GLboolean   :: u8;
GLchar      :: u8;
GLbitfield  :: u32;
GLbyte      :: i8;
GLshort     :: i16;
GLint       :: i32;
GLsizei     :: i32;
GLubyte     :: u8;
GLushort    :: u16;
GLuint      :: u32;
GLfloat     :: f32;
GLclampf    :: f32;

GL_TRUE  :: 1;
GL_FALSE :: 0;

GL_UNSIGNED_BYTE :: 0x1401;
GL_FLOAT         :: 0x1406;
GL_FLOAT_MAT4    :: 0x8B5C;
GL_TRIANGLES     :: 0x0004;

GL_DEPTH_BUFFER_BIT     :: 0x100;
GL_STENCIL_BUFFER_BIT   :: 0x400;
GL_COLOR_BUFFER_BIT     :: 0x4000;

GL_FRAGMENT_SHADER :: 0x8B30;
GL_VERTEX_SHADER   :: 0x8B31;

GL_MAJOR_VERSION :: 0x821B;
GL_MINOR_VERSION :: 0x821C;

GL_LINK_STATUS       :: 0x8B82;
GL_ACTIVE_UNIFORMS   :: 0x8B86;
GL_ACTIVE_ATTRIBUTES :: 0x8B89;

GL_ARRAY_BUFFER :: 0x8892;
GL_LEQUAL       :: 0x0203;
GL_DEPTH_TEST   :: 0x0B71;
GL_CULL_FACE    :: 0x0B44;
GL_BACK         :: 0x0405;
GL_CCW          :: 0x0901;
GL_BLEND        :: 0x0BE2;
GL_SRC_ALPHA    :: 0x0302;
GL_ONE_MINUS_SRC_ALPHA :: 0x0303;

GL_STREAM_DRAW :: 0x88E0;

GL_TEXTURE_2D           :: 0x0DE1;
GL_NEAREST              :: 0x2600;
GL_LINEAR               :: 0x2601;
GL_TEXTURE_MAG_FILTER   :: 0x2800;
GL_TEXTURE_MIN_FILTER   :: 0x2801;
GL_TEXTURE_WRAP_S       :: 0x2802;
GL_TEXTURE_WRAP_T       :: 0x2803;
GL_TEXTURE0             :: 0x84C0;
GL_RED                  :: 0x1903;
GL_RGB                  :: 0x1907;
GL_RGBA                 :: 0x1908;
GL_SAMPLER_2D           :: 0x8B5E;
GL_FLOAT_VEC2           :: 0x8B50;

GL_VENDOR     :: 0x1F00;
GL_RENDERER   :: 0x1F01;
GL_VERSION    :: 0x1F02;
GL_EXTENSIONS :: 0x1F03;

GL_FRAMEBUFFER_SRGB :: 0x8DB9;
GL_SRGB_ALPHA       :: 0x8C42;
GL_MULTISAMPLE_ARB  :: 0x809D;

@(default_calling_convention = "c")
foreign opengl32 {
    glClear         :: proc(mask: GLbitfield) ---;
    glClearColor    :: proc(red: GLclampf, green: GLclampf, blue: GLclampf, alpha: GLclampf) ---;
    glGetIntegerv   :: proc(pname: GLenum, params: ^GLint) ---;
    glGetString     :: proc(name: GLenum) -> ^GLubyte ---;
    glViewport      :: proc(x: GLint, y: GLint, width: GLsizei, height: GLsizei) ---;
    glDepthMask     :: proc(flag: GLboolean) ---;
    glColorMask     :: proc(r, g, b, a: GLboolean) ---;
    glDepthFunc     :: proc(func: GLenum) ---;
    glEnable        :: proc(cap: GLenum) ---;
    // glClearDepthf :: proc(d: GLfloat) ---;
    glCullFace      :: proc(mode: GLenum) ---;
    glFrontFace     :: proc(mode: GLenum) ---;
    glBlendFunc     :: proc(sfactor: GLenum, dfactor: GLenum) ---;
    glDrawArrays    :: proc(mode: GLenum, first: GLint, count: GLsizei) ---;
    glGenTextures   :: proc(n: GLsizei, textures: ^GLint) ---;
    glBindTexture   :: proc(target: GLenum, texture: GLuint) ---;
    glTexParameteri :: proc(target: GLenum, pname: GLenum, param: GLint) ---;
    glTexImage2D    :: proc(target: GLenum, level: GLint, internalformat: GLint, width: GLsizei, height: GLsizei, border: GLint, format: GLenum, type: GLenum, pixels: ^u8) ---;
}

// This structure holds all opengl extensions that will be loaded in the os implementation
//
// @note Any procedure added to this struct is expected to be a gl function
GL_Functions :: struct {
    // Shader stuff
    glCreateProgram      : proc "c" () -> GLuint,
    glCreateShader       : proc "c" (shaderType: GLenum) -> GLuint,
    glShaderSource       : proc "c" (shader: GLuint, count: GLsizei, str: ^cstring, len: ^GLint),
    glCompileShader      : proc "c" (shader: GLuint),
    glAttachShader       : proc "c" (program: GLuint, shader: GLuint),
    glLinkProgram        : proc "c" (program: GLuint),
    glValidateProgram    : proc "c" (program: GLuint),
    glGetProgramiv       : proc "c" (program: GLuint, pname: GLenum, params: ^GLint),
    glDeleteShader       : proc "c" (shader: GLuint),
    glGetActiveAttrib    : proc "c" (program: GLuint, index: GLuint, bufSize: GLsizei, length: ^GLsizei, size: ^GLint, type: ^GLenum, name: cstring),
    glGetAttribLocation  : proc "c" (program: GLuint, name: cstring) -> GLint,
    glGetActiveUniform   : proc "c" (program: GLuint, index: GLuint, bufSize: GLsizei, length: ^GLsizei, size: ^GLint, type: ^GLenum, name: cstring),
    glGetUniformLocation : proc "c" (program: GLuint, name: cstring) -> GLint,
    glUseProgram         : proc "c" (program: GLuint),
    glGetProgramInfoLog  : proc "c" (program: GLuint, bufSize: GLsizei, length: ^GLsizei, infolog: ^GLchar),
    glGetShaderInfoLog   : proc "c" (shader: GLuint, bufSize: GLsizei, length: ^GLsizei, infolog: ^GLchar),
    glUniform1i          : proc "c" (location: GLint, v0: GLint),
    glUniform2f          : proc "c" (location: GLint, v0, v1: GLfloat),
    glUniformMatrix4fv   : proc "c" (loc: GLint, count: GLsizei, transpose: GLboolean, value: ^GLfloat),

    // VAO and VBO support
    glGenVertexArrays : proc "c" (n: GLsizei, arrays: ^GLuint),
    glBindVertexArray : proc "c" (array: GLuint),
    glGenBuffers      : proc "c" (n: GLsizei, buffers: ^GLuint),
    glBindBuffer      : proc "c" (target: GLenum, buffer: GLuint),
    glBufferData      : proc "c" (target: GLenum, size: u64, data: rawptr, usage: GLenum), // @Platform size should be usize
    glVertexAttribPointer       : proc "c" (index: GLuint, size: GLint, type: GLenum, normalized: GLboolean, stride: GLsizei, offset: u64), // offset is actually pointer in the standard. thought this would be easier. @Platform
    glEnableVertexAttribArray   : proc "c" (index: GLuint),

    glActiveTexture : proc "c" (texture: GLenum),
}

extensions : GL_Functions;

// Holds data on the current gl context
GL_Context :: struct {
    is_valid : bool

    maj_version : GLint,
    min_version : GLint,

    thread_id : int,

    bound_shader  : ^Shader,
    bound_texture : ^Texture,
}

// GL only allows 1 context at a time on a single thread
ctx : GL_Context;

_gl_check :: proc(loc := #caller_location) {
    if !ctx.is_valid {
        log.errorf("[OpenGL] To do work with GL a context must be created. GL work at {} on line {}", loc.file_path, loc.line);
        assert(false);
    }

    if ctx.thread_id != context.thread_id {
        log.errorf("[OpenGL] To do work with GL the work must be done on the same thread the context was intiialized on. GL work at {} on line {}", loc.file_path, loc.line);
        assert(false);
    }
}

clear :: proc(c: core.Linear_Color, loc := #caller_location) {
    _gl_check(loc);
    
    glClearColor(c.r, c.g, c.b, c.a);
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
}

Shader_Variable :: struct {
    name     : string,
    type     : GLenum,
    location : GLint,
}

// Wrapper structure around GL's shaders
// 
// @note contains data about uniforms and attributes
Shader :: struct {
    using _ : asset.Asset,

    id : GLuint,

    attributes : []Shader_Variable,
    uniforms   : []Shader_Variable,
}

// Compiles and uploads the shader to the gpu
//
// @returns true if the shader was compile and uploaded
compile_shader :: proc(using shader: ^Shader, source: cstring) -> bool {
    using extensions;

    _gl_check();

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
    using extensions;

    _gl_check(loc);

    if shader != nil {
        glUseProgram(shader.id);
        ctx.bound_shader = shader;
    } else {
        glUseProgram(0);
        ctx.bound_shader = nil;
    }
}

find_attribute :: proc(shader: ^Shader, name: string) -> ^Shader_Variable {
    for it, i in shader.attributes {
        if it.name == name do return &shader.attributes[i];
    }

    return nil;
}

find_uniform :: proc(shader: ^Shader, name: string, type: GLenum) -> ^Shader_Variable {
    for it, i in shader.uniforms {
        if it.name == name && it.type == type do return &shader.uniforms[i];
    }

    return nil;
}

_set_uniform :: proc(name: string, type: GLenum, loc := #caller_location) -> (bound: ^Shader, uniform: ^Shader_Variable) {
    _gl_check(loc);

    bound = ctx.bound_shader;
    if bound == nil {
        log.errorf("[OpenGL] Tried to uniform \"{}\" when no shader was bound in {} at line {}", name, loc.file_path, loc.line);
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
    using extensions;

    bound, uniform := _set_uniform(name, GL_FLOAT_MAT4, loc);
    if bound == nil || uniform == nil do return false;

    matrix := m;
    glUniformMatrix4fv(uniform.location, 1, GL_FALSE, &matrix[0][0]);
    return true;
}

set_uniform_tex :: proc(name: string, t: ^Texture, loc := #caller_location) -> bool {
    using extensions;

    bound, uniform := _set_uniform(name, GL_SAMPLER_2D, loc);
    if bound == nil || uniform == nil do return false;

    glActiveTexture(u32(GL_TEXTURE0 + uniform.location));
    set_texture(t);
    glUniform1i(uniform.location, uniform.location);

    return true;
}

set_uniform_vec2 :: proc(name: string, a: core.Vector2, loc := #caller_location) -> bool {
    using extensions;

    bound, uniform := _set_uniform(name, GL_FLOAT_VEC2, loc);
    if bound == nil || uniform == nil do return false;

    glUniform2f(uniform.location, a.x, a.y);
    return true;
}

set_uniform :: proc { set_uniform_mat4, set_uniform_tex, set_uniform_vec2 };

Texture :: struct {
    using _ : asset.Asset,

    id      : GLuint,
    pixels  : []u8,
    width   : int,
    height  : int,
    depth   : int, 
}

set_texture :: proc(texture: ^Texture, loc := #caller_location) {
    using extensions;

    _gl_check(loc);

    if texture == nil {
        glBindTexture(GL_TEXTURE_2D, 0);
        ctx.bound_texture = nil;
    } else {
        glBindTexture(GL_TEXTURE_2D, texture.id);
        ctx.bound_texture = texture;
    }
}

// TODO(colby): Handle all the different formatting info and such
upload_texture :: proc(texture: ^Texture) -> bool {
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
