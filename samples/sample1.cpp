#include <cassert>

#include "radiance.h"
#include "sceneBuilder.h"
#include "inspector.h"

#define STB_IMAGE_WRITE_IMPLEMENTATION
#include "stb_image_write.h"

#define OFF_SCREEN
#define LOAD_CACHE true

struct CbData
{
    RD::Platform* plt;
    unsigned int* extent;
    uint8_t* image;
    RD::Buffer rdImage;
    size_t imageSize;

    RD::Buffer rdCamData;
    RD::Buffer rdSceneData;
    RD::Buffer rdRTProp;
};

struct Camera
{
    float x, y, z, focal;
    float wx, wy, wz, exposure;
};

void render(void* data, unsigned char** image, int* out_width, int* out_height);
bool RenderSceneConfigUI(CbData *d);

int main()
{
    std::string modelFile =
        // "/home/zekailin00/Desktop/ray-tracing/framework/assets/Cornell2.glb"; // helmet
        "/home/zekailin00/Desktop/ray-tracing/framework/assets/Cornell-armor.glb"; //armor
        // "/home/zekailin00/Desktop/ray-tracing/framework/assets/sample1.glb";
    std::string shaderPath =
        "/home/zekailin00/Desktop/ray-tracing/framework/samples/shader.cl";
    unsigned int extent[2] = {4000, 4000};
    size_t imageSize = extent[0] * extent[1] * RD_CHANNEL;
    uint8_t* image = (uint8_t*)malloc(imageSize);

    /* Define pipeline data inputs */
    RD::RayTraceProperties RTProp = {
        .totalSamples = 0,
        .batchSize = 10,
        .depth = 8,
        .debug = 0
    };

    // // sample1
    // struct Camera camData = {
    //     .x =  -1.0f,
    //     .y = 2.0f, 
    //     .z = 1.0f,
    //     .focal = -1.0f,
    //     .wx = -0.0f,
    //     .wy = -0.6f,
    //     .wz = -0.0f,
    //     .exposure = 1.0f
    // };
    // RD::SceneProperties sceneData;
    // sceneData.lightCount[0] = 1;
    // sceneData.lights[0] = {
    //     .direction = {100.0f, -10.0f, 10.0f},
    //     .color = {15.0f, 15.0f, 15.0f, 1.0f}
    // };


    // // cornell
    // struct Camera camData = {
    //     .x = 0.0f,
    //     .y = 6.0f, 
    //     .z = -10.0f,
    //     .focal = -1.0f,
    //     .wx = 0.3f,
    //     .wy = 3.14f,
    //     .wz = -0.0f,
    //     .exposure = 1.0f
    // };
    // RD::SceneProperties sceneData;
    // sceneData.lightCount[0] = 1;
    // sceneData.lights[0] = {
    //     .direction = {0.0f, -1.0f, 100.0f},
    //     .color = {10.0f, 10.0f, 10.0f, 1.0f}
    // };

    // cornell - details
    struct Camera camData = {
        .x = 0.0f,
        .y = 7.5f, 
        .z = -8.0f,
        .focal = -1.0f,
        .wx = 0.4f,
        .wy = 3.14f,
        .wz = -0.0f,
        .exposure = 1.0f
    };
    RD::SceneProperties sceneData;
    sceneData.lightCount[0] = 1;
    sceneData.lights[0] = {
        .direction = {0.0f, 1.0f, 10.0f},
        .color = {10.0f, 10.0f, 10.0f, 1.0f}
    };

    /* Intialize platform */
    RD::Platform* plt = RD::Platform::GetPlatform();

    RD::Buffer rdRTProp = RD::CreateBuffer(plt, sizeof(RD::RayTraceProperties));
    RD::WriteBuffer(plt, rdRTProp, sizeof(RD::RayTraceProperties), &RTProp);

    RD::Buffer rdExtent  = RD::CreateBuffer(plt, sizeof(extent));
    RD::WriteBuffer(plt, rdExtent, sizeof(extent), extent);

    RD::Buffer rdImage   = RD::CreateImage(plt, extent[0], extent[1]);
    RD::Buffer rdImageScratch = RD::CreateBuffer(plt, extent[0] * extent[1] * CHANNEL * sizeof(float));

    RD::Buffer rdCamData = RD::CreateBuffer(plt, sizeof(camData));
    RD::WriteBuffer(plt, rdCamData, sizeof(camData), &camData);

    RD::Buffer rdSceneData = RD::CreateBuffer(plt, sizeof(RD::SceneProperties));
    RD::WriteBuffer(plt, rdSceneData, sizeof(sceneData), &sceneData);

    RD::Scene* scene = RD::Scene::Load(modelFile, plt, LOAD_CACHE);

    /* Build and configure pipeline */
    RD::DescriptorSet descSet = RD::CreateDescriptorSet({
        rdRTProp, rdImageScratch, rdImage,
        rdExtent, rdCamData, rdSceneData,
        INCLUDE_SCENE_DESC(scene)});
    RD::PipelineLayout layout = RD::CreatePipelineLayout({
        RD::BUFFER_TYPE, RD::BUFFER_TYPE, RD::IMAGE_TYPE,
        RD::BUFFER_TYPE, RD::BUFFER_TYPE, RD::BUFFER_TYPE,
        INCLUDE_SCENE_LAYOUT});

    /* Build shader module */
    char* shaderCode;
    size_t shaderSize;
    RD::read_kernel_file_str(shaderPath.c_str(), &shaderCode, &shaderSize);
    RD::ShaderModule shader = RD::CreateShaderModule(plt, shaderCode, shaderSize, "functName..");

    RD::Pipeline pipeline = RD::CreatePipeline({
        1,          // maxRayRecursionDepth
        layout,     // PipelineLayout
        {shader},   // ShaderModule
        {}          // ShaderGroup
    });

    /* Ray tracing */
    RD::BindPipeline(plt, pipeline);    
    RD::BindDescriptorSet(plt, descSet);

    CbData data = {
        .plt = plt,
        .extent = extent,
        .image = image,
        .rdImage = rdImage,
        .imageSize = imageSize,

        .rdCamData = rdCamData,
        .rdSceneData = rdSceneData,
        .rdRTProp = rdRTProp
    };

#ifdef OFF_SCREEN
    render((void*)&data, nullptr, nullptr, nullptr);
    printf("Writing image with extent: <%d, %d>\n", extent[0], extent[1]);
    stbi_write_jpg("output.jpg", extent[0], extent[1], RD_CHANNEL, data.image, 100);
#else
    renderLoop(render, &data);
#endif
}

#include "imgui.h"

void render(void* data, unsigned char** image, int* out_width, int* out_height)
{
    CbData *d = (CbData*) data;
    bool updated = false;

#ifndef OFF_SCREEN
    updated = RenderSceneConfigUI(d);
#endif

    RD::TraceRays(d->plt, 0,0,0, d->extent[0], d->extent[1]);

    /* Fetch result */
    RD::ReadBuffer(d->plt, d->rdImage, d->imageSize, d->image);

    /* Update frame sample counts */
    RD::RayTraceProperties RTProp;
    RD::ReadBuffer(d->plt, d->rdRTProp, sizeof(RD::RayTraceProperties), &RTProp);
    if (updated)
    {
        RTProp.totalSamples = 0;
    }
    else
    {
        RTProp.totalSamples += RTProp.batchSize;
    }
    RD::WriteBuffer(d->plt, d->rdRTProp, sizeof(RD::RayTraceProperties), &RTProp);


#ifndef OFF_SCREEN
    *image = d->image;
    *out_height = d->extent[1];
    *out_width  = d->extent[0];
#endif
}


bool RenderSceneConfigUI(CbData *d)
{
    bool updated = false;
    Camera camData;
    RD::ReadBuffer(d->plt, d->rdCamData, sizeof(camData), &camData);

    RD::SceneProperties scene;
    RD::ReadBuffer(d->plt, d->rdSceneData, sizeof(scene), &scene);

    RD::RayTraceProperties RTProp;
    RD::ReadBuffer(d->plt, d->rdRTProp, sizeof(RD::RayTraceProperties), &RTProp);

    {
        ImGui::Begin("Render Config");

        ImGui::Text("Camera:");
        updated |= ImGui::SliderFloat3("Camera Position", &camData.x, -40.0f, 40.0f);
        updated |= ImGui::SliderFloat3("Camera Rotation", &camData.wx, -10.0f, 10.0f);
        updated |= ImGui::SliderFloat("Camera focal", &camData.focal, -10.0f, 10.0f);

        ImGui::Text("Light:");
        updated |= ImGui::SliderFloat4("Light Direction", scene.lights[0].direction, -100.0f, 100.0f);
        updated |= ImGui::SliderFloat4("Light Color", scene.lights[0].color, 0.0f, 100.0f);

        ImGui::Text("Debug Mode:");
        updated |= ImGui::DragInt("Debug", (int*)&RTProp.debug, 1.0f, 0, 20);
        if (ImGui::Button("Previous Debug")){
            RTProp.debug++;
            updated = true;
        }
        ImGui::SameLine();
        if (ImGui::Button("Next Debug")){
            RTProp.debug--;
            updated = true;
        }

        ImGui::End();
    }

    if (updated)
    {
        RD::WriteBuffer(d->plt, d->rdCamData, sizeof(camData), &camData);
        RD::WriteBuffer(d->plt, d->rdSceneData, sizeof(scene), &scene);
        RD::WriteBuffer(d->plt, d->rdRTProp, sizeof(RD::RayTraceProperties), &RTProp);
    }

    return updated;
}