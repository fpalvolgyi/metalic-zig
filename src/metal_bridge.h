#ifndef METAL_BRIDGE_H
#define METAL_BRIDGE_H

#include <stddef.h>



#ifdef __cplusplus
extern "C" {
#endif

typedef void* MyMetalDevice;
typedef void* MyMetalPipeline;
typedef void* MyMetalBuffer;

MyMetalDevice bridge_create_device();
void bridge_get_device_name(MyMetalDevice device, char* out_name);
void bridge_release_device(MyMetalDevice device);
MyMetalPipeline bridge_create_compute_pipeline(MyMetalDevice device, const char* function_name);
MyMetalPipeline bridge_create_render_pipeline(MyMetalDevice device,
                                                        const char* vert_fn_name,
                                                        const char* frag_fn_name);
MyMetalBuffer bridge_create_buffer(MyMetalDevice device, float* data, size_t count);
MyMetalBuffer bridge_create_buffer_nocopy(MyMetalDevice device, float* data, size_t count);
void bridge_run_adder(MyMetalDevice device, MyMetalPipeline pipeline,
                      MyMetalBuffer bufA, MyMetalBuffer bufB, MyMetalBuffer bufC,
                      size_t count);
void bridge_draw_frame(MyMetalDevice device, MyMetalPipeline pipeline,
                                 MyMetalBuffer vertex_buf, void* current_drawable);

#ifdef __cplusplus
}
#endif

#endif
