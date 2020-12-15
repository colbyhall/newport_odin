#ifdef VERTEX

layout(location = 0) in vec3 position;
layout(location = 1) in vec2 normal;
layout(location = 2) in vec2 uv0;
layout(location = 3) in vec2 uv1;
layout(location = 4) in vec4 color;

uniform mat4 projection;
uniform mat4 view;

out vec4 frag_color;
out vec2 frag_uv0;
out vec2 frag_uv1;

void main() {
    gl_Position =  projection * view * vec4(position, 1.0);
    frag_color = color;
    frag_uv0 = uv0;
}

#endif
#ifdef FRAGMENT

out vec4 final_color;
in vec4 frag_color;
in vec2 frag_uv0;
in vec2 frag_uv1;

uniform sampler2D diffuse;

void main() {
    if (frag_uv0.x > -1.0) {
        vec4 sample = texture(diffuse, frag_uv0);
        final_color = sample;
    } else {
        final_color = frag_color;
    }
}

#endif