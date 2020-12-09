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

uniform sampler2D diffuse;

void main() {
    if (frag_uv.x > -1.0) {
        vec4 sample = texture(diffuse, frag_uv);
        final_color = sample;
    } else {
        final_color = frag_color;
    }
}

#endif