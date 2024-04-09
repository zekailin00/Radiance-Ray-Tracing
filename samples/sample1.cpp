#include <cassert>

#include "radiance.h"
#include "sceneBuilder.h"
#include "inspector.h"

#define STB_IMAGE_WRITE_IMPLEMENTATION
#include "stb_image_write.h"

#define OFF_SCREEN

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

void render(void* data, unsigned char** image, int* out_width, int* out_height);

void GetInstanceList(std::vector<RD::Instance>& instanceList, RD::BottomAccelStruct rdBottomAS);
void GetMaterialList(std::vector<RD::Material>& materialList);
void GetSceneData(RD::SceneProperties* sceneData);
bool RenderSceneConfigUI(CbData *d);

int main()
{
    std::string modelFile =
        "/home/zekailin00/Desktop/ray-tracing/framework/assets/scene-loader-test.gltf";
    std::string shaderPath =
        "/home/zekailin00/Desktop/ray-tracing/framework/samples/shader.cl";
    unsigned int extent[2] = {1080, 1080};
    size_t imageSize = extent[0] * extent[1] * RD_CHANNEL;
    uint8_t* image = (uint8_t*)malloc(imageSize);

    /* Define pipeline data inputs */
    RD::RayTraceProperties RTProp = {
        .totalSamples = 0,
        .batchSize = 10,
        .depth = 2,
        .debug = 0
    };

    float camData[4] = {0.0f, -1.0f, -30.0f, 3.14f};

    RD::SceneProperties sceneData;
    sceneData.lightCount[0] = 1;
    sceneData.lights[0] = {
        .direction = {0.0f, 60.0f, 20.0f},
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
    RD::WriteBuffer(plt, rdCamData, sizeof(camData), camData);

    RD::Buffer rdSceneData = RD::CreateBuffer(plt, sizeof(RD::SceneProperties));
    RD::WriteBuffer(plt, rdSceneData, sizeof(sceneData), &sceneData);

    RD::Scene* scene = RD::Scene::Load(modelFile, plt);

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

void GetSceneData(RD::SceneProperties* sceneData)
{
    sceneData->lightCount[0] = 1;
    sceneData->lights[0] = {
        .direction = {0.0f, 60.0f, 20.0f},
        .color = {10.0f, 10.0f, 10.0f, 1.0f}
    };
}