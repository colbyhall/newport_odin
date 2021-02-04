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

    return .UNDEFINED;
}

init_vulkan :: proc(window: ^core.Window) -> ^Device {
    vulkan_state := new(Vulkan_State);
    vulkan_state.derived = vulkan_state^;

    device := new(Device);
    vulkan_state.current = device;

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
    views  : []vk.ImageView,
}

@private
recreate_swapchain :: proc(using device: ^Device) {
    // Check if there is a valid swapchain and if so delete it
    if swapchain != nil {
        using actual := &swapchain.(Swapchain);

        for it in views do vk.DestroyImageView(logical_gpu, it, nil);

        delete(views);

        // vk.DestroyRenderPass(logical_gpu, render_pass.handle, nil);
        vk.DestroySwapchainKHR(logical_gpu, handle, nil);
    }

    using state := get(Vulkan_State);

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

    queue_family_indices := [?]u32{
        graphics_family_index,
        surface_family_index,
    };

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

    using actual : Swapchain;

    extent = capabilities.currentExtent;

    result := vk.CreateSwapchainKHR(logical_gpu, &create_info, nil, &handle);
    assert(result == .SUCCESS);

    image_count : u32;
    vk.GetSwapchainImagesKHR(logical_gpu, handle, &image_count, nil);

    images := make([]vk.Image, int(image_count), context.temp_allocator);
    vk.GetSwapchainImagesKHR(logical_gpu, handle, &image_count, &images[0]);

    views = make([]vk.ImageView, int(image_count));

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

// display :: proc(using device: ^Device, framebuffer: ^Framebuffer) {
//     image_index : u32;
//     for it, i in swapchain.framebuffers {
//         if it.handle == framebuffer.handle {
//             image_index = u32(i);
//             break;
//         }
//     }

//     present_info := vk.PresentInfoKHR{
//         sType               = .PRESENT_INFO_KHR,
//         // waitSemaphoreCount  = 1,
//         // pWaitSemaphores     = &render_finished_semaphore,
//         swapchainCount      = 1,
//         pSwapchains         = &swapchain.handle,
//         pImageIndices       = &image_index,
//     };

//     result := vk.QueuePresentKHR(presentation_queue, &present_info);
//     if result == .ERROR_OUT_OF_DATE_KHR || result == .SUBOPTIMAL_KHR do create_swap_chain();

//     vk.QueueWaitIdle(presentation_queue);
// }

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
    heigth : int,
    depth  : int,
}

//
// Context API
////////////////////////////////////////////////////

Context :: struct {
    command_buffer : vk.CommandBuffer,
    derived        : typeid,
    device         : ^Device,
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
            finalLayout   = .SHADER_READ_ONLY_OPTIMAL,
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
            finalLayout   = .SHADER_READ_ONLY_OPTIMAL,
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

init_shader :: proc(using s: ^Shader, contents: []byte) {
    // check();

    // create_info := vk.ShaderModuleCreateInfo{
    //     sType    = .SHADER_MODULE_CREATE_INFO,
    //     codeSize = len(contents),
    //     pCode    = cast(^u32)&contents[0],
    // };

    // using state := get(Vulkan_Graphics);

    // result := vk.CreateShaderModule(logical_gpu, &create_info, nil, &module);
    // assert(result == .SUCCESS);
}



}