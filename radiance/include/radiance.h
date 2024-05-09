#pragma once
#define CL_TARGET_OPENCL_VERSION 120

#include "core.h"
#include "clcontext.h"

#define SHADER_LIB_PATH "/home/zekailin00/Desktop/ray-tracing/framework/radiance/shader"

namespace RD
{

typedef void* Handle;
typedef cl_mem TopAccelStruct;

typedef cl_mem Image;
typedef cl_mem ImageArray;
typedef cl_sampler Sampler;
typedef unsigned int Uniform;
typedef cl_mem Buffer;

enum DescriptorType
{
    ACCEL_STRUCT_TYPE,
    IMAGE_TYPE,
    IMAGE_ARRAY_TYPE,
    IMAGE_SAMPLER_TYPE,
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

typedef std::vector<Handle> DescriptorSet;
typedef std::vector<DescriptorType> PipelineLayout;

typedef cl_kernel ShaderModule;

#define SHADER_UNUSED (~0U)

struct PipelineCreateInfo
{
    PipelineLayout              layout;
    ShaderModule                modules;
};

typedef PipelineCreateInfo Pipeline;

struct Platform;

#define CHANNEL 4
#define RD_CHANNEL CHANNEL

// blocking, build AS
BottomAccelStruct BuildAccelStruct(Platform* platform, Mesh& mesh);
TopAccelStruct BuildAccelStruct(Platform* platform, std::vector<Instance>& instances);

void TopAccelStructToFile(Platform* platform, TopAccelStruct accelStruct, const char* path);
void FileToTopAccelStruct(Platform* platform, const char* path, TopAccelStruct* accelStruct);

typedef uint32_t AddressingMode;
// - Out-of-range image coordinates are clamped to the edge of the image.
#define RD_ADDRESS_CLAMP_TO_EDGE   CL_ADDRESS_CLAMP_TO_EDGE
// - Out-of-range image coordinates are assigned a border color value.
#define RD_ADDRESS_CLAMP           CL_ADDRESS_CLAMP
// - Out-of-range image coordinates read from the image
//   as if the image data were replicated in all dimensions.
#define RD_ADDRESS_REPEAT          CL_ADDRESS_REPEAT
// - Out-of-range image coordinates read from the image
//   as if the image data were replicated in all dimensions,
//   mirroring the image contents at the edge of each replication.
#define RD_ADDRESS_MIRRORED_REPEAT CL_ADDRESS_MIRRORED_REPEAT

typedef uint32_t FilterMode;
// - Returns the image element nearest to the image coordinate.
#define RD_FILTER_NEAREST          CL_FILTER_NEAREST
//  - Returns a weighted average of the four image elements
//    nearest to the image coordinate.
#define RD_FILTER_LINEAR           CL_FILTER_LINEAR


Buffer CreateBuffer(Platform* platform, unsigned int size);
Image CreateImage(Platform* platform, unsigned int width, unsigned int height);
ImageArray CreateImageArray(Platform* platform, unsigned int width, unsigned int height, unsigned int arraySize);
Sampler CreateSampler(Platform* platform, AddressingMode addressingMode, FilterMode filterMode);


void ReadImage(Platform* platform, ImageArray handle,
    unsigned int width, unsigned int height, size_t arrayIndex, void* data);
void WriteImage(Platform* platform, ImageArray handle,
    unsigned int width, unsigned int height, size_t arrayIndex, void* data);
void ReadBuffer(Platform* platform, Buffer handle,
    size_t size, void* data, size_t offset = 0);
void WriteBuffer(Platform* platform, Buffer handle,
    size_t size, void* data, size_t offset = 0);

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
