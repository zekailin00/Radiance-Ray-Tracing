typedef struct {
    float x, y;
} Vec2;

typedef struct {
    float x, y, z;
} Vec3;

typedef struct {
    float x, y, z, w;
} Vec4;

typedef struct {
    Vec4 c0, c1, c2, c3;
} Mat4x4;

typedef unsigned int Handle;
typedef unsigned int AccelStruct;
typedef unsigned int Image;
typedef unsigned int Uniform;
typedef unsigned int Buffer;

typedef unsigned int DescriptorSet;
typedef unsigned int PipelineLayout;
typedef unsigned int ShaderModule;
typedef unsigned int Pipeline;

typedef unsigned int Index;
struct Vertex
{
    Vec3 pos;
    Vec3 normal;
    Vec2 texCoord;
};

// Host mesh data
struct Mesh
{
    Vertex* vertexData;
    unsigned int vertexSize;
    unsigned int vertexOffset; // FIXME: For shaders to access the buffer?
    unsigned int vertexStride; // TODO: For uv and normal. How to build AS

    Index* indexData;
    unsigned int indexSize;
    unsigned int indexOffset; // FIXME: For shaders to access the buffer?
};

// Host instance data
struct Instance
{
    Mat4x4 transform;
    unsigned int SBTOffset;
    AccelStruct handle;
};

#define SHADER_UNUSED (~0U)
struct ShaderGroup
{
    ShaderModule generalShader; // from Vulkan. Either miss or raygen
    ShaderModule closestHitShader;
    ShaderModule anyHitShader; // TODO: names of the shader functions 
    //ShaderModule intersectionShader; // No intersection shader. triangles only
};

enum DescriptorType
{
    ACCEL_STRUCT_TYPE,
    IMAGE_TYPE,
    BUFFER_TYPE,
    TEX_ARRAY_TYPE
};

struct PipelineCreateInfo
{
    unsigned int   maxRayRecursionDepth;
    PipelineLayout layout;

    ShaderModule*  modules;
    unsigned int   moduleCount;

    ShaderGroup*   groups;
    unsigned int   groupCount;
};

// blocking, build AS
AccelStruct BuildAccelStruct(Mesh& mesh);
AccelStruct BuildAccelStruct(Instance* instances, unsigned int size);

Image  CreateImage(unsigned width, unsigned int height);
Buffer CreateBuffer(void* data, unsigned size); // TODO: 
Image  CreateImageArray(); // TODO:

DescriptorSet  CreateDescriptorSet(Handle* handles, unsigned int size); // allocate GPU resources
PipelineLayout CreatePipelineLayout(DescriptorType* descriptorTypes, unsigned int size);
ShaderModule   CreateShaderModule(char* code, unsigned int size, char* name);
Pipeline       CreatePipeline(PipelineCreateInfo* pipelineCreateInfo); // upload shader code to GPU

bool BindPipeline(Pipeline pipeline);
bool BindDescriptorSet(DescriptorSet descriptorSet);
bool TraceRays(
    unsigned int raygenGroupIndex
    unsigned int missGroupIndex,
    unsigned int hitGroupIndex,
    unsigned int width,
    unsigned int height
);