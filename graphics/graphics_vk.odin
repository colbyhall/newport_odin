package graphics

import "core:mem"
import "core:dynlib"
import "core:runtime"
import "core:fmt"
import "core:log"

import "vk"
import "../engine"
import "../asset"

when ODIN_OS == "windows" { 
    import "core:sys/win32"
}

Vulkan_Swapchain :: struct {
    handle : vk.SwapchainKHR,

    extent : vk.Extent2D,
    images : []vk.Image,
    views  : []vk.ImageView,
}

Vulkan_Graphics :: struct {
    using base : Graphics,

    instance : vk.Instance,
    surface  : vk.SurfaceKHR,

    physical_gpu : vk.PhysicalDevice,
    logical_gpu  : vk.Device,

    graphics_queue      : vk.Queue,
    presentation_queue  : vk.Queue,

    swapchain : Vulkan_Swapchain,

    render_pass : Render_Pass, // temp
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

    graphics_family_index := -1;
    surface_family_index := -1;

    // Find the proper queue family indices
    {
        queue_family_count : u32;
        vk.GetPhysicalDeviceQueueFamilyProperties(physical_gpu, &queue_family_count, nil);
        assert(queue_family_count > 0);

        queue_families := make([]vk.QueueFamilyProperties, int(queue_family_count), context.temp_allocator);
        vk.GetPhysicalDeviceQueueFamilyProperties(physical_gpu, &queue_family_count, &queue_families[0]);

        for queue_family, i in queue_families {
            if .GRAPHICS in queue_family.queueFlags {
                graphics_family_index = i;
            }

            present_support : b32;
            vk.GetPhysicalDeviceSurfaceSupportKHR(physical_gpu, u32(i), surface, &present_support);
            if present_support do surface_family_index = i;
        }
    }

    assert(graphics_family_index != -1 && surface_family_index != -1);
    queue_family_indices := [?]u32{
        u32(graphics_family_index),
        u32(surface_family_index),
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

        vk.GetDeviceQueue(logical_gpu, u32(graphics_family_index), 0, &graphics_queue);
        vk.GetDeviceQueue(logical_gpu, u32(surface_family_index), 0, &presentation_queue);
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

        result := vk.CreateSwapchainKHR(logical_gpu, &create_info, nil, &handle);
        assert(result == .SUCCESS);

        image_count : u32;
        vk.GetSwapchainImagesKHR(logical_gpu, handle, &image_count, nil);

        images = make([]vk.Image, int(image_count));
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
    }

    render_pass = make_render_pass(); // temp
}

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

    using state := get(Vulkan_Graphics);

    result := vk.CreateShaderModule(logical_gpu, &create_info, nil, &module);
    assert(result == .SUCCESS);
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

Pipeline :: struct {

}