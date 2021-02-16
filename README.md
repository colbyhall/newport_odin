# Newport 
Newport is a modular game engine built in odin for odin. It is designed to be easily extendable and easy to use.

## Setup
1. Clone the repo into a desired folder
```sh
$ git clone https://github.com/colbyhall/newport.git
```
2. Run the setup script
```sh
$ setup.bat
```
3. Add the collection to your project build command
```sh
$ odin build example.odin -collection:newport=desired\
```
4. Import the collection into your project
```odin
package example

import "newport:core"
import "newport:engine"
import "newport:asset"
import "newport:gpu"

Vertex :: struct {
    position : core.Vector3,
    color    : core.Linear_Color,
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
        swapchain := device.swapchain.(gpu.Swapchain);
        format := swapchain.backbuffers[0].format;

        color := gpu.Attachment{ format = format };

        desc := gpu.Render_Pass_Description{
            colors = []gpu.Attachment{ color },
        };

        render_pass = gpu.make_render_pass(device, desc);
    }

    // Make graphics pipeline
    pipeline : gpu.Pipeline;
    {
        vert_shader, frag_shader : ^gpu.Shader;
        found : bool;
        
        vert_shader, found = asset.load("assets/test.hlvs", gpu.Shader);
        assert(found);

        frag_shader, found = asset.load("assets/test.hlps", gpu.Shader);
        assert(found);

        shaders := []^gpu.Shader{ frag_shader, vert_shader };
        pipeline_desc := gpu.make_pipeline_description(&render_pass, typeid_of(Vertex), shaders);

        pipeline = gpu.make_graphics_pipeline(device, pipeline_desc);
    }

    vertices := []Vertex{
        Vertex{ 
            position = v3(0, -0.5, 0),
            color    = core.red,
        },
        Vertex{
            position = v3(0.5, 0.5, 0),
            color    = core.green,
        },
        Vertex{
            position = v3(-0.5, 0.5, 0),
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

        // Record command buffer
        {
            gpu.record(gfx);

            backbuffer := gpu.backbuffer(device);
            {
                attachments := []^gpu.Texture{ backbuffer };
                gpu.render_pass_scope(gfx, &render_pass, attachments);

                gpu.bind_pipeline(gfx, &pipeline, v2(backbuffer.width, backbuffer.height));

                gpu.bind_vertex_buffer(gfx, vertex_buffer);
                
                gpu.draw(gfx, len(vertices));
            }
            gpu.resource_barrier(gfx, backbuffer, .Color_Attachment, .Present);
        }

        gpu.submit(device, gfx);
        gpu.display(device);
    }
}

```