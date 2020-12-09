package graphics

// This package will alias the currently used api and building abstractions with the api

// This could later be switched with when statements or even a vtable
import api "gl"

clear :: api.clear;

Shader :: api.Shader;

compile_shader :: api.compile_shader;
set_shader     :: api.set_shader;
find_attribute :: api.find_attribute;
find_uniform   :: api.find_uniform;
set_uniform    :: api.set_uniform;

Texture :: api.Texture;

set_texture    :: api.set_texture;
upload_texture :: api.upload_texture;

init :: proc() {
    init_shader_catalog();
    init_texture_catalog();
}