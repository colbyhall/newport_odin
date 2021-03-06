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
Vector2 :: core.Vector2;
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
Quaternion :: core.Quaternion;

Vertex :: struct {
    position : Vector3,
    
    normal   : Vector3,
    
    uv0      : Vector2,
    uv1      : Vector2,

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
    render_pass : ^gpu.Render_Pass;
    {
        swapchain := &device.swapchain.(gpu.Swapchain);
        format := swapchain.format;

        color := gpu.Attachment{ format = format };

        desc := gpu.Render_Pass_Description{
            colors = []gpu.Attachment{ color },
        };

        render_pass = gpu.make_render_pass(device, desc);
    } 

    vert_shader, frag_shader : ^gpu.Shader;
    found : bool;
    
    vert_shader, found = asset.acquire("assets/test.hlvs", gpu.Shader);
    assert(found);

    frag_shader, found = asset.acquire("assets/test.hlps", gpu.Shader);
    assert(found);

    test_texture : ^gpu.Texture;
    test_texture, found = asset.acquire("assets/test.texture", gpu.Texture);
    assert(found);

    // Make graphics pipeline
    pipeline : ^gpu.Pipeline;
    {
        shaders := []^gpu.Shader{ frag_shader, vert_shader };
        pipeline_desc := gpu.make_pipeline_description(render_pass, typeid_of(Vertex), shaders);

        pipeline = gpu.make_graphics_pipeline(device, pipeline_desc);
    }

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
            position = v3(-0.5, -0.5, 0),
            color    = core.green,
            uv0      = v2(1, 0),
        },
        Vertex{ 
            position = v3(-0.5, 0.5, 0),
            color    = core.red,
            uv0      = v2(0, 0),
        },
        Vertex{
            position = v3(0.5, 0.5, 0),
            color    = core.blue,
            uv0      = v2(0, 1),
        },
        Vertex{
            position = v3(-0.5, -0.5, 0),
            color    = core.green,
            uv0      = v2(1, 0),
        },
        Vertex{ 
            position = v3(0.5, 0.5, 0),
            color    = core.red,
            uv0      = v2(0, 1),
        },
        Vertex{
            position = v3(0.5, -0.5, 0),
            color    = core.blue,
            uv0      = v2(1, 1),
        }
    };

    // Make vertex buffer
    vertex_buffer : ^gpu.Buffer;
    {
        desc := gpu.Buffer_Description{
            usage  = { .Vertex },
            memory = .Host_Visible,
            size   = len(vertices) * size_of(Vertex),
        };

        vertex_buffer = gpu.make_buffer(device, desc);
        gpu.copy_to_buffer(vertex_buffer, vertices);
    }

    gfx := gpu.make_graphics_context(device);

    cam_pos : Vector3;
    cam_rot : Quaternion;

    core.show_window(&the_engine.window, true);

    for engine.is_running() {
        engine.dispatch_input();

        FOV :: 90;

        viewport := engine.viewport();
        aspect_ratio := viewport.max.x / viewport.max.y;

        x : Constant_Buffer;
        x.world = core.translate(v3(0, 0, -1));
        x.projection = core.persp(FOV, aspect_ratio, 0.1, 1000.0);
        x.view = core.mul(core.translate(-cam_pos), core.quat_to_mat4(cam_rot));

        // gpu.copy_to_buffer(constant_buffer, &x);
        // gpu.bind_to_set(vert_resource_set, constant_buffer);
        // gpu.bind_to_set(frag_resource_set, test_texture);

        // Record command buffer
        backbuffer, acquire_receipt := gpu.acquire_backbuffer(device);
        {
            gpu.record(gfx);
            {
                gpu.render_pass_scope(gfx, render_pass, backbuffer);

                gpu.clear(gfx, core.white, backbuffer);

                gpu.bind_pipeline(gfx, pipeline, v2(backbuffer.width, backbuffer.height));

                // gpu.bind_resource_set(gfx, vert_resource_set, 0);
                // gpu.bind_resource_set(gfx, frag_resource_set, 0);

                gpu.bind_vertex_buffer(gfx, vertex_buffer);
                
                gpu.draw(gfx, len(vertices));
            }
            gpu.resource_barrier(gfx, backbuffer, .Color_Attachment, .Present);
        }

        draw_receipt := gpu.submit(device, gfx, acquire_receipt);
        gpu.display(device, draw_receipt);

        gpu.wait(device);
    }
}