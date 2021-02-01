# Newport Research Document
As I've been working on this project I've realized that I need a space to throw a bunch of information regarding design patterns, API's, and system architecture. I can't retain all of this in my head and I've found some deep hidden blogs/research that have been extremely helpful. There will be "basic" information in this doc. I want a place where someone can start picking up on Game Engine Programming.

### API Selection
| Name          | Platform               | Reason                   |
|---------------|------------------------|--------------------------|
|Vulkan         | Windows, Linux, Switch |Hardware Abstraction Layer|
|DirectX12      | Windows, XBOX          |Hardware Abstraction Layer|
|DirectXCompiler| Windows, Linux, XBOX   |Runtime Shader Compilation|
|SPIRV Reflect  | Windows, Linux, Switch |Vulkan Description Layout |
|STB            | All                    |PNG, JPG, TTF, .OGG       |
|WASABI         | Windows, XBOX          |Audio                     |
|XInput         | Windows, XBOX          |Controller Support        |

### Table Of Contents
[Fiber Based Job System](#fiber-based-job-system)<br>
[Asset Manager](#asset-manager)<br>
[COM in C](#com-in-c)<br>
[DirectXCompiler](#directxcompiler)<br>
[Hardware Abstraction Layer](#hardware-abstraction-layer)<br>
[Frame Graph](#frame-graph)<br>
[Forward+ Rendering](#forward+-rendering)<br>


## Fiber Based Job System
This is what sparked the inspiration for Newport. I wanted to get as much juice as I could from the CPU so I decided to commit to a job system based architecture. 

### Articles
[Parallelizing the Naughty Dog engine using fibers](https://www.gdcvault.com/play/1022186/Parallelizing-the-Naughty-Dog-Engine)<br>
[Fiber based job system - Our Machiner](https://ourmachinery.com/post/fiber-based-job-system/)<br>

## Asset Manager
A lot of what I used in this asset manager came from experience. It's strongly based off of Jonathan Blow's engine for asset management. I don't use catalogs and just keep it together, but the general structure is there. 

### Articles
[The Machinery Asset Pipeline](https://ourmachinery.com/post/the-machinery-asset-pipeline/)<br>
[The Truth](https://ourmachinery.com/post/the-story-behind-the-truth-designing-a-data-model/)<br>

## COM in C
I had never worked with COM in my entire life. I have lots of questions about the design decisions but to be fair to the creators I'm not aware of COM's full capabilities so I will give them the benefit of the doubt. 

### Articles
[COM in plain C](https://www.codeproject.com/Articles/13601/COM-in-plain-C)<br>
[COM in plain C, Part 2](https://www.codeproject.com/Articles/13862/COM-in-plain-C-Part-2)<br>

### Additional Thoughts
If you care to see how I solved this just checkout my DXC wrapper [here](https://github.com/colbyhall/odin-dxc)

## [DirectXCompiler](https://github.com/microsoft/DirectXShaderCompiler)
I really wanted the ability to write shaders once and then have them compile for both Vulkan and Direct X. DirectXCompiler seemed to be a great way to do it. Overrall the API is pretty easy to use. Works on Linux too which is a plus.

### Articles
[Using the DirectXShaderCompiler C++ API](https://simoncoenen.com/blog/programming/graphics/DxcCompiling.html)<br>
[Using the DirectXShaderCompiler C++ API - Revised](https://simoncoenen.com/blog/programming/graphics/DxcRevised.html)<br>
[Spirv Descriptors](https://github.com/microsoft/DirectXShaderCompiler/blob/master/docs/SPIR-V.rst#descriptors)<br>

## Hardware Abstraction Layer
This has been something thats been on my mind for years now. The more I dig the deeper I go. This one will be constantly updated. 

### Articles
[An Opinionated Post on Modern Rendering Abstraction Layers](http://alextardif.com/RenderingAbstractionLayers.html)<br>
[Binding Bindlessly](http://alextardif.com/Bindless.html)<br>
[Vulkan Textures Unbound](http://roar11.com/2019/06/vulkan-textures-unbound/)<br>
[Halcyon Architecture "Director's Cut"](https://media.contentapi.ea.com/content/dam/ea/seed/presentations/wihlidal-halcyonarchitecture-notes.pdf)<br>
[A modern rendering architecture](https://ourmachinery.com/post/a-modern-rendering-architecture/)<br>
[A Comparison of Modern Graphics APIs](https://alain.xyz/blog/comparison-of-modern-graphics-apis)<br>
[Musings on cross-platform graphics engine architectures - Part1](http://www.gijskaerts.com/wordpress/?p=98)<br>
[Vulkan Guide](https://vkguide.dev/)

### Additional Thoughts
I'm going to be following in the mindset of Alex Tardif in his article [An Opinionated Post on Modern Rendering Abstraction Layers](http://alextardif.com/RenderingAbstractionLayers.html). I want to keep things as simple as possible and not limit the user too much.

## Frame Graph
I've spent a good bit of time researching Frame/Render graphs to determine if I want to implement one. I'm still not sure but I think they're promising. Maybe this could be a fun stretch goal.

### Articles
[High-Level Rendering Using Render Graphs](https://ourmachinery.com/post/high-level-rendering-using-render-graphs/)<br>
[Render graphs](https://apoorvaj.io/render-graphs-1/)<br>
[Render graphs and Vulkan - a deep dive](https://themaister.net/blog/2017/08/15/render-graphs-and-vulkan-a-deep-dive/)<br>
[Simon's Tech Blog: Render Graph](http://simonstechblog.blogspot.com/2019/07/render-graph.html)<br>
[FrameGraph: Extensible Rendering Architecture in Frostbite](https://www.gdcvault.com/play/1024612/FrameGraph-Extensible-Rendering-Architecture-in)<br>

## Forward+ Rendering
It seems that deferred is slowly losing the grasp it once had on the industry. Games like Doom Eternal seem to really be pushing forward what is capable with graphics by using Forward+. 

### Articles
[Forward vs Deferred vs Forward+ Rendering with DirectX 11](https://www.3dgep.com/forward-plus/)<br>
[Doom Eternal - Graphics Study](https://simoncoenen.com/blog/programming/graphics/DoomEternalStudy.html)<br>