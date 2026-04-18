#include <cstdio>
#include <iostream>

#include "metal_bridge.h"
#include "Metal/MTLBuffer.hpp"
#include <Foundation/Foundation.hpp>
#include <Metal/Metal.hpp>


extern "C" MyMetalDevice bridge_create_device() {
    return (void*)MTL::CreateSystemDefaultDevice();
}

extern "C" void bridge_get_device_name(MyMetalDevice device, char* out_name) {
    MTL::Device* mtl_dev = (MTL::Device*)device;
    const char* name = mtl_dev->name()->utf8String();
    strcpy(out_name, name);
}

extern "C" void bridge_release_device(MyMetalDevice device) {
    MTL::Device* mtl_dev = (MTL::Device*)device;
    mtl_dev->release();
}

extern "C" MyMetalPipeline bridge_create_compute_pipeline(MyMetalDevice device, const char* function_name) {
    auto dev = (MTL::Device*)device;

    // Load default library (requires default.metallib to be in your run path)
    MTL::Library* lib = dev->newDefaultLibrary();
    if (!lib){
        std::cerr << "Cannot load default library!";
        return nullptr;
    }

    auto fn_name = NS::String::string(function_name, NS::UTF8StringEncoding);
    MTL::Function* fn = lib->newFunction(fn_name);

    NS::Error* error = nullptr;
    MTL::ComputePipelineState* pso = dev->newComputePipelineState(fn, &error);

    fn->release();
    lib->release();
    return (void*)pso;
}

extern "C" MyMetalPipeline bridge_create_render_pipeline(MyMetalDevice device,
                                                        const char* vert_fn_name,
                                                        const char* frag_fn_name) {
    auto dev = (MTL::Device*)device;
    MTL::Library* lib = dev->newDefaultLibrary();

    // 1. Load the two different shader functions
    auto vName = NS::String::string(vert_fn_name, NS::UTF8StringEncoding);
    auto fName = NS::String::string(frag_fn_name, NS::UTF8StringEncoding);
    MTL::Function* vertFn = lib->newFunction(vName);
    MTL::Function* fragFn = lib->newFunction(fName);

    // 2. Create a Descriptor (the blueprint)
    MTL::RenderPipelineDescriptor* desc = MTL::RenderPipelineDescriptor::alloc()->init();
    desc->setVertexFunction(vertFn);
    desc->setFragmentFunction(fragFn);

    // Crucial: This must match your window's pixel format (usually BGRA8)
    desc->colorAttachments()->object(0)->setPixelFormat(MTL::PixelFormatBGRA8Unorm);

    // 3. Compile the Pipeline State Object (PSO)
    NS::Error* error = nullptr;
    MTL::RenderPipelineState* pso = dev->newRenderPipelineState(desc, &error);

    // Cleanup
    desc->release();
    vertFn->release();
    fragFn->release();
    lib->release();

    return (void*)pso;
}

extern "C" MyMetalBuffer bridge_create_buffer(MyMetalDevice device, float* data, size_t count) {
    auto dev = (MTL::Device*)device;
    size_t size = count * sizeof(float);
    // Shared mode = Unified Memory (CPU and GPU see the same pointer)
    MTL::Buffer* buf = dev->newBuffer(data, size, MTL::ResourceStorageModeShared);
    return (void*)buf;
}


// Directly use the input memory when creating the Metal buffer, nocopy
extern "C" MyMetalBuffer bridge_create_buffer_nocopy(MyMetalDevice device, float* data, size_t count) {
    auto dev = (MTL::Device*)device;
    size_t size = count * sizeof(float);

    // This wraps your Zig pointer directly
    MTL::Buffer* buf = dev->newBuffer(data, size, MTL::ResourceStorageModeShared, nullptr);
    return (void*)buf;
}

// Copy the content of the metal buffer into the target memory
extern "C" void bridge_read_buffer(MyMetalBuffer buf, float* dest, size_t count) {
    auto mtlBuf = (MTL::Buffer*)buf;
    memcpy(dest, mtlBuf->contents(), count * sizeof(float));
}

extern "C" void bridge_run_adder(MyMetalDevice device, MyMetalPipeline pipeline,
                      MyMetalBuffer bufA, MyMetalBuffer bufB, MyMetalBuffer bufC,
                      size_t count) {
    auto dev = (MTL::Device*)device;
    auto pso = (MTL::ComputePipelineState*)pipeline;

    auto queue = dev->newCommandQueue();
    auto cmd_buffer = queue->commandBuffer();
    auto encoder = cmd_buffer->computeCommandEncoder();

    encoder->setComputePipelineState(pso);

    auto bufferC = (MTL::Buffer*)bufC;


    encoder->setBuffer((MTL::Buffer*)bufA, 0, 0); // buffer(0) in .metal
    encoder->setBuffer((MTL::Buffer*)bufB, 0, 1); // buffer(1) in .metal
    encoder->setBuffer((MTL::Buffer*)bufC, 0, 2); // buffer(2) in .metal

    // Grid size logic
    MTL::Size gridSize = MTL::Size(count, 1, 1);
    NS::UInteger tgSize = pso->maxTotalThreadsPerThreadgroup();
    if (tgSize > count) tgSize = count;
    MTL::Size threadgroupSize = MTL::Size(tgSize, 1, 1);

    encoder->dispatchThreads(gridSize, threadgroupSize);
    encoder->endEncoding();

    cmd_buffer->commit();
    cmd_buffer->waitUntilCompleted(); // Wait for results

    // 1. Get the raw pointer and cast it to float*
    float* results = (float*)bufferC->contents();

    // 2. Iterate and print the actual values
    std::cout << "Results: ";
    for (size_t i = 0; i < count; i++) {
        std::cout << results[i] << " ";
    }
    std::cout << std::endl;


    queue->release();
}

extern "C" void bridge_draw_frame(MyMetalDevice device, MyMetalPipeline pipeline,
                                 MyMetalBuffer vertex_buf, void* current_drawable) {
    auto dev = (MTL::Device*)device;
    auto pso = (MTL::RenderPipelineState*)pipeline;
    auto drawable = (CA::MetalDrawable*)current_drawable;

    auto queue = dev->newCommandQueue();
    auto cmd_buffer = queue->commandBuffer();

    // Setup the Render Pass (Clear the screen to a specific color)
    MTL::RenderPassDescriptor* pass = MTL::RenderPassDescriptor::renderPassDescriptor();
    pass->colorAttachments()->object(0)->setTexture(drawable->texture());
    pass->colorAttachments()->object(0)->setLoadAction(MTL::LoadActionClear);
    pass->colorAttachments()->object(0)->setClearColor(MTL::ClearColor(0.1, 0.1, 0.1, 1.0)); // Dark grey
    pass->colorAttachments()->object(0)->setStoreAction(MTL::StoreActionStore);

    auto encoder = cmd_buffer->renderCommandEncoder(pass);
    encoder->setRenderPipelineState(pso);

    // Bind your Zig-provided vertex buffer
    encoder->setVertexBuffer((MTL::Buffer*)vertex_buf, 0, 0);

    // Draw! 3 vertices = 1 triangle
    encoder->drawPrimitives(MTL::PrimitiveTypeTriangle, (NS::UInteger)0, (NS::UInteger)3);

    encoder->endEncoding();
    cmd_buffer->presentDrawable(drawable);
    cmd_buffer->commit();
}
