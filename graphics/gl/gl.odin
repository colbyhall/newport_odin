package gl

foreign import "system:opengl32.lib"

import "core:mem"
import "core:fmt"
import "core:log"

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
GL_UNSIGNED_INT  :: 0x1405;
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
GL_DEPTH_TEST   :: 0x0B71;
GL_CULL_FACE    :: 0x0B44;
GL_CCW          :: 0x0901;

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

GL_FRONT            :: 0x0404;
GL_BACK             :: 0x0405;
GL_FRONT_AND_BACK   :: 0x0408;

GL_POINT :: 0x1B00;
GL_LINE  :: 0x1B01;
GL_FILL  :: 0x1B02;

GL_BLEND :: 0x0BE2;
GL_BLEND_SRC :: 0x0BE1;
GL_BLEND_DST :: 0x0BE0;
GL_ZERO :: 0;
GL_ONE :: 1;
GL_SRC_COLOR :: 0x0300;
GL_ONE_MINUS_SRC_COLOR :: 0x0301;
GL_SRC_ALPHA :: 0x0302;
GL_ONE_MINUS_SRC_ALPHA :: 0x0303;
GL_DST_ALPHA :: 0x0304;
GL_ONE_MINUS_DST_ALPHA :: 0x0305;
GL_DST_COLOR :: 0x0306;
GL_ONE_MINUS_DST_COLOR :: 0x0307;
GL_SRC_ALPHA_SATURATE :: 0x0308;

GL_NEVER :: 0x0200;
GL_LESS :: 0x0201;
GL_EQUAL :: 0x0202;
GL_LEQUAL :: 0x0203;
GL_GREATER :: 0x0204;
GL_NOTEQUAL :: 0x0205;
GL_GEQUAL :: 0x0206;
GL_ALWAYS :: 0x0207;

GL_ELEMENT_ARRAY_BUFFER :: 0x8893;

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
    glDisable       :: proc(cap: GLenum) ---;
    glPolygonMode   :: proc(face, mode: GLenum) ---;
    glLineWidth     :: proc(width: GLfloat) ---;
    // glClearDepthf :: proc(d: GLfloat) ---;
    glCullFace      :: proc(mode: GLenum) ---;
    glFrontFace     :: proc(mode: GLenum) ---;
    glBlendFunc     :: proc(sfactor: GLenum, dfactor: GLenum) ---;
    glDrawArrays    :: proc(mode: GLenum, first: GLint, count: GLsizei) ---;
    glDrawElements  :: proc(mode: GLenum, count: GLsizei, type: GLenum, indices: rawptr) ---;
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
}

// GL only allows 1 context at a time on a single thread
ctx : GL_Context;

check :: proc(loc := #caller_location) {
    if !ctx.is_valid {
        log.errorf("[OpenGL] To do work with GL a context must be created. GL work at {} on line {}", loc.file_path, loc.line);
        assert(false);
    }

    if ctx.thread_id != context.thread_id {
        log.errorf("[OpenGL] To do work with GL the work must be done on the same thread the context was intiialized on. GL work at {} on line {}", loc.file_path, loc.line);
        assert(false);
    }
}