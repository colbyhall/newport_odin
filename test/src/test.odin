package test

import "newport:core"
import "newport:engine"
import "newport:asset"
import "newport:job"
import "newport:gpu"
import "newport:draw"
import "newport:gui"

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

    draw.register_font_collection();
    
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

    consola : ^draw.Font_Collection;
    consola, found = asset.acquire("assets/consola.ttf", draw.Font_Collection);
    assert(found);

    font := draw.font_at_size(consola, 72);

    Constants :: struct {
        render : Matrix4,
        world  : Matrix4,
        tex    : u32,
    };

    // Make graphics pipeline
    pipeline : ^gpu.Pipeline;
    {
        shaders := []^gpu.Shader{ frag_shader, vert_shader };
        pipeline_desc := gpu.make_pipeline_description(render_pass, typeid_of(Vertex), shaders);
        pipeline_desc.push_constant_size = size_of(Constants);

        pipeline = gpu.make_graphics_pipeline(device, pipeline_desc);
    }

    vertices := []Vertex{
        Vertex{
            position = v3(-0.5, -0.5, 0),
            color    = core.green,
            uv0      = v2(0, 1),
        },
        Vertex{ 
            position = v3(-0.5, 0.5, 0),
            color    = core.red,
            uv0      = v2(0, 0),
        },
        Vertex{
            position = v3(0.5, 0.5, 0),
            color    = core.blue,
            uv0      = v2(1, 0),
        },
        Vertex{
            position = v3(-0.5, -0.5, 0),
            color    = core.green,
            uv0      = v2(0, 1),
        },
        Vertex{ 
            position = v3(0.5, 0.5, 0),
            color    = core.red,
            uv0      = v2(1, 0),
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

    cam_pos := v3(0, 0, 0.5);
    cam_rot : Quaternion;

    core.show_window(&the_engine.window, true);

    for engine.is_running() {
        engine.dispatch_input();

        FOV :: 90;

        viewport := engine.viewport();
        aspect_ratio := viewport.max.x / viewport.max.y;

        projection := core.persp(FOV, aspect_ratio, 0.01, 1000.0);
        view := core.mul(core.translate(-cam_pos), core.quat_to_mat4(cam_rot));


        // Record command buffer
        backbuffer, acquire_receipt := gpu.acquire_backbuffer(device);
        gpu.update_bindless(device);
        {
            gpu.record(gfx);
            {
                gpu.render_pass_scope(gfx, render_pass, backbuffer);

                gpu.clear(gfx, core.black, backbuffer);

                gpu.bind_pipeline(gfx, pipeline, v2(backbuffer.width, backbuffer.height));

                gpu.bind_vertex_buffer(gfx, vertex_buffer);


                world := core.translate(v3());
                x := Constants{ render = core.mul(projection, view), world = world, tex = 0 };
                gpu.push_constants(gfx, &x);

                gpu.draw(gfx, len(vertices));
            }
            gpu.resource_barrier(gfx, backbuffer, .Color_Attachment, .Present);
        }

        draw_receipt := gpu.submit(device, gfx, acquire_receipt);
        gpu.display(device, draw_receipt);

        gpu.wait(device);
    }
}