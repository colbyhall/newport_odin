package gpu

import "core:mem"
import "core:dynlib"
import "core:runtime"
import "core:log"

import "core:fmt" // temp

import "vk"
import "../engine"
import "../asset"

when ODIN_OS == "windows" { 
    import "core:sys/win32"
}

Swapchain :: struct {
    handle : vk.SwapchainKHR,

    extent       : vk.Extent2D,
    framebuffers : []Framebuffer,

    render_pass : Render_Pass,
}

acquire_backbuffer :: proc() -> ^Framebuffer {
    using state := get(Vulkan_Graphics);

    image_index : u32;
    vk.AcquireNextImageKHR(logical_gpu, swapchain.handle, (1 << 64 - 1), image_available_semaphore, 0, &image_index);

    return &swapchain.framebuffers[int(image_index)];
}

Vulkan_Graphics :: struct {
    using base : Graphics,

    instance : vk.Instance,
    surface  : vk.SurfaceKHR,

    physical_gpu : vk.PhysicalDevice,
    logical_gpu  : vk.Device,

    graphics_queue      : vk.Queue,
    presentation_queue  : vk.Queue,

    graphics_family_index  : u32,
    surface_family_index   : u32,

    image_available_semaphore : vk.Semaphore,
    render_finished_semaphore : vk.Semaphore,
}

instance_layers := [?]cstring{
    "VK_LAYER_KHRONOS_validation",
};

init_vulkan :: proc() {
    casted_state := new(Vulkan_Graphics);
    state = casted_state;

    // Load all the function ptrs from the dll
    {
        lib, ok := dynlib.load_library("vulkan-1.dll", true);
        assert(ok);

        context.user_ptr = &lib;

        vk.load_proc_addresses(proc(p: rawptr, name: cstring){
            lib := (cast(^dynlib.Library)context.user_ptr)^;

            ptr, found := dynlib.symbol_address(lib, runtime.cstring_to_string(name));
            if !found {
                // log.warnf("[Vulkan] Could not find symbol {}", name);
                return;
            }

            casted := cast(^rawptr)p;
            casted^ = ptr;
        });
    }

    using casted_state;

    // Create the vulkan instance
    {
        app_info := vk.ApplicationInfo{
            sType               = .APPLICATION_INFO,
            pApplicationName    = "Why does this matter",
            applicationVersion  = vk.MAKE_VERSION(1, 0, 0),
            pEngineName         = "Why does this matter engine",
            engineVersion       = vk.MAKE_VERSION(1, 0, 0),
            apiVersion          = vk.API_VERSION_1_0,
        };

        when ODIN_OS == "windows" {
            instance_extensions := [?]cstring{
                "VK_KHR_surface",
                "VK_KHR_win32_surface",
            };
        }

        create_info := vk.InstanceCreateInfo{
            sType                   = .INSTANCE_CREATE_INFO,
            pApplicationInfo        = &app_info,
            enabledExtensionCount   = u32(len(instance_extensions)),
            ppEnabledExtensionNames = &instance_extensions[0],
            enabledLayerCount       = u32(len(instance_layers)),
            ppEnabledLayerNames     = &instance_layers[0],
        };

        result := vk.CreateInstance(&create_info, nil, &instance);
        assert(result == .SUCCESS);
    }

    // Create the window surface
    when ODIN_OS == "windows" {
        the_engine := engine.get();
        window     := &the_engine.window;

        create_info := vk.Win32SurfaceCreateInfoKHR{
            sType     = .WIN32_SURFACE_CREATE_INFO_KHR,
            hwnd      = auto_cast window.handle,
            hinstance = auto_cast win32.get_module_handle_a(nil),
        };

        result := vk.CreateWin32SurfaceKHR(instance, &create_info, nil, &surface);
        assert(result == .SUCCESS);
    }

    // Pick the GPU based on some criteria
    {
        device_count : u32;
        vk.EnumeratePhysicalDevices(instance, &device_count, nil);
        assert(device_count > 0);

        devices := make([]vk.PhysicalDevice, int(device_count), context.temp_allocator);

        vk.EnumeratePhysicalDevices(instance, &device_count, &devices[0]);

        selected_gpu : vk.PhysicalDevice;
        for device in devices {
            properties : vk.PhysicalDeviceProperties;
            vk.GetPhysicalDeviceProperties(device, &properties);

            features : vk.PhysicalDeviceFeatures;
            vk.GetPhysicalDeviceFeatures(device, &features);

            // TODO(colby): Maybe do more checking with features we actually will need like KHR Swapchain support?
            if properties.deviceType == .DISCRETE_GPU && features.geometryShader {
                selected_gpu = device;
            }
        }

        assert(selected_gpu != nil);
        physical_gpu = selected_gpu;
    }

    // Find the proper queue family indices
    {
        queue_family_count : u32;
        vk.GetPhysicalDeviceQueueFamilyProperties(physical_gpu, &queue_family_count, nil);
        assert(queue_family_count > 0);

        queue_families := make([]vk.QueueFamilyProperties, int(queue_family_count), context.temp_allocator);
        vk.GetPhysicalDeviceQueueFamilyProperties(physical_gpu, &queue_family_count, &queue_families[0]);

        for queue_family, i in queue_families {
            if .GRAPHICS in queue_family.queueFlags {
                graphics_family_index = u32(i);
            }

            present_support : b32;
            vk.GetPhysicalDeviceSurfaceSupportKHR(physical_gpu, u32(i), surface, &present_support);
            if present_support do surface_family_index = u32(i);
        }
    }

    queue_family_indices := [?]u32{
        graphics_family_index,
        surface_family_index,
    };

    // Setup the logical device and queues
    {
        queue_create_infos := make([]vk.DeviceQueueCreateInfo, len(queue_family_indices), context.temp_allocator);

        queue_priority : f32;
        for index, i in queue_family_indices {
            create_info := vk.DeviceQueueCreateInfo{
                sType            = .DEVICE_QUEUE_CREATE_INFO,
                queueFamilyIndex = index,
                queueCount       = 1,
                pQueuePriorities  = &queue_priority,
            };

            queue_create_infos[i] = create_info;
        }

        logical_device_features : vk.PhysicalDeviceFeatures;
        logical_device_extensions := [?]cstring{
            vk.KHR_SWAPCHAIN_EXTENSION_NAME,
        };

        logical_device_create_info := vk.DeviceCreateInfo{
            sType                   = .DEVICE_CREATE_INFO,
            queueCreateInfoCount    = u32(len(queue_create_infos)),
            pQueueCreateInfos       = &queue_create_infos[0],
            enabledLayerCount       = u32(len(instance_layers)),
            ppEnabledLayerNames     = &instance_layers[0],
            enabledExtensionCount   = u32(len(logical_device_extensions)),
            ppEnabledExtensionNames = &logical_device_extensions[0],
            pEnabledFeatures        = &logical_device_features,
        };

        result := vk.CreateDevice(physical_gpu, &logical_device_create_info, nil, &logical_gpu);
        assert(result == .SUCCESS);

        vk.GetDeviceQueue(logical_gpu, graphics_family_index, 0, &graphics_queue);
        vk.GetDeviceQueue(logical_gpu, surface_family_index, 0, &presentation_queue);
    }

    // Create the swap chain
    // TODO(colby): Abstract out into its own function for swap chain creation
    {
        capabilities : vk.SurfaceCapabilitiesKHR;
        vk.GetPhysicalDeviceSurfaceCapabilitiesKHR(physical_gpu, surface, &capabilities);

        format_count : u32;
        vk.GetPhysicalDeviceSurfaceFormatsKHR(physical_gpu, surface, &format_count, nil);

        formats := make([]vk.SurfaceFormatKHR, int(format_count), context.temp_allocator);
        vk.GetPhysicalDeviceSurfaceFormatsKHR(physical_gpu, surface, &format_count, &formats[0]);

        format : ^vk.SurfaceFormatKHR;
        for it in &formats {
            if it.format == .B8G8R8A8_SRGB && it.colorSpace == .SRGB_NONLINEAR {
                format = &it;
                break;
            }
        }
        assert(format != nil);

        present_mode := vk.PresentModeKHR.FIFO;

        create_info := vk.SwapchainCreateInfoKHR{
            sType            = .SWAPCHAIN_CREATE_INFO_KHR,
            surface          = surface,
            minImageCount    = capabilities.minImageCount,
            imageFormat      = format.format,
            imageColorSpace  = format.colorSpace,
            imageExtent      = capabilities.currentExtent,
            imageArrayLayers = 1,
            imageUsage       = { .COLOR_ATTACHMENT },
            imageSharingMode = .CONCURRENT,

            queueFamilyIndexCount = u32(len(queue_family_indices)),
            pQueueFamilyIndices   = &queue_family_indices[0],

            preTransform     = capabilities.currentTransform,
            compositeAlpha   = { .OPAQUE },
            presentMode      = present_mode,
            clipped          = true,
        };

        using swapchain;

        extent = capabilities.currentExtent;

        result := vk.CreateSwapchainKHR(logical_gpu, &create_info, nil, &handle);
        assert(result == .SUCCESS);

        image_count : u32;
        vk.GetSwapchainImagesKHR(logical_gpu, handle, &image_count, nil);

        images := make([]vk.Image, int(image_count), context.temp_allocator);
        vk.GetSwapchainImagesKHR(logical_gpu, handle, &image_count, &images[0]);

        views := make([]vk.ImageView, int(image_count), context.temp_allocator);

        for _, i in images {
            component_mapping := vk.ComponentMapping{ .IDENTITY, .IDENTITY, .IDENTITY, .IDENTITY };

            subresource_range := vk.ImageSubresourceRange{
                aspectMask = { .COLOR },
                levelCount = 1,
                layerCount = 1,
            };

            create_info := vk.ImageViewCreateInfo{
                sType       = .IMAGE_VIEW_CREATE_INFO,
                image       = images[i],
                viewType    = .D2,
                format      = .B8G8R8A8_SRGB,
                components  = component_mapping,
                subresourceRange = subresource_range,
            };

            result := vk.CreateImageView(logical_gpu, &create_info, nil, &views[i]);
            assert(result == .SUCCESS);
        }

        render_pass = make_render_pass();

        framebuffers = make([]Framebuffer, int(image_count));

        for it, i in &framebuffers {
            create_info := vk.FramebufferCreateInfo{
                sType           = .FRAMEBUFFER_CREATE_INFO,
                renderPass      = render_pass.handle,
                attachmentCount = 1,
                pAttachments    = &views[i],
                width           = extent.width,
                height          = extent.height,
                layers          = 1,
            };

            handle : vk.Framebuffer;
            result := vk.CreateFramebuffer(logical_gpu, &create_info, nil, &handle);
            assert(result == .SUCCESS);

            it.handle = handle;
            it.width  = int(extent.width);
            it.height = int(extent.height);
            
            it.attachments = make([]Framebuffer_Attachment, 1);
            it.attachments[0].image = images[i];
            it.attachments[0].view  = views[i];
        }
    }

    // Create semaphores
    {
        create_info := vk.SemaphoreCreateInfo{
            sType = .SEMAPHORE_CREATE_INFO,
        };

        result := vk.CreateSemaphore(logical_gpu, &create_info, nil, &image_available_semaphore);
        assert(result == .SUCCESS);

        result = vk.CreateSemaphore(logical_gpu, &create_info, nil, &render_finished_semaphore);
        assert(result == .SUCCESS);
    }
}

/*
fill_command_buffer :: proc(pipeline: ^Graphics_Pipeline) {
    using state := get(Vulkan_Graphics);

    // Create the command buffers and fill them
    {
        pool_create_info := vk.CommandPoolCreateInfo{
            sType            = .COMMAND_POOL_CREATE_INFO,
            queueFamilyIndex = graphics_family_index,
        };

        result := vk.CreateCommandPool(logical_gpu, &pool_create_info, nil, &command_pool);
        assert(result == .SUCCESS);

        alloc_info := vk.CommandBufferAllocateInfo{
            sType               = .COMMAND_BUFFER_ALLOCATE_INFO,
            commandPool         = command_pool,
            level               = .PRIMARY,
            commandBufferCount  = u32(len(command_buffers)),
        };

        result = vk.AllocateCommandBuffers(logical_gpu, &alloc_info, &command_buffers[0]);
        assert(result == .SUCCESS);

        for it, i in &command_buffers {
            begin_info := vk.CommandBufferBeginInfo{
                sType = .COMMAND_BUFFER_BEGIN_INFO,
                flags = { .SIMULTANEOUS_USE },
            };

            result = vk.BeginCommandBuffer(it, &begin_info);
            assert(result == .SUCCESS);

            // Start a render pass
            {
                render_area := vk.Rect2D{ extent = swapchain.extent };
                clear_color : vk.ClearValue;
                clear_color.color.float32 = { 0, 0, 0, 1 };

                begin_info := vk.RenderPassBeginInfo{
                    sType           = .RENDER_PASS_BEGIN_INFO,
                    renderPass      = swapchain.render_pass.handle,
                    framebuffer     = swapchain.framebuffers[i],
                    renderArea      = render_area,
                    clearValueCount = 1,
                    pClearValues    = &clear_color,
                };

                vk.CmdBeginRenderPass(it, &begin_info, .INLINE);
            }

            vk.CmdBindPipeline(it, .GRAPHICS, pipeline.handle);

            vk.CmdDraw(it, 3, 1, 0, 0);

            vk.CmdEndRenderPass(it);

            result = vk.EndCommandBuffer(it);
            assert(result == .SUCCESS);
        }
    }
}

do_draw :: proc() {
    using state := get(Vulkan_Graphics);

    image_index : u32;
    vk.AcquireNextImageKHR(logical_gpu, swapchain.handle, (1 << 64 - 1), image_available_semaphore, 0, &image_index);

    wait_stage : vk.PipelineStageFlags = { .COLOR_ATTACHMENT_OUTPUT };

    submit_info := vk.SubmitInfo{
        sType                = .SUBMIT_INFO,
        waitSemaphoreCount   = 1,
        pWaitSemaphores      = &image_available_semaphore,
        pWaitDstStageMask    = &wait_stage,
        commandBufferCount   = 1,
        pCommandBuffers      = &command_buffers[int(image_index)],
        signalSemaphoreCount = 1,
        pSignalSemaphores    = &render_finished_semaphore,
    };

    vk.QueueSubmit(graphics_queue, 1, &submit_info, 0);

    present_info := vk.PresentInfoKHR{
        sType               = .PRESENT_INFO_KHR,
        waitSemaphoreCount  = 1,
        pWaitSemaphores     = &render_finished_semaphore,
        swapchainCount      = 1,
        pSwapchains         = &swapchain.handle,
        pImageIndices       = &image_index,
    };

    vk.QueuePresentKHR(presentation_queue, &present_info);
    vk.QueueWaitIdle(presentation_queue);
}
*/

Render_Pass :: struct {
    handle : vk.RenderPass,
}

// TODO(colby): Super not finished
make_render_pass :: proc(loc := #caller_location) -> Render_Pass {
    check(loc);

    attachment := vk.AttachmentDescription{
        format  = .B8G8R8A8_SRGB,
        samples = { ._1 },
        loadOp  = .CLEAR,
        storeOp = .STORE,

        stencilLoadOp  = .DONT_CARE,
        stencilStoreOp = .DONT_CARE,

        initialLayout = .UNDEFINED,
        finalLayout   = .PRESENT_SRC_KHR,
    };

    attachment_ref := vk.AttachmentReference{
        attachment  = 0,
        layout      = .COLOR_ATTACHMENT_OPTIMAL,
    };

    subpass := vk.SubpassDescription{
        pipelineBindPoint    = .GRAPHICS,
        colorAttachmentCount = 1,
        pColorAttachments    = &attachment_ref,
    };

    dependency := vk.SubpassDependency{
        srcSubpass    = vk.SUBPASS_EXTERNAL,
        srcStageMask  = { .COLOR_ATTACHMENT_OUTPUT },
        dstStageMask  = { .COLOR_ATTACHMENT_OUTPUT },
        dstAccessMask = { .COLOR_ATTACHMENT_WRITE },
    };

    create_info := vk.RenderPassCreateInfo{
        sType           = .RENDER_PASS_CREATE_INFO,
        attachmentCount = 1,
        pAttachments    = &attachment,
        subpassCount    = 1,
        pSubpasses      = &subpass,
        dependencyCount = 1,
        pDependencies   = &dependency,
    };

    using state := get(Vulkan_Graphics);

    handle : vk.RenderPass;
    result := vk.CreateRenderPass(logical_gpu, &create_info, nil, &handle);
    return Render_Pass{ handle = handle };
}

Shader :: struct {
    using asset : asset.Asset,

    type   : Shader_Type,
    module : vk.ShaderModule,
}

init_shader :: proc(using s: ^Shader, contents: []byte) {
    check();

    create_info := vk.ShaderModuleCreateInfo{
        sType    = .SHADER_MODULE_CREATE_INFO,
        codeSize = len(contents),
        pCode    = cast(^u32)&contents[0],
    };

    // TODO(colby): somehow determine what type of shader this is.
    // The question is whether we'll have metadata or just use the file extension

    using state := get(Vulkan_Graphics);

    result := vk.CreateShaderModule(logical_gpu, &create_info, nil, &module);
    assert(result == .SUCCESS);
}

Graphics_Pipeline :: struct {
    using description : Graphics_Pipeline_Description,

    handle : vk.Pipeline,
    layout : vk.PipelineLayout,
}

make_graphics_pipeline :: proc(using description: Graphics_Pipeline_Description, loc := #caller_location) -> Graphics_Pipeline {
    check(loc);

    using state := get(Vulkan_Graphics);

    assert(len(shaders) > 0);

    // Setup all the shader stages and load into a buffer
    shader_stages := make([]vk.PipelineShaderStageCreateInfo, len(shaders), context.temp_allocator);
    for it, i in shaders {
        if it == nil do continue;
        assert(it.loaded);

        stage : vk.ShaderStageFlag;
        switch it.type {
        case .Vertex:   stage = .VERTEX;
        case .Fragment: stage = .FRAGMENT;
        }

        stage_info := vk.PipelineShaderStageCreateInfo{
            sType  = .PIPELINE_SHADER_STAGE_CREATE_INFO,
            stage  = { stage },
            module = it.module,
            pName  = "main",
        };

        shader_stages[i] = stage_info;
    }

    // TODO(colby): Setup the vertex attributes
    vertex_input_state := vk.PipelineVertexInputStateCreateInfo{
        sType = .PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
    };  

    input_assembly_state := vk.PipelineInputAssemblyStateCreateInfo{
        sType    = .PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
        topology = .TRIANGLE_LIST,
    };

    vk_viewport := vk.Viewport{
        width    = f32(swapchain.extent.width),
        height   = f32(swapchain.extent.height),
        maxDepth = 1,
    };

    vk_scissor := vk.Rect2D{
        extent = swapchain.extent,
    };

    viewport_state := vk.PipelineViewportStateCreateInfo{
        sType           = .PIPELINE_VIEWPORT_STATE_CREATE_INFO,
        viewportCount   = 1,
        pViewports      = &vk_viewport,
        scissorCount    = 1,
        pScissors       = &vk_scissor,
    };

    polygon_mode : vk.PolygonMode;
    switch draw_mode {
    case .Fill:  polygon_mode = .FILL;
    case .Line:  polygon_mode = .LINE;
    case .Point: polygon_mode = .POINT;
    }

    cull : vk.CullModeFlags;
    if .Front in cull_mode do cull |= { .FRONT };
    if .Back in cull_mode do cull |= { .BACK };

    // NOTE(colby): Depth Testing goes around here somewhere
    rasterizer_state := vk.PipelineRasterizationStateCreateInfo{
        sType       = .PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
        polygonMode = polygon_mode,
        cullMode    = cull,
        frontFace   = .CLOCKWISE,
        lineWidth   = line_width,
    };

    multisample_state := vk.PipelineMultisampleStateCreateInfo{
        sType                   = .PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
        rasterizationSamples    = { ._1 },
        minSampleShading        = 1.0,
    };

    // Setting up blending and converting data types
    vk_blend_factor :: proc(fc: Blend_Factor) -> vk.BlendFactor{
        switch fc {
        case .Zero: return .ZERO;
        case .One:  return .ONE;
        case .Src_Color: return .SRC_COLOR;
        case .One_Minus_Src_Color: return .ONE_MINUS_SRC_COLOR;
        case .Dst_Color: return .DST_COLOR;
        case .One_Minus_Dst_Color: return .ONE_MINUS_DST_COLOR;
        case .Src_Alpha: return .SRC_ALPHA;
        case .One_Minus_Src_Alpha: return .ONE_MINUS_SRC_ALPHA;
        }

        return .ZERO;
    }

    vk_blend_op :: proc(a: Blend_Op) -> vk.BlendOp{
        switch a {
        case .Add: return .ADD;
        case .Subtract: return .SUBTRACT;
        case .Reverse_Subtract: return .REVERSE_SUBTRACT;
        case .Min: return .MIN;
        case .Max: return .MAX;
        }

        return .ADD;
    }

    color_write_mask : vk.ColorComponentFlags;
    if .Red   in color_mask do color_write_mask |= { .R };
    if .Green in color_mask do color_write_mask |= { .G };
    if .Blue  in color_mask do color_write_mask |= { .B };
    if .Alpha in color_mask do color_write_mask |= { .A };

    color_blend_attachment := vk.PipelineColorBlendAttachmentState{
        blendEnable = b32(blend_enabled),
        srcColorBlendFactor = vk_blend_factor(src_color_blend_factor),
        dstColorBlendFactor = vk_blend_factor(dst_color_blend_factor),
        colorBlendOp = vk_blend_op(color_blend_op),

        srcAlphaBlendFactor = vk_blend_factor(src_alpha_blend_factor),
        dstAlphaBlendFactor = vk_blend_factor(dst_alpha_blend_factor),
        alphaBlendOp = vk_blend_op(alpha_blend_op),
        colorWriteMask = color_write_mask,
    };

    color_blend_state := vk.PipelineColorBlendStateCreateInfo{
        sType           = .PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
        logicOp         = .COPY,
        attachmentCount = 1,
        pAttachments    = &color_blend_attachment,
    };

    // Creating the dynamic states
    dynamic_states := [?]vk.DynamicState {
        .VIEWPORT,
        .SCISSOR,
        .LINE_WIDTH,
    };

    dynamic_state := vk.PipelineDynamicStateCreateInfo{
        sType               = .PIPELINE_DYNAMIC_STATE_CREATE_INFO,
        dynamicStateCount   = u32(len(dynamic_states)),
        pDynamicStates      = &dynamic_states[0],
    };

    // TODO(colby): Look into what a pipeline layout is and why
    pipeline_layout_info := vk.PipelineLayoutCreateInfo{
        sType = .PIPELINE_LAYOUT_CREATE_INFO,
    };

    layout : vk.PipelineLayout;
    result := vk.CreatePipelineLayout(logical_gpu, &pipeline_layout_info, nil, &layout);
    assert(result == .SUCCESS);

    create_info := vk.GraphicsPipelineCreateInfo{
        sType               = .GRAPHICS_PIPELINE_CREATE_INFO,
        stageCount          = u32(len(shader_stages)),
        pStages             = &shader_stages[0],
        pVertexInputState   = &vertex_input_state,
        pInputAssemblyState = &input_assembly_state,
        pViewportState      = &viewport_state,
        pRasterizationState = &rasterizer_state,
        pMultisampleState   = &multisample_state,
        pColorBlendState    = &color_blend_state,
        // pDynamicState       = &dynamic_state,
        layout              = layout,
        renderPass          = render_pass.handle,
        subpass             = u32(subpass_index),
        basePipelineIndex   = -1,
    };

    // TODO(colby): Look into pipeline caches
    handle : vk.Pipeline;
    result = vk.CreateGraphicsPipelines(logical_gpu, 0, 1, &create_info, nil, &handle);
    assert(result == .SUCCESS);

    return Graphics_Pipeline{ 
        description = description, 
        handle      = handle, 
        layout      = layout 
    };
}

Command_Allocator :: struct {
    handle : vk.CommandPool,
    type   : Command_Allocator_Type,
}

make_command_allocator :: proc(type: Command_Allocator_Type) -> Command_Allocator {
    using state := get(Vulkan_Graphics);

    create_info := vk.CommandPoolCreateInfo{
        sType            = .COMMAND_POOL_CREATE_INFO,
        flags            = { .RESET_COMMAND_BUFFER },
        queueFamilyIndex = graphics_family_index,
    };

    handle : vk.CommandPool;
    result := vk.CreateCommandPool(logical_gpu, &create_info, nil, &handle);
    assert(result == .SUCCESS);

    return Command_Allocator{ handle = handle, type = type };
}

delete_command_allocator :: proc(using alloc: ^Command_Allocator) {
    using state := get(Vulkan_Graphics);

    vk.DestroyCommandPool(logical_gpu, handle, nil);
    handle = 0;
}

Command_Buffer :: struct {
    handle    : vk.CommandBuffer,
}

make_command_buffer_single :: proc(alloc: Command_Allocator) -> Command_Buffer {
    using state := get(Vulkan_Graphics);

    alloc_info := vk.CommandBufferAllocateInfo{
        sType               = .COMMAND_BUFFER_ALLOCATE_INFO,
        commandPool         = alloc.handle,
        level               = .PRIMARY,
        commandBufferCount  = 1,
    };

    handle : vk.CommandBuffer;
    result := vk.AllocateCommandBuffers(logical_gpu, &alloc_info, &handle);
    assert(result == .SUCCESS);

    return Command_Buffer{ handle = handle };
}

make_command_buffers :: proc(alloc: Command_Allocator, len: int, slice_allocator := context.allocator) -> []Command_Buffer {
    using state := get(Vulkan_Graphics);

    alloc_info := vk.CommandBufferAllocateInfo{
        sType               = .COMMAND_BUFFER_ALLOCATE_INFO,
        commandPool         = alloc.handle,
        level               = .PRIMARY,
        commandBufferCount  = u32(len),
    };

    // HACK(colby): Doing this to prevent multiple allocation. This will break is more members are added to Command_Buffer
    results := make([]Command_Buffer, len, slice_allocator);
    result := vk.AllocateCommandBuffers(logical_gpu, &alloc_info, &results[0].handle);
    assert(result == .SUCCESS);

    return results;
}

make_command_buffer :: proc{ make_command_buffer_single, make_command_buffers };

reset_command_buffer :: proc(buffer: Command_Buffer) {
    result := vk.ResetCommandBuffer(buffer.handle, {});
    assert(result == .SUCCESS);
}

begin_command_buffer :: proc(buffer: Command_Buffer) {
    begin_info := vk.CommandBufferBeginInfo{
        sType = .COMMAND_BUFFER_BEGIN_INFO,
        flags = { .SIMULTANEOUS_USE },
    };

    result := vk.BeginCommandBuffer(buffer.handle, &begin_info);
    assert(result == .SUCCESS);
}

end_command_buffer :: proc(buffer: Command_Buffer) {
    result := vk.EndCommandBuffer(buffer.handle);
    assert(result == .SUCCESS);
}

@(deferred_out=end_command_buffer)
record_scope :: proc(buffer: Command_Buffer) -> Command_Buffer {
    begin_command_buffer(buffer);
    return buffer;
}

begin_render_pass :: proc(buffer: Command_Buffer, render_pass: ^Render_Pass, framebuffer: ^Framebuffer) {
    extent := vk.Extent2D{
        width  = u32(framebuffer.width),
        height = u32(framebuffer.height)
    };

    render_area := vk.Rect2D{ extent = extent };

    // TODO(colby): Figure out where to put clear values and such
    clear_color : vk.ClearValue;
    clear_color.color.float32 = { 0, 0, 0, 1 };

    begin_info := vk.RenderPassBeginInfo{
        sType           = .RENDER_PASS_BEGIN_INFO,
        renderPass      = render_pass.handle,
        framebuffer     = framebuffer.handle,
        renderArea      = render_area,
        clearValueCount = 1,
        pClearValues    = &clear_color,
    };

    vk.CmdBeginRenderPass(buffer.handle, &begin_info, .INLINE);
}

end_render_pass :: proc(buffer: Command_Buffer) {
    vk.CmdEndRenderPass(buffer.handle);
}

@(deferred_out=end_render_pass)
render_pass_scope :: proc(buffer: Command_Buffer, render_pass: ^Render_Pass, framebuffer: ^Framebuffer) -> Command_Buffer {
    begin_render_pass(buffer, render_pass, framebuffer);
    return buffer;
}

bind_graphics_pipeline :: proc(buffer: Command_Buffer, pipeline: ^Graphics_Pipeline) {
    vk.CmdBindPipeline(buffer.handle, .GRAPHICS, pipeline.handle);
}

bind_pipeline :: proc{ bind_graphics_pipeline };

draw :: proc(buffer: Command_Buffer, auto_cast vertex_count: int, auto_cast first_vertex := 0) {
    vk.CmdDraw(buffer.handle, u32(vertex_count), 1, u32(first_vertex), 0);
}

submit_multiple :: proc(buffers: []Command_Buffer) {
    using state := get(Vulkan_Graphics);

    wait_stage : vk.PipelineStageFlags = { .COLOR_ATTACHMENT_OUTPUT };

    submit_info := vk.SubmitInfo{
        sType                = .SUBMIT_INFO,
        waitSemaphoreCount   = 1,
        pWaitSemaphores      = &image_available_semaphore,
        pWaitDstStageMask    = &wait_stage,
        commandBufferCount   = u32(len(buffers)),
        pCommandBuffers      = auto_cast &buffers[0],
        signalSemaphoreCount = 1,
        pSignalSemaphores    = &render_finished_semaphore,
    };

    vk.QueueSubmit(graphics_queue, 1, &submit_info, 0);
    vk.QueueWaitIdle(graphics_queue);
}

submit_single :: proc(buffer: Command_Buffer) {
    single := [?]Command_Buffer{ buffer };
    submit_multiple(single[:]);
}

submit :: proc{ submit_multiple, submit_single };

display :: proc(framebuffer: ^Framebuffer) {
    using state := get(Vulkan_Graphics);

    image_index : u32;
    for it, i in swapchain.framebuffers {
        if it.handle == framebuffer.handle {
            image_index = u32(i);
            break;
        }
    }

    present_info := vk.PresentInfoKHR{
        sType               = .PRESENT_INFO_KHR,
        waitSemaphoreCount  = 1,
        pWaitSemaphores     = &render_finished_semaphore,
        swapchainCount      = 1,
        pSwapchains         = &swapchain.handle,
        pImageIndices       = &image_index,
    };

    vk.QueuePresentKHR(presentation_queue, &present_info);
    // vk.QueueWaitIdle(presentation_queue);
}

Framebuffer_Attachment :: struct {
    image : vk.Image,
    view  : vk.ImageView,
}

Framebuffer :: struct {
    handle        : vk.Framebuffer,
    width, height : int,
    attachments   : []Framebuffer_Attachment,
}

// UNIMPLEMENTED
Texture2d :: struct {
    using asset : asset.Asset,

    pixels : []u8,
    width, height, depth: int,
}

upload_texture :: proc(using t: ^Texture2d) -> bool {
    return false;
}