#ifdef VERTEX

layout(location = 0) in vec3 position;
layout(location = 1) in vec3 normal;
layout(location = 2) in vec2 uv;
layout(location = 3) in vec4 color;

uniform mat4 projection;
uniform mat4 view;

out vec4 frag_color;
out vec2 frag_uv;

void main() {
    gl_Position =  projection * view * vec4(position, 1.0);
    frag_color = color;
    frag_uv = uv;
}

#endif
#ifdef FRAGMENT

out vec4 final_color;
in vec4 frag_color;
in vec2 frag_uv;

uniform sampler2D atlas;

void main() {
    vec4 sample = texture(atlas, frag_uv);
    final_color = vec4(frag_color.xyz, sample.r);
}

#endif