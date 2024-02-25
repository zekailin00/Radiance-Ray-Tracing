#include "../radiance/radiance.hpp"
#include <vector>

Vertex* sceneVertexData;
unsigned int* sceneIndexData;
unsigned int sceneVertexCount, mesh1VertexCount, mesh2VertexCount;
unsigned int sceneIndexCount, mesh1IndexCount, mesh2IndexCount;

Mesh mesh1;
Mesh mesh2;

struct CameraData
{
    Mat4x4 transform;
    Vec4 fov;
    // ...
} cameraData;

AccelStruct buildAccelStruct()
{
    const unsigned int INST_SIZE = 2;
    //FIXME: single vertex and index buffer for the scene
    // Shaders have access to the buffers and the offsets?

    mesh1 = {
        sceneVertexData, mesh1VertexCount,
        0 /*offset*/,sizeof(Vertex),
        sceneIndexData,  mesh1IndexCount,  0 /*offset*/
        };
    AccelStruct BottomASHandle1 = BuildAccelStruct(&mesh1);


    mesh2 = {
        sceneVertexData, mesh2VertexCount,
        mesh1VertexCount * sizeof(Vertex) /*offset*/, sizeof(Vertex),
        sceneIndexData,  mesh2IndexCount,
        mesh1IndexCount * sizeof(Index) 
    };
    AccelStruct BottomASHandle2 = BuildAccelStruct(&mesh2);


    Instance instanceList[INST_SIZE] = {
        {Mat4x4(), 0, BottomASHandle1},
        {Mat4x4(), 1, BottomASHandle2}
    };
    AccelStruct topASHandle = BuildAccelStruct(instanceList, INST_SIZE);

    return topASHandle;

    // Vulkan uses device side addresses with another device side buffer
    // Buffer instanceBuffer = CreateBuffer(INST_SIZE);
    // BuildAccelStruct(instanceBuffer)?
}

DescriptorSet createDescriptors(AccelStruct topASHandle)
{
    unsigned int width = 1920, height = 1080;

    Image  renderImageHandle   = CreateImage(width, height);
    Buffer vertexBufHandle     = CreateBuffer(sceneVertexData, sceneVertexCount);
    Buffer indexBufHandle      = CreateBuffer(sceneIndexData,  sceneIndexCount);
    Buffer camDataBufHandle    = CreateBuffer(&cameraData,     sizeof(CameraData));
    Image  texArrayHandle      = CreateImageArray(); // TODO:

    // Bind to pipeline before launching rayTracing command on the host side.
    DescriptorSet descHandle = CreateDescriptorSet(
        {topASHandle, renderImageHandle,
         vertexBufHandle, indexBufHandle,
         camDataBufHandle, texArrayHandle}, 6/*handle count*/);

    return descHandle;
}

Pipeline buildRayTracePipeline()
{
    // Vulkan allows having each descriptor binding to any specified shader stage
    // but here all descriptors bind to all shader stages.
    // Match to Descriptor set.
    unsigned int handleCount = 5;
    PipelineLayout pipelineLayoutHandle = CreatePipelineLayout(
        {ACCEL_STRUCT_TYPE, IMAGE_TYPE, BUFFER_TYPE, BUFFER_TYPE, BUFFER_TYPE, TEX_ARRAY_TYPE},
        handleCount
    );

    std::vector<ShaderModule> shaderStages;
    std::vector<ShaderGroup> shaderGroups;

    char* code;
    unsigned int codeSize;

    LoadShader("path/raygen.cl", &code, &codeSize);
    ShaderModule rayGenHandle = CreateShaderModule(code, codeSize, "raygen");
    shaderStages.push_back(rayGenHandle);
    shaderGroups.push_back({shaderStages.size()-1, SHADER_UNUSED, SHADER_UNUSED});

    LoadShader("path/miss.cl", &code, &codeSize);
    ShaderModule missHandle = CreateShaderModule(code, codeSize, "miss");
    shaderStages.push_back(missHandle);
    shaderGroups.push_back({shaderStages.size()-1, SHADER_UNUSED, SHADER_UNUSED});

    ShaderModule closestHitHandle, anyHitHandle;

    LoadShader("path/mesh1ClosestHit.cl", &code, &codeSize);
    closestHitHandle = CreateShaderModule(code, codeSize, "unique_name0");
    LoadShader("path/mesh1AnyHit.cl",     &code, &codeSize);
    anyHitHandle     = CreateShaderModule(code, codeSize, "unique_name1");
    shaderStages.push_back(closestHitHandle);
    shaderStages.push_back(anyHitHandle);
    shaderGroups.push_back({SHADER_UNUSED, shaderStages.size()-2, shaderStages.size()-1});

    LoadShader("path/mesh2ClosestHit.cl", &code, &codeSize);
    closestHitHandle = CreateShaderModule(code, codeSize, "unique_name2");
    LoadShader("path/mesh2AnyHit.cl",     &code, &codeSize);
    anyHitHandle     = CreateShaderModule(code, codeSize, "unique_name3");
    shaderStages.push_back(closestHitHandle);
    shaderStages.push_back(anyHitHandle);
    shaderGroups.push_back({SHADER_UNUSED, shaderStages.size()-2, shaderStages.size()-1});

    PipelineCreateInfo info;
    info.maxRayRecursionDepth = 1;
    info.layout               = pipelineLayoutHandle;
    info.modules              = shaderStages.data();
    info.moduleCount          = shaderStages.size();
    info.groups               = shaderGroups.data();
    info.groupCount           = shaderGroups.size();

    Pipeline pipelineHandle = CreatePipeline(&info);

    return pipelineHandle;
}

// not needed?
void buildShaderBindingTable(Pipeline pipelineHandle)
{
    std::vector<uint8_t> shaderGroupHandles;
    GetRayTracingShaderGroupHandles(pipelineHandle, shaderGroupHandles.data());

    Buffer raygenBufHandle = CreateBuffer();
    Buffer missBufHandle = CreateBuffer();
    Buffer hitBufHandle = CreateBuffer();

    // write handles from shaderGroupHandles to the buffers
    // those tables are used in ray tracing
}


void rayTrace(Pipeline pipelineHandle, DescriptorSet descHandle)
{
    BindPipeline(pipelineHandle);
    BindDescriptorSet(descHandle);

    TraceRays(
        0,     // raygen group index
        1,     // miss group index
        2,     // hit group index
        1920,  // width
        1080   // height
    );

    // example of rendering shadow
    TraceRays(
        6,     // raygen group index
        7,     // miss group index
        2,     // hit group index
        1920,  // width
        1080   // height
    ); // TODO: check and support supersampling 
}

int main()
{
    AccelStruct topASHandle = buildAccelStruct();
    DescriptorSet descHandle = createDescriptors(topASHandle);
    Pipeline pipelineHandle = buildRayTracePipeline();
    buildShaderBindingTable(pipelineHandle);

    bool quit = false;
    while(!quit)
    {
        rayTrace(pipelineHandle, descHandle);
        displayImage();
    }
}