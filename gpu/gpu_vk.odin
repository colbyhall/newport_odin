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

vk_format :: proc (format: Texture_Format) -> vk.Format {
    switch format {
    case .Undefined: asset(false);
    }

    return .Undefined;
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

    return device;
}

// 
// Device API
////////////////////////////////////////////////////

Swapchain :: struct {
    handle : vk.SwapchainKHR,

    extent       : vk.Extent2D,
    framebuffers : []Framebuffer,

    // render_pass : Render_Pass,
}

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
}

submit_multiple :: proc(using device: ^Device, contexts: []^Context) {
    wait_stage : vk.PipelineStageFlags = { .COLOR_ATTACHMENT_OUTPUT };

    submit_info := vk.SubmitInfo{
        sType                = .SUBMIT_INFO,
        waitSemaphoreCount   = 1,
        pWaitSemaphores      = &image_available_semaphore,
        pWaitDstStageMask    = &wait_stage,
        commandBufferCount   = u32(len(buffers)),
        pCommandBuffers      = auto_cast &buffers[0],
        // signalSemaphoreCount = 1,
        // pSignalSemaphores    = &render_finished_semaphore,
    };

    vk.QueueSubmit(graphics_queue, 1, &submit_info, 0);
    vk.QueueWaitIdle(graphics_queue);
}

submit_single :: proc(using device: ^Device, ctx: ^Context) {
    single := []^Context{ ctx };
    submit_multiple(single);
}

submit :: proc{ submit_multiple, submit_single };

display :: proc(using device: ^Device, framebuffer: ^Framebuffer) {
    image_index : u32;
    for it, i in swapchain.framebuffers {
        if it.handle == framebuffer.handle {
            image_index = u32(i);
            break;
        }
    }

    present_info := vk.PresentInfoKHR{
        sType               = .PRESENT_INFO_KHR,
        // waitSemaphoreCount  = 1,
        // pWaitSemaphores     = &render_finished_semaphore,
        swapchainCount      = 1,
        pSwapchains         = &swapchain.handle,
        pImageIndices       = &image_index,
    };

    result := vk.QueuePresentKHR(presentation_queue, &present_info);
    if result == .ERROR_OUT_OF_DATE_KHR || result == .SUBOPTIMAL_KHR do create_swap_chain();

    vk.QueueWaitIdle(presentation_queue);
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
record :: proc(using ctx: ^Context) -> return ^Context {
    begin(ctx);
    return ctx;
}

Graphics_Context :: distinct Context;

make_graphics_context :: proc(using device: ^Device) -> Graphics_Context {
    alloc_info := vk.CommandBufferAllocateInfo{
        sType               = .COMMAND_BUFFER_ALLOCATE_INFO,
        commandPool         = graphics_command_pool,
        level               = .PRIMARY,
        commandBufferCount  = u32(len),
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
// Render Pass API
////////////////////////////////////////////////////

Render_Pass :: struct {
    handle : vk.RenderPass,
    device : ^Device,
    desc   : Render_Pass_Description,
}

make_render_pass :: proc(using device: ^Device, attachments: []Attachment_Description) -> Render_Pass {
    color_refs := make([dynamic]vk.AttachmentReference, 0, len(attachments), context.temp_allocator);
    depth_refs : vk.AttachmentReference;

    subpass := vk.SubpassDescription{
        pipelineBindPoint = .GRAPHICS,
    }

    vk_attachments := make([]vk.AttachmentDescription, len(attachments), context.temp_allocator);
    for it, i in attachments {
        attachment := vk.AttachmentDescription{

        }
    }

    subpass.colorAttachmentCount = u32(len(color_refs));
    subpass.pColorAttachments = &color_refs[0];

    dependency := vk.SubpassDependency{

    };

    create_info := vk.RenderPassCreateInfo{
        sType           = .RENDER_PASS_CREATE_INFO,
        attachmentCount = u32(len(vk_attachments)),
        pAttachments    = &vk_attachments[0],
        subpassCount    = 1,
        pSubpasses      = &subpass,
        dependencyCount = 1,
        pDependencies   = &dependency,
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