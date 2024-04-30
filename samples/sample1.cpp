#include <cassert>

#include "radiance.h"
#include "sceneBuilder.h"
#include "inspector.h"

#define STB_IMAGE_WRITE_IMPLEMENTATION
#include "stb_image_write.h"

#define OFF_SCREEN
#define LOAD_FROM_CACHE

#ifdef LOAD_FROM_CACHE
#define LOAD_CACHE true
#else
#define LOAD_CACHE false
#endif
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
bool RenderSceneConfigUI(CbData *d);
void rayTracer(std::string& modelFile, std::string& shaderPath,
    RD::RayTraceProperties& RTProp, RD::PhysicalCamera& camData, RD::SceneProperties& sceneData);

inline float blenderToXRad(float xDeg)
{
    xDeg = -90.0 - xDeg;
    float xRad = xDeg / 180.0 * 3.14159;
    return xRad;
}

inline float blenderToYRad(float yDeg)
{
    float yRad = yDeg / 180.0 * 3.14159;
    return yRad;
}

inline float blenderToZRad(float zDeg)
{
    float zRad = zDeg / 180.0 * 3.14159;
    return zRad;
}

inline void blenderToCameraRotation(float xDeg, float yDeg, float zDeg, float& xRad, float& yRad, float& zRad)
{
    xRad = blenderToXRad(xDeg);
    yRad = blenderToZRad(zDeg - 180);
    zRad = blenderToYRad(yDeg - 180);
}

inline void blenderToCameraTranslate(float x, float y, float z, float& xOut, float& yOut, float& zOut)
{
    xOut = xOut;
    yOut = z;
    zOut = -y;
}

RD::DirLight blenderToDirLight(float xDeg, float zDeg, float intensity)
{
    float xRad = blenderToXRad(xDeg);
    float zRad = blenderToZRad(zDeg);

    aiMatrix3x3 eulerX;
    aiMatrix3x3::Rotation(xRad, {-1,0,0}, eulerX);

    aiMatrix3x3 eulerY;
    aiMatrix3x3::Rotation(zRad, {0,1,0}, eulerY);

    aiVector3f lightDir = {0, 0, 1};
    lightDir = eulerX * eulerY * lightDir;

    RD::DirLight light = {
        .direction = {lightDir[0], lightDir[1], lightDir[2], 0.0f},
        .color = {intensity, intensity, intensity, 1.0f}
    };
    return light;
}

int main()
{
    std::string modelFile =
        // "/home/zekailin00/Desktop/ray-tracing/framework/assets/Cornell2.glb"; // helmet
        // "/home/zekailin00/Desktop/ray-tracing/framework/assets/Cornell-armor.glb"; //armor
        "/home/zekailin00/Desktop/ray-tracing/framework/assets/benchmark/cornell-pbr-standard.glb";
        // "/home/zekailin00/Desktop/ray-tracing/framework/assets/benchmark/cornell-transmission.glb";

    std::string shaderPath = "/home/zekailin00/Desktop/ray-tracing/framework/samples/shader.cl";

    RD::SceneProperties sceneData;
    sceneData.lightCount[0] = 1;

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

    // material test
    RD::PhysicalCamera camData = {
        .widthPixel = 2000.0f,       .heightPixel = 2000.0f,
        .focalLength = 0.036f,       .sensorWidth = 0.036f,
        .focalDistance = 2.0f,       .fStop = 0.00f,
        .x  = 0.00f,  .y  = 6.0f,    .z = -10.0f,
        .wx = 0.00f,  .wy = 3.1415f, .wz =  0.00f
    };
    sceneData.lights[0] = blenderToDirLight(-95.0f, 5.0f, 10.0f);

    // // cornell - details
    // RD::PhysicalCamera camData = {
    //     .widthPixel = 1000.0f,      .heightPixel = 1000.0f,
    //     .focalLength = 0.030f,      .sensorWidth = 0.036f,
    //     .focalDistance = 2.0f,      .fStop = 0.00f
    // };
    // sceneData.lights[0] = blenderToDirLight(-95.0f, 20.0f, 10.0f);
    // blenderToCameraTranslate(0, 9, 7.5, camData.x, camData.y, camData.z);
    // blenderToCameraRotation(-115, 180, 0, camData.wx, camData.wy, camData.wz);

    /* Define pipeline data inputs */
    RD::RayTraceProperties RTProp = {
        .totalSamples = 0,  .batchSize = 10,
        .depth = 8,         .debug = 0
    };


    rayTracer(modelFile, shaderPath, RTProp, camData, sceneData);
}

void rayTracer(std::string& modelFile, std::string& shaderPath,
    RD::RayTraceProperties& RTProp, RD::PhysicalCamera& camData, RD::SceneProperties& sceneData)
{
    size_t imageSize = camData.widthPixel * camData.heightPixel * RD_CHANNEL;
    uint8_t* image = (uint8_t*)malloc(imageSize);

    /* Intialize platform */
    RD::Platform* plt = RD::Platform::GetPlatform();

    RD::Buffer rdRTProp = RD::CreateBuffer(plt, sizeof(RD::RayTraceProperties));
    RD::WriteBuffer(plt, rdRTProp, sizeof(RD::RayTraceProperties), &RTProp);

    RD::Buffer rdImage   = RD::CreateImage(plt, camData.widthPixel, camData.heightPixel);
    RD::Buffer rdImageScratch = RD::CreateBuffer(plt, imageSize * sizeof(float));

    RD::Buffer rdCamData = RD::CreateBuffer(plt, sizeof(camData));
    RD::WriteBuffer(plt, rdCamData, sizeof(camData), &camData);

    RD::Buffer rdSceneData = RD::CreateBuffer(plt, sizeof(RD::SceneProperties));
    RD::WriteBuffer(plt, rdSceneData, sizeof(sceneData), &sceneData);

    RD::Scene* scene = RD::Scene::Load(modelFile, plt, LOAD_CACHE);

    /* Build and configure pipeline */
    RD::DescriptorSet descSet = RD::CreateDescriptorSet({
        rdRTProp, rdImageScratch, rdImage,
        rdCamData, rdSceneData,
        INCLUDE_SCENE_DESC(scene)});
    RD::PipelineLayout layout = RD::CreatePipelineLayout({
        RD::BUFFER_TYPE, RD::BUFFER_TYPE, RD::IMAGE_TYPE,
        RD::BUFFER_TYPE, RD::BUFFER_TYPE,
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

    unsigned int extent[2] = {
        (unsigned int) camData.widthPixel,
        (unsigned int) camData.heightPixel
    };
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
    time_t ltime;
    time(&ltime);
    char* time = ctime(&ltime);
    std::string fileName = "output.";
    fileName += time;
    fileName += ".jpg";

    render((void*)&data, nullptr, nullptr, nullptr);
    stbi_write_jpg(fileName.c_str(), extent[0], extent[1], RD_CHANNEL, data.image, 100);
    printf("Writing image with extent: <%d, %d>\n", extent[0], extent[1]);
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

#ifdef OFF_SCREEN
    time_t start_t, end_t;
    double diff_t;
    char* timeStr;

    time(&start_t);
    timeStr = ctime(&start_t);
    printf("\nStart of ray tracing: %s", timeStr);
#endif

    RD::TraceRays(d->plt, 0,0,0, d->extent[0], d->extent[1]);

    /* Fetch result */
    RD::ReadBuffer(d->plt, d->rdImage, d->imageSize, d->image);

#ifdef OFF_SCREEN
    time(&end_t);
    timeStr = ctime(&start_t);
    printf("End of ray tracing: %s", timeStr);
    diff_t = difftime(end_t, start_t);
    printf("Execution time = %f\n", diff_t);
#endif

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
    RD::PhysicalCamera camData;
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
        updated |= ImGui::SliderFloat("Camera focal", &camData.focalLength, -10.0f, 10.0f);

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