package gpu;

when BACK_END == .Vulkan {

import "core:mem"
import "core:dynlib"
import "core:log"
import "core:reflect"
import "core:runtime"

import "vk"
import "../core"
import "../asset"

when ODIN_OS == "windows" { 
    import "core:sys/win32"
}

Vulkan_State :: struct {
    using base : GPU_State,

    instance : vk.Instance,
    surface  : vk.SurfaceKHR,
}

instance_layers := [?]cstring{
    "VK_LAYER_KHRONOS_validation",
};

vk_format :: proc (format: Format) -> vk.Format {
    switch format {
    case .RGB_U8:       return .R8G8B8_UINT;
    case .RGBA_U8:      return .R8G8B8A8_UINT;
    case .RGBA_U8_SRGB: return .R8G8B8A8_SRGB;
    case .RGBA_F16:     return .R16G16B16A16_SFLOAT;
    case .BGR_U8_SRGB:  return .B8G8R8A8_SRGB;

    case .Undefined:    return .UNDEFINED;
    }

    unimplemented();
}

init_vulkan :: proc(window: ^core.Window) -> ^Device {
    vulkan_state := new(Vulkan_State);
    vulkan_state.derived = vulkan_state^;

    device := new(Device);
    vulkan_state.current = device;

    state = vulkan_state;

    // Load all the function ptrs from the dll
    {
        lib, ok := dynlib.load_library("vulkan-1.dll", true);
        assert(ok);

        context.user_ptr = &lib;

        vk.load_proc_addresses(proc(p: rawptr, name: cstring) {
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

    using vulkan_state;

    // Create the Vulkan instance
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
        create_info := vk.Win32SurfaceCreateInfoKHR{
            sType     = .WIN32_SURFACE_CREATE_INFO_KHR,
            hwnd      = auto_cast window.handle,
            hinstance = auto_cast win32.get_module_handle_a(nil),
        };

        result := vk.CreateWin32SurfaceKHR(instance, &create_info, nil, &surface);
        assert(result == .SUCCESS);
    }

    using device;

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

    // TEMP
    // Make the command pool
    {
        create_info := vk.CommandPoolCreateInfo{
            sType            = .COMMAND_POOL_CREATE_INFO,
            flags            = { .RESET_COMMAND_BUFFER },
            queueFamilyIndex = graphics_family_index,
        };

        result := vk.CreateCommandPool(logical_gpu, &create_info, nil, &graphics_command_pool);
        assert(result == .SUCCESS);
    }

    recreate_swapchain(device);

    return device;
}

// 
// Swapchain API
////////////////////////////////////////////////////

Swapchain :: struct {
    handle : vk.SwapchainKHR,
    extent : vk.Extent2D,

    backbuffers : []^Texture,
    current     : int,
}

@private
recreate_swapchain :: proc(using device: ^Device) {
    // Check if there is a valid swapchain and if so delete it
    if swapchain != nil {
        using actual := &swapchain.(Swapchain);

        for it in backbuffers {
            vk.DestroyImageView(logical_gpu, it.view, nil);
            free(it);
        }

        delete(backbuffers);

        // vk.DestroyRenderPass(logical_gpu, render_pass.handle, nil);
        vk.DestroySwapchainKHR(logical_gpu, handle, nil);
    }

    state := get(Vulkan_State);

    // Find the best surface format based on our specs
    capabilities : vk.SurfaceCapabilitiesKHR;
    vk.GetPhysicalDeviceSurfaceCapabilitiesKHR(physical_gpu, state.surface, &capabilities);

    format_count : u32;
    vk.GetPhysicalDeviceSurfaceFormatsKHR(physical_gpu, state.surface, &format_count, nil);

    formats := make([]vk.SurfaceFormatKHR, int(format_count), context.temp_allocator);
    vk.GetPhysicalDeviceSurfaceFormatsKHR(physical_gpu, state.surface, &format_count, &formats[0]);

    format : ^vk.SurfaceFormatKHR;
    for it in &formats {
        if it.format == .B8G8R8A8_SRGB && it.colorSpace == .SRGB_NONLINEAR {
            format = &it;
            break;
        }
    }
    assert(format != nil);

    present_mode := vk.PresentModeKHR.FIFO;

    queue_family_indices := [?]u32{
        graphics_family_index,
        surface_family_index,
    };

    using actual : Swapchain;

    // Make the swapchain object
    create_info := vk.SwapchainCreateInfoKHR{
        sType            = .SWAPCHAIN_CREATE_INFO_KHR,
        surface          = state.surface,
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

    result := vk.CreateSwapchainKHR(logical_gpu, &create_info, nil, &handle);
    assert(result == .SUCCESS);

    extent = capabilities.currentExtent;

    // Gather the swapchain created images
    image_count : u32;
    vk.GetSwapchainImagesKHR(logical_gpu, handle, &image_count, nil);
    images := make([]vk.Image, int(image_count), context.temp_allocator);
    vk.GetSwapchainImagesKHR(logical_gpu, handle, &image_count, &images[0]);

    // Fill out the back buffer textures
    backbuffers = make([]^Texture, int(image_count));
    for it, i in images {
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

        view : vk.ImageView;
        result := vk.CreateImageView(logical_gpu, &create_info, nil, &view);
        assert(result == .SUCCESS);

        backbuffer := new(Texture);
        backbuffer.width  = int(extent.width);
        backbuffer.height = int(extent.height);
        backbuffer.depth  = 1;
        backbuffer.format = .BGR_U8_SRGB;
        backbuffer.image  = it;
        backbuffer.view   = view;

        backbuffers[i] = backbuffer;
    }

    swapchain = actual;
}

// 
// Device API
////////////////////////////////////////////////////

Device :: struct {
    logical_gpu  : vk.Device,
    physical_gpu : vk.PhysicalDevice,

    // All the queues that will be used. This might get changed up to allow submission on multiple frames
    graphics_queue     : vk.Queue,
    presentation_queue : vk.Queue,

    graphics_family_index : u32,
    surface_family_index  : u32,

    // TODO: Think about job system and multi-threading
    graphics_command_pool : vk.CommandPool,

    swapchain : Maybe(Swapchain),
}

backbuffer :: proc(using device: ^Device) -> ^Texture {
    actual := &swapchain.(Swapchain);

    image_index : u32;

    result := vk.AcquireNextImageKHR(logical_gpu, actual.handle, (1 << 64 - 1), 0, 0, &image_index);
    if result == .ERROR_OUT_OF_DATE_KHR || result == .SUBOPTIMAL_KHR {
        recreate_swapchain(device);
        vk.AcquireNextImageKHR(logical_gpu, actual.handle, (1 << 64 - 1), 0, 0, &image_index);
    }

    actual.current = int(image_index);

    return actual.backbuffers[actual.current];
}

// TODO: Setup Reciepts 
submit_multiple :: proc(using device: ^Device, contexts: []^Context) {
    wait_stage : vk.PipelineStageFlags = { .COLOR_ATTACHMENT_OUTPUT };

    buffers := make([]vk.CommandBuffer, len(contexts), context.temp_allocator);
    for c, i in contexts do buffers[i] = c.command_buffer;

    submit_info := vk.SubmitInfo{
        sType                = .SUBMIT_INFO,
        pWaitDstStageMask    = &wait_stage,
        commandBufferCount   = u32(len(buffers)),
        pCommandBuffers      = &buffers[0],
    };

    vk.QueueSubmit(graphics_queue, 1, &submit_info, 0);
    vk.QueueWaitIdle(graphics_queue);
}

submit_single :: proc(using device: ^Device, ctx: ^Context) {
    single := []^Context{ ctx };
    submit_multiple(device, single);
}

submit :: proc{ submit_multiple, submit_single };

display :: proc(using device: ^Device) {
    if swapchain == nil do recreate_swapchain(device);
    actual := swapchain.(Swapchain);

    index := u32(actual.current);

    present_info := vk.PresentInfoKHR{
        sType               = .PRESENT_INFO_KHR,
        swapchainCount      = 1,
        pSwapchains         = &actual.handle,
        pImageIndices       = &index,
    };

    result := vk.QueuePresentKHR(presentation_queue, &present_info);
    if result == .ERROR_OUT_OF_DATE_KHR || result == .SUBOPTIMAL_KHR do recreate_swapchain(device);

    // TODO: Reciept system
    vk.QueueWaitIdle(presentation_queue);
}

//
// Buffer Pass API
////////////////////////////////////////////////////

Buffer :: struct {  
    handle : vk.Buffer,
    memory : vk.DeviceMemory, // @TODO: Move to a central allocation system

    desc   : Buffer_Description,
    device : ^Device,
}

// TODO: Better device memory allocation
make_buffer :: proc(using device: ^Device, desc: Buffer_Description) -> Buffer {
    usage : vk.BufferUsageFlags;
    if .Transfer_Src in desc.usage do usage |= { .TRANSFER_SRC };
    if .Transfer_Dst in desc.usage do usage |= { .TRANSFER_DST };
    if .Vertex       in desc.usage do usage |= { .VERTEX_BUFFER };
    if .Index        in desc.usage do usage |= { .INDEX_BUFFER };
    if .Uniform      in desc.usage do usage |= { .UNIFORM_BUFFER };

    create_info := vk.BufferCreateInfo{
        sType       = .BUFFER_CREATE_INFO,
        size        = vk.DeviceSize(desc.size),
        usage       = usage,
        sharingMode = .EXCLUSIVE, // TODO(colby): Look into this more
    };

    handle : vk.Buffer;
    result := vk.CreateBuffer(logical_gpu, &create_info, nil, &handle);

    // HACK: ALlocate unique DeviceMemory for each buffer. This will have to change
    memory : vk.DeviceMemory;
    {
        properties : vk.MemoryPropertyFlags;

        switch desc.memory {
        case .Host_Visible: properties |= { .HOST_VISIBLE, .HOST_COHERENT };
        case .Device_Local: properties |= { .DEVICE_LOCAL };
        }

        mem_requirements : vk.MemoryRequirements;
        vk.GetBufferMemoryRequirements(logical_gpu, handle, &mem_requirements);

        mem_properties : vk.PhysicalDeviceMemoryProperties;
        vk.GetPhysicalDeviceMemoryProperties(physical_gpu, &mem_properties);

        index := -1;
        for i : u32 = 0; i < mem_properties.memoryTypeCount; i += 1 {
            can_use := bool(mem_requirements.memoryTypeBits & (1 << i));
            can_use &= mem_properties.memoryTypes[i].propertyFlags & properties != {};

            if can_use {
                index = int(i);
                break;
            }
        }
        assert(index != -1);

        alloc_info := vk.MemoryAllocateInfo{
            sType           = .MEMORY_ALLOCATE_INFO,
            allocationSize  = mem_requirements.size,
            memoryTypeIndex = u32(index),
        };

        result = vk.AllocateMemory(logical_gpu, &alloc_info, nil, &memory);
        assert(result == .SUCCESS);
    }

    vk.BindBufferMemory(logical_gpu, handle, memory, 0);

    buffer := Buffer{
        handle = handle,
        memory = memory,
        desc   = desc,
        device = device,
    };

    return buffer;
}

delete_buffer :: proc(using buffer: ^Buffer) {
    vk.DestroyBuffer(device.logical_gpu, handle, nil);

    // NOTE: This will be removed when we have actual device allocators
    vk.FreeMemory(device.logical_gpu, memory, nil);

    handle = 0;
    memory = 0;
}

copy_to_buffer :: proc(using dst: ^Buffer, src: []$E) {
    assert(len(src) * size_of(E) == desc.size);

    data: rawptr;
    vk.MapMemory(device.logical_gpu, memory, 0, vk.DeviceSize(desc.size), {}, &data);
    mem.copy(data, &src[0], desc.size);
    vk.UnmapMemory(device.logical_gpu, memory);
}

//
// Texture API
////////////////////////////////////////////////////

// TODO: Mips
Texture :: struct {
    using asset : asset.Asset,

    image  : vk.Image,
    view   : vk.ImageView,
    memory : vk.DeviceMemory,

    format : Format,
    width  : int,
    height : int,
    depth  : int,
}

//
// Context API
////////////////////////////////////////////////////

Context :: struct {
    command_buffer : vk.CommandBuffer,
    derived        : typeid,
    device         : ^Device,

    framebuffers   : [dynamic]vk.Framebuffer,
}

begin :: proc(using ctx: ^Context) {
    result := vk.ResetCommandBuffer(command_buffer, {});
    assert(result == .SUCCESS);

    begin_info := vk.CommandBufferBeginInfo{
        sType = .COMMAND_BUFFER_BEGIN_INFO,
        flags = { .SIMULTANEOUS_USE },
    };

    result = vk.BeginCommandBuffer(command_buffer, &begin_info);
    assert(result == .SUCCESS);
}

end :: proc(using ctx: ^Context) {
    result := vk.EndCommandBuffer(command_buffer);
    assert(result == .SUCCESS);
}

@(deferred_out=end)
record :: proc(using ctx: ^Context) -> ^Context {
    begin(ctx);
    return ctx;
}

@private
texture_layout_to_image_layout :: proc(layout: Texture_Layout) -> vk.ImageLayout {
    switch layout {
    case .Undefined: return .UNDEFINED;
    case .General: return .GENERAL;
    case .Color_Attachment: return .COLOR_ATTACHMENT_OPTIMAL;
    case .Depth_Attachment: return .DEPTH_STENCIL_ATTACHMENT_OPTIMAL;
    case .Transfer_Src: return .TRANSFER_SRC_OPTIMAL;
    case .Transfer_Dst: return .TRANSFER_DST_OPTIMAL;
    case .Shader_Read_Only: return .SHADER_READ_ONLY_OPTIMAL;
    case .Present: return .PRESENT_SRC_KHR;
    }

    panic("Unsupported layout");
}

resource_barrier_texture :: proc(using ctx: ^Context, texture: ^Texture, old_layout, new_layout: Texture_Layout) {
    old_layout := texture_layout_to_image_layout(old_layout);
    new_layout := texture_layout_to_image_layout(new_layout);

    barrier := vk.ImageMemoryBarrier{
        sType       = .IMAGE_MEMORY_BARRIER,
        oldLayout   = old_layout,
        newLayout   = new_layout,
        image       = texture.image,

        srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
        dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
    };

    // TODO: Mips
    barrier.subresourceRange.aspectMask     = { .COLOR };
    barrier.subresourceRange.baseMipLevel   = 0;
    barrier.subresourceRange.levelCount     = 1;
    barrier.subresourceRange.baseArrayLayer = 0;
    barrier.subresourceRange.layerCount     = 1;

    src_stage : vk.PipelineStageFlag;
    dst_stage : vk.PipelineStageFlag;

    if old_layout == .UNDEFINED && new_layout == .TRANSFER_DST_OPTIMAL {
        barrier.dstAccessMask = { .TRANSFER_WRITE };
        src_stage = .TOP_OF_PIPE;
        dst_stage = .TRANSFER;
    } else if old_layout == .TRANSFER_DST_OPTIMAL && new_layout == .SHADER_READ_ONLY_OPTIMAL {
        barrier.srcAccessMask = { .TRANSFER_WRITE };
        barrier.dstAccessMask = { .SHADER_READ };

        src_stage = .TRANSFER;
        dst_stage = .FRAGMENT_SHADER;
    } else if old_layout == .COLOR_ATTACHMENT_OPTIMAL && new_layout == .PRESENT_SRC_KHR {
        src_stage = .BOTTOM_OF_PIPE;
        dst_stage = .BOTTOM_OF_PIPE;
    } else do panic("Unsupported layout transition");

    dep_flags : vk.DependencyFlags;
    vk.CmdPipelineBarrier(command_buffer, { src_stage }, { dst_stage }, dep_flags, 0, nil, 0, nil, 1, &barrier);
}

resource_barrier :: proc{ resource_barrier_texture };

Graphics_Context :: Context;

make_graphics_context :: proc(using device: ^Device) -> Graphics_Context {
    alloc_info := vk.CommandBufferAllocateInfo{
        sType               = .COMMAND_BUFFER_ALLOCATE_INFO,
        commandPool         = graphics_command_pool,
        level               = .PRIMARY,
        commandBufferCount  = 1,
    };

    handle : vk.CommandBuffer;
    result := vk.AllocateCommandBuffers(logical_gpu, &alloc_info, &handle);
    assert(result == .SUCCESS);

    return Graphics_Context{
        command_buffer = handle,
        derived        = typeid_of(Graphics_Context),
        device         = device,
    };
}

delete_graphics_context :: proc(using ctx: ^Graphics_Context) {
    // UNIMPLEMENTED
}

begin_render_pass :: proc(using ctx: ^Context, render_pass: ^Render_Pass, attachments: []^Texture) {
    extent := vk.Extent2D{
        width  = u32(attachments[0].width),
        height = u32(attachments[0].height)
    };

    render_area := vk.Rect2D{ extent = extent };

    // Make the framebuffer
    framebuffer : vk.Framebuffer;
    {
        vk_attachments := make([]vk.ImageView, len(attachments), context.temp_allocator);
        for it, i in attachments do vk_attachments[i] = it.view;

        create_info := vk.FramebufferCreateInfo{
            sType           = .FRAMEBUFFER_CREATE_INFO,
            renderPass      = render_pass.handle,
            attachmentCount = u32(len(attachments)),
            pAttachments    = &vk_attachments[0],
            width           = extent.width,
            height          = extent.height,
            layers          = 1,
        };

        result := vk.CreateFramebuffer(device.logical_gpu, &create_info, nil, &framebuffer);
        assert(result == .SUCCESS);
    }

    // Append framebuffer to framebuffers
    append(&framebuffers, framebuffer);

    begin_info := vk.RenderPassBeginInfo{
        sType           = .RENDER_PASS_BEGIN_INFO,
        renderPass      = render_pass.handle,
        framebuffer     = framebuffer,
        renderArea      = render_area,
    };

    vk.CmdBeginRenderPass(command_buffer, &begin_info, .INLINE);
}

end_render_pass :: proc(using ctx: ^Context) {
    vk.CmdEndRenderPass(command_buffer);
}

@(deferred_out=end_render_pass)
render_pass_scope :: proc(using ctx: ^Context, render_pass: ^Render_Pass, attachments: []^Texture) -> ^Context {
    begin_render_pass(ctx, render_pass, attachments);
    return ctx;
}

bind_pipeline :: proc(using ctx: ^Context, pipeline: ^Pipeline, viewport: Vector2, scissor: Maybe(Rect) = nil) {
    vk.CmdBindPipeline(command_buffer, .GRAPHICS, pipeline.handle);

    vk_viewport := vk.Viewport{
        width    = viewport.x,
        height   = viewport.y,
        maxDepth = 1,
    };
    vk.CmdSetViewport(command_buffer, 0, 1, &vk_viewport);
    if scissor == nil {
        rect : vk.Rect2D;
        rect.extent.width = u32(viewport.x);
        rect.extent.height = u32(viewport.y);
        vk.CmdSetScissor(command_buffer, 0, 1, &rect);
    } else {
        scissor := scissor.(Rect);

        _, size := rect_pos_size(scissor);

        rect : vk.Rect2D;
        rect.offset.x = i32(scissor.min.x);
        rect.offset.y = i32(scissor.min.y);
        rect.extent.width  = u32(size.x);
        rect.extent.height = u32(size.y);
        vk.CmdSetScissor(command_buffer, 0, 1, &rect);
    }
}

bind_vertex_buffer :: proc(using ctx: ^Context, b: Buffer) {
    b := b;

    offset : vk.DeviceSize;
    vk.CmdBindVertexBuffers(command_buffer, 0, 1, &b.handle, &offset);
}

draw :: proc(using ctx: ^Context, auto_cast vertex_count: int, auto_cast first_vertex := 0) {
    vk.CmdDraw(command_buffer, u32(vertex_count), 1, u32(first_vertex), 0);
}

//
// Render Pass API
////////////////////////////////////////////////////

Render_Pass :: struct {
    handle : vk.RenderPass,
    desc   : Render_Pass_Description,

    device : ^Device,
}

make_render_pass :: proc(using device: ^Device, desc: Render_Pass_Description) -> Render_Pass {
    color_refs := make([]vk.AttachmentReference, len(desc.colors), context.temp_allocator);

    num_attachments := len(desc.colors);
    if desc.depth != nil do num_attachments += 1;

    attachments := make([]vk.AttachmentDescription, num_attachments, context.temp_allocator);

    for it, i in desc.colors {
        format := vk_format(it.format);

        attachment := vk.AttachmentDescription{
            format  = format,
            samples = { ._1 },

            loadOp  = .LOAD,
            storeOp = .STORE,

            stencilLoadOp  = .DONT_CARE,
            stencilStoreOp = .DONT_CARE,

            initialLayout = .UNDEFINED,
            finalLayout   = .PRESENT_SRC_KHR,
        };
        attachments[i] = attachment;

        ref := vk.AttachmentReference{
            attachment = u32(i),
            layout     = .COLOR_ATTACHMENT_OPTIMAL,
        };
        color_refs[i] = ref;
    }

    // Currently we're only going to support 1 subpass as no other API has subpasses
    subpass := vk.SubpassDescription{
        pipelineBindPoint    = .GRAPHICS,
        colorAttachmentCount = u32(len(color_refs)),
        pColorAttachments    = &color_refs[0],
    };

    depth_refs : vk.AttachmentReference;
    if desc.depth != nil {
        depth := desc.depth.(Attachment);

        format := vk_format(depth.format);

        attachment := vk.AttachmentDescription{
            format  = format,
            samples = { ._1 },

            loadOp  = .LOAD,
            storeOp = .STORE,

            stencilLoadOp  = .DONT_CARE,
            stencilStoreOp = .DONT_CARE,

            initialLayout = .UNDEFINED,
            finalLayout   = .DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
        };
        attachments[len(desc.colors)] = attachment;

        depth_refs = vk.AttachmentReference{
            attachment = u32(num_attachments),
            layout     = .DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
        };

        subpass.pDepthStencilAttachment = &depth_refs;
    }

    stage_mask : vk.PipelineStageFlags;
    access_mask : vk.AccessFlags;

    if len(desc.colors) > 0 {
        stage_mask |= { .COLOR_ATTACHMENT_OUTPUT };
        access_mask |= { .COLOR_ATTACHMENT_WRITE };
    }

    if desc.depth != nil {
        stage_mask |= { .EARLY_FRAGMENT_TESTS };
        access_mask |= { .DEPTH_STENCIL_ATTACHMENT_WRITE };
    }

    dependency := vk.SubpassDependency{
        srcSubpass = vk.SUBPASS_EXTERNAL,
        srcStageMask = stage_mask,
        dstStageMask = stage_mask,
        dstAccessMask = access_mask,
    };

    create_info := vk.RenderPassCreateInfo{
        sType           = .RENDER_PASS_CREATE_INFO,
        attachmentCount = u32(num_attachments),
        pAttachments    = &attachments[0],
        subpassCount    = 1,
        pSubpasses      = &subpass,
        dependencyCount = 1,
        pDependencies   = &dependency,
    };

    handle : vk.RenderPass;
    result := vk.CreateRenderPass(logical_gpu, &create_info, nil, &handle);
    assert(result == .SUCCESS);
    return Render_Pass{
        handle = handle,
        desc   = desc,
        device = device,
    };
}

delete_render_pass :: proc(using rp: ^Render_Pass) { 
    // UNIMPLEMENTED
}

Shader :: struct {
    using asset : asset.Asset,

    type : Shader_Type,
    module : vk.ShaderModule,
}

init_shader :: proc(using device: ^Device, shader: ^Shader, contents: []byte) {
    create_info := vk.ShaderModuleCreateInfo{
        sType    = .SHADER_MODULE_CREATE_INFO,
        codeSize = len(contents),
        pCode    = cast(^u32)&contents[0],
    };

    result := vk.CreateShaderModule(logical_gpu, &create_info, nil, &shader.module);
    assert(result == .SUCCESS);
}

Pipeline :: struct {
    handle : vk.Pipeline,
    layout : vk.PipelineLayout,

    description : Pipeline_Description,
}

make_graphics_pipeline :: proc(using device: ^Device, using description: Pipeline_Description) -> Pipeline {
    assert(len(shaders) > 0);

    // Setup all the shader stages and load into a buffer
    shader_stages := make([]vk.PipelineShaderStageCreateInfo, len(shaders), context.temp_allocator);
    for it, i in shaders {
        if it == nil do continue;
        assert(it.loaded);

        stage : vk.ShaderStageFlag;
        switch it.type {
        case .Vertex:   stage = .VERTEX;
        case .Pixel: stage = .FRAGMENT;
        }

        stage_info := vk.PipelineShaderStageCreateInfo{
            sType  = .PIPELINE_SHADER_STAGE_CREATE_INFO,
            stage  = { stage },
            module = it.module,
            pName  = "main",
        };

        shader_stages[i] = stage_info;
    }

    // Do the vertex input stuff
    binding := vk.VertexInputBindingDescription{
        binding   = 0,
        stride    = u32(reflect.size_of_typeid(description.vertex)),
        inputRate = .VERTEX,
    };

    attributes := make([dynamic]vk.VertexInputAttributeDescription, 0, 12, context.temp_allocator);
    {
        using reflect;

        type_info := type_info_base(type_info_of(description.vertex));
        struct_info, ok := type_info.variant.(Type_Info_Struct);
        assert(ok); // Vertex must be a struct

        for it, i in struct_info.types {
            desc := vk.VertexInputAttributeDescription{
                binding  = 0,
                location = u32(i),
                offset   = u32(struct_info.offsets[i]),
            };

            switch it.id {
            case i32:           desc.format = .R32_SINT;
            case f32:           desc.format = .R32_SFLOAT;
            case Vector2:       desc.format = .R32G32_SFLOAT;
            case Vector3:       desc.format = .R32G32B32_SFLOAT;
            case Vector4:       desc.format = .R32G32B32A32_SFLOAT;
            case Linear_Color:  desc.format = .R32G32B32A32_SFLOAT;
            case:               assert(false);
            }

            append(&attributes, desc);
        }
    }

    vertex_input_state := vk.PipelineVertexInputStateCreateInfo{
        sType                           = .PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
        vertexBindingDescriptionCount   = 1,
        pVertexBindingDescriptions      = &binding,
        vertexAttributeDescriptionCount = u32(len(attributes)),
        pVertexAttributeDescriptions    = &attributes[0],
    };  

    input_assembly_state := vk.PipelineInputAssemblyStateCreateInfo{
        sType    = .PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
        topology = .TRIANGLE_LIST,
    };

    actual := swapchain.(Swapchain);
    vk_viewport := vk.Viewport{
        width    = f32(actual.extent.width),
        height   = f32(actual.extent.height),
        maxDepth = 1,
    };

    vk_scissor := vk.Rect2D{
        extent = actual.extent,
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

    // NOTE: Depth Testing goes around here somewhere
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
    };

    dynamic_state := vk.PipelineDynamicStateCreateInfo{
        sType               = .PIPELINE_DYNAMIC_STATE_CREATE_INFO,
        dynamicStateCount   = u32(len(dynamic_states)),
        pDynamicStates      = &dynamic_states[0],
    };

    // TODO(colby): Look into what a pipeline layout is and why
    pipeline_layout_info := vk.PipelineLayoutCreateInfo{
        sType          = .PIPELINE_LAYOUT_CREATE_INFO,
        // setLayoutCount = 1,
        // pSetLayouts    = &set_layout,
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
        pDynamicState       = &dynamic_state,
        layout              = layout,
        renderPass          = render_pass.handle,
        subpass             = 0,
        basePipelineIndex   = -1,
    };

    // TODO(colby): Look into pipeline caches
    handle : vk.Pipeline;
    result = vk.CreateGraphicsPipelines(logical_gpu, 0, 1, &create_info, nil, &handle);
    assert(result == .SUCCESS);

    return Pipeline{ 
        description = description, 
        handle      = handle, 
        
        layout      = layout,
    };
}

make_pipeline :: proc{ make_graphics_pipeline };


}