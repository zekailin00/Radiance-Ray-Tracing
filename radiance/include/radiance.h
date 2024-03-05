#pragma once
#define CL_TARGET_OPENCL_VERSION 120

#include "core.h"
#include "clcontext.h"

#define SHADER_LIB_PATH "/home/zekailin00/Desktop/ray-tracing/framework/radiance/shader"

namespace RD
{

typedef cl_mem Handle;
typedef cl_mem TopAccelStruct;

typedef cl_mem Image;
typedef unsigned int Uniform;
typedef cl_mem Buffer;

enum DescriptorType
{
    ACCEL_STRUCT_TYPE,
    IMAGE_TYPE,
    BUFFER_TYPE,
    TEX_ARRAY_TYPE
};

// Host mesh data
struct Mesh
{
    std::vector<Vec3> vertexData;
    std::vector<Triangle> indexData;
};

struct BVHNode;
struct _BottomAccelStruct
{
    BVHNode* root;
    std::vector<char> data;
};

typedef _BottomAccelStruct* BottomAccelStruct;

// Host instance data
struct Instance
{
    Mat4x4 transform; // row majorx
    unsigned int SBTOffset;
    // unsigned int instanceID; // automatically computed when building TopAS
    unsigned int customInstanceID;
    BottomAccelStruct bottomAccelStruct;
};

typedef std::vector<cl_mem> DescriptorSet;
typedef std::vector<DescriptorType> PipelineLayout;

typedef cl_kernel ShaderModule;

#define SHADER_UNUSED (~0U)
struct ShaderGroup
{
    ShaderModule generalShader; // from Vulkan. Either miss or raygen
    ShaderModule closestHitShader;
    ShaderModule anyHitShader; // TODO: names of the shader functions 
    //ShaderModule intersectionShader; // No intersection shader. triangles only
};

struct PipelineCreateInfo
{
    unsigned int                maxRayRecursionDepth;
    PipelineLayout              layout;

    std::vector<ShaderModule>   modules;
    std::vector<ShaderGroup>    groups;
};

typedef PipelineCreateInfo Pipeline;

struct Platform;

#define CHANNEL 4
#define RD_CHANNEL CHANNEL

// blocking, build AS
BottomAccelStruct BuildAccelStruct(Platform* platform, Mesh& mesh);
TopAccelStruct BuildAccelStruct(Platform* platform, std::vector<Instance>& instances);

void TopAccelStructToFile(Platform* platform, TopAccelStruct accelStruct, char* path);
void FileToTopAccelStruct(Platform* platform, char* path, TopAccelStruct* accelStruct);

Image  CreateImage(Platform* platform, unsigned int width, unsigned int height);
Buffer CreateBuffer(Platform* platform, unsigned int size); // TODO:
Image  CreateImageArray(); // TODO:

void ReadBuffer(Platform* platform,Handle handle, size_t size, void* data, size_t offset = 0);
void WriteBuffer(Platform* platform, Handle handle, size_t size, void* data, size_t offset = 0);

DescriptorSet   CreateDescriptorSet(std::vector<Handle> handles); // allocate GPU resources
PipelineLayout  CreatePipelineLayout(std::vector<DescriptorType> descriptorTypes);
ShaderModule    CreateShaderModule(Platform* platform, char* code, unsigned int size, char* name);
Pipeline        CreatePipeline(PipelineCreateInfo pipelineCreateInfo); // upload shader code to GPU

void BindPipeline(Platform* platform, Pipeline pipeline);
void BindDescriptorSet(Platform* platform, DescriptorSet descriptorSet);

void TraceRays(Platform* platform,
    unsigned int raygenGroupIndex,
    unsigned int missGroupIndex,
    unsigned int hitGroupIndex,
    unsigned int width,
    unsigned int height
);

struct Platform
{
    static Platform* GetPlatform()
    {
        static Platform ctx;
        if (!ctx.initialized)
        {
            ctx.clContext = CLContext::GetCLContext();
            ctx.initialized = true;
            printf("Platform initialized.\n");
        }
        return &ctx;
    }

    ~Platform()
    {
        printf("Platform destroyed.\n");
        clContext->Cleanup();
    }

    Pipeline activePipeline;
    CLContext* clContext = nullptr;
    bool initialized = false;

private:
    Platform() = default;
    void operator=(Platform&) = delete;
    Platform(Platform&) = delete;
};

} // namespace RD
