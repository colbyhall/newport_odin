package test

import "newport:core"
import "newport:engine"
import "newport:asset"
import "newport:job"
import "newport:gpu"

import "core:encoding/json"
import "core:os"
import "core:fmt"
import "core:math/linalg"

Vector3 :: core.Vector3;
Linear_Color :: core.Linear_Color;
v2 :: core.v2;
v3 :: core.v3;
dot :: core.dot;
cross :: core.cross;
norm :: core.norm;
length :: core.length;
Matrix4 :: core.Matrix4;
MATRIX4_IDENTITY :: core.MATRIX4_IDENTITY;
Rect :: core.Rect;
rect_pos_size :: core.rect_pos_size;
ortho :: core.ortho;
translate :: linalg.matrix4_translate;

// ax + bx + dx = w
Plane :: core.Vector4;

plane_dot :: proc(a: Plane, b: Vector3) -> f32 {
    return a.x * b.x + a.y * b.y + a.z * b.z - a.w;
}

ray_plane_intersection :: proc(origin, dir: Vector3, p: Plane) -> (impact: Vector3, hit: bool) {
    pn := v3(p.x, p.y, p.z);
    pd := plane_dot(p, origin);

    if pd > 1e-6 {
        hit = dot(pn, dir) < 0;
        if hit do impact = origin + dir * pd;
        return;
    }

    hit = true;
    impact = origin + pn * -pd;

    return;
}

Vertex :: struct {
    position : Vector3,
    color    : Linear_Color,
}

main :: proc() {
    // Setup the engine
    init_details := engine.default_init_details();
    engine.init_scoped(init_details);   

    context = engine.default_context();

    the_engine := engine.get();

    // Setup all the gpu stuff including the 
    device := gpu.init(&the_engine.window);
    defer gpu.shutdown();
    
    asset.discover();

    // Make render pass
    render_pass : gpu.Render_Pass;
    {
        swapchain := &device.swapchain.(gpu.Swapchain);
        format := swapchain.backbuffers[0].format;

        color := gpu.Attachment{ format = format };

        desc := gpu.Render_Pass_Description{
            colors = []gpu.Attachment{ color },
        };

        render_pass = gpu.make_render_pass(device, desc);
    }

    vert_shader, frag_shader : ^gpu.Shader;
    found : bool;
    
    vert_shader, found = asset.load("assets/test.hlvs", gpu.Shader);
    assert(found);

    frag_shader, found = asset.load("assets/test.hlps", gpu.Shader);
    assert(found);

    // Make graphics pipeline
    pipeline : gpu.Pipeline;
    {

        shaders := []^gpu.Shader{ frag_shader, vert_shader };
        pipeline_desc := gpu.make_pipeline_description(&render_pass, typeid_of(Vertex), shaders);

        pipeline = gpu.make_graphics_pipeline(device, pipeline_desc);
    }

    resource_set_pool := gpu.make_resource_set_pool(vert_shader, 1);
    resource_set := gpu.allocate_resource_set(&resource_set_pool, 0);

    Constant_Buffer :: struct {
        projection, view, world : Matrix4,
    };

    constant_buffer := gpu.make_buffer(device, gpu.Buffer_Description{
        usage  = { .Constants },
        memory = .Host_Visible,
        size   = size_of(Constant_Buffer),
    });

    vertices := []Vertex{
        Vertex{
            position = v3(200, 0, -20),
            color    = core.green,
        },
        Vertex{ 
            position = v3(0, 500, -20),
            color    = core.red,
        },
        Vertex{
            position = v3(700, 0, -20),
            color    = core.blue,
        }
    };

    // Make vertex buffer
    vertex_buffer : gpu.Buffer;
    {
        desc := gpu.Buffer_Description{
            usage  = { .Vertex },
            memory = .Host_Visible,
            size   = len(vertices) * size_of(Vertex),
        };

        vertex_buffer = gpu.make_buffer(device, desc);
        gpu.copy_to_buffer(&vertex_buffer, vertices);
    }

    gfx_context := gpu.make_graphics_context(device);
    gfx := &gfx_context;

    core.show_window(&the_engine.window, true);

    for engine.is_running() {
        engine.dispatch_input();

        x : Constant_Buffer;
        x.world      = MATRIX4_IDENTITY;

        x.projection, x.view = render_right_handed(engine.viewport());

        gpu.copy_to_buffer(&constant_buffer, &x);
        gpu.bind_to_set(&resource_set, constant_buffer);


        // Record command buffer
        {
            gpu.record(gfx);

            backbuffer := gpu.backbuffer(device);
            {
                attachments := []^gpu.Texture{ backbuffer };
                gpu.render_pass_scope(gfx, &render_pass, attachments);

                gpu.bind_pipeline(gfx, &pipeline, v2(backbuffer.width, backbuffer.height));

                gpu.bind_resource_set(gfx, &resource_set);

                gpu.bind_vertex_buffer(gfx, vertex_buffer);
                
                gpu.draw(gfx, len(vertices));
            }
            gpu.resource_barrier(gfx, backbuffer, .Color_Attachment, .Present);
        }

        gpu.submit(device, gfx);
        gpu.display(device);
    }
}

// TEMP
render_right_handed :: proc(viewport: Rect, near : f32 = 0.1, far : f32 = 1000.0) -> (proj: Matrix4, view: Matrix4) {
    using core;

    _, draw_size := rect_pos_size(viewport);
    aspect_ratio := draw_size.x / draw_size.y;
    ortho_size   := draw_size.y / 2;

    proj = ortho(ortho_size, aspect_ratio, near, far);
    view = translate(v3(-draw_size.x / 2.0, -ortho_size, 0));
    return;
}