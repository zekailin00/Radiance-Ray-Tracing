#include <cassert>

#include "radiance.h"

#define STB_IMAGE_WRITE_IMPLEMENTATION
#include "stb_image_write.h"


bool modelLoader(
    std::vector<RD::Vec3>& vertices,
    std::vector<RD::Triangle>& triangles,
    std::string modelFile)
{
    // Create an instance of the Importer class
    Assimp::Importer importer;

    // And have it read the given file with some example postprocessing
    // Usually - if speed is not the most important aspect for you - you'll
    // probably to request more postprocessing than we do in this example.
    const aiScene* scene = importer.ReadFile( modelFile,
        aiProcess_GenSmoothNormals       |
        aiProcess_Triangulate            |
        aiProcess_JoinIdenticalVertices  |
        aiProcess_SortByPType);

    // If the import failed, report it
    if (nullptr == scene) {
        printf("%s", importer.GetErrorString());
        return false;
    }

    assert(scene->mNumMeshes == 1);

    const aiMesh* mesh = scene->mMeshes[0];

    printf("Number of vertices: %d\n", mesh->mNumVertices);
    printf("Number of faces: %d\n", mesh->mNumFaces);

    vertices.resize(mesh->mNumVertices);
    triangles.resize(mesh->mNumFaces);

    for (size_t i = 0; i < mesh->mNumVertices; i++)
    {
        vertices[i] = mesh->mVertices[i];
    }

    for (size_t i = 0; i < mesh->mNumFaces; i++)
    {
        assert(mesh->mFaces[i].mNumIndices == 3);

        triangles[i].idx0 = mesh->mFaces[i].mIndices[0];
        triangles[i].idx1 = mesh->mFaces[i].mIndices[1];
        triangles[i].idx2 = mesh->mFaces[i].mIndices[2];
    }

    return true;
}

int main()
{
    std::string modelFile =
        "/home/zekailin00/Desktop/ray-tracing/framework/assets/stanford-bunny.obj";
    std::string shaderPath =
        "/home/zekailin00/Desktop/ray-tracing/framework/samples/shader.cl";
    unsigned int extent[2] = {1080, 1080};
    size_t imageSize = extent[0] * extent[1] * RD_CHANNEL;
    uint8_t* image = (uint8_t*)malloc(imageSize);

    /* Intialize platform */
    RD::Platform* plt = RD::Platform::GetPlatform();

    /* Build shader module */
    char* shaderCode;
    size_t shaderSize;
    RD::read_kernel_file_str(shaderPath.c_str(), &shaderCode, &shaderSize);
    RD::ShaderModule shader = RD::CreateShaderModule(plt, shaderCode, shaderSize, "functName..");

    /* Load mesh and build accel struct */
    RD::Mesh mesh;
    modelLoader(mesh.vertexData, mesh.indexData, modelFile);
    RD::BottomAccelStruct rdBottomAS = RD::BuildAccelStruct(plt, mesh);

    std::vector<RD::Instance> instanceList =
    {
        {
            {
                {1.0f, 1.0f, 1.0f}, // scaling
                aiQuaterniont<float>(), // rotation
                {0.0f, 0.0f, 0.0f} // position
            }, // transform
            0, // SBT offset
            10, // customInstanceID
            rdBottomAS // accelStruct handle
        },
        {
            {
                {1.0f, 1.0f, 1.0f}, // scaling
                aiQuaterniont<float>(), // rotation
                {0.0f, -.1f, 0.0f} // position
            }, // transform
            0, // SBT offset
            40, // customInstanceID
            rdBottomAS // accelStruct handle
        },
        {
            {
                {1.0f, 1.0f, 1.0f}, // scaling
                aiQuaterniont<float>(), // rotation
                {0.0f, -.2f, 0.0f} // position
            }, // transform
            0, // SBT offset
            70, // customInstanceID
            rdBottomAS // accelStruct handle
        }, 
        {
            {
                {1.0f, 1.0f, 1.0f}, // scaling
                aiQuaterniont<float>(), // rotation
                {0.1f, 0.0f, 0.0f} // position
            }, // transform
            0, // SBT offset
            100, // customInstanceID
            rdBottomAS // accelStruct handle
        },
        {
            {
                {1.0f, 1.0f, 1.0f}, // scaling
                aiQuaterniont<float>(), // rotation
                {0.1f, -.1f, 0.0f} // position
            }, // transform
            0, // SBT offset
            130, // customInstanceID
            rdBottomAS // accelStruct handle
        },
        {
            {
                {1.0f, 1.0f, 1.0f}, // scaling
                aiQuaterniont<float>(), // rotation
                {0.1f, -.2f, 0.0f} // position
            }, // transform
            0, // SBT offset
            160, // customInstanceID
            rdBottomAS // accelStruct handle
        }, 
        {
            {
                {1.0f, 1.0f, 1.0f}, // scaling
                aiQuaterniont<float>(), // rotation
                {-0.1f, 0.0f, 0.0f} // position
            }, // transform
            0, // SBT offset
            190, // customInstanceID
            rdBottomAS // accelStruct handle
        },
        {
            {
                {1.0f, 1.0f, 1.0f}, // scaling
                aiQuaterniont<float>(), // rotation
                {-0.1f, -.1f, 0.0f} // position
            }, // transform
            0, // SBT offset
            220, // customInstanceID
            rdBottomAS // accelStruct handle
        },
        {
            {
                {1.0f, 1.0f, 1.0f}, // scaling
                aiQuaterniont<float>(), // rotation
                {-0.1f, -.2f, 0.0f} // position
            }, // transform
            0, // SBT offset
            250, // customInstanceID
            rdBottomAS // accelStruct handle
        }
    };

    RD::TopAccelStruct rdTopAS = RD::BuildAccelStruct(plt, instanceList);

    /* Define pipeline data inputs */
    RD::Buffer rdImage            = RD::CreateImage(plt, extent[0], extent[1]);
    RD::Buffer rdExtent           = RD::CreateBuffer(plt, sizeof(extent));
    RD::WriteBuffer(plt, rdExtent, sizeof(extent), extent);

    /* Build and configure pipeline */
    RD::DescriptorSet descSet = RD::CreateDescriptorSet(
        {rdImage, rdExtent, rdTopAS});
    RD::PipelineLayout layout = RD::CreatePipelineLayout(
        {RD::IMAGE_TYPE, RD::BUFFER_TYPE, RD::ACCEL_STRUCT_TYPE});
    RD::Pipeline pipeline     = RD::CreatePipeline({
        1,          // maxRayRecursionDepth
        layout,     // PipelineLayout
        {shader},   // ShaderModule
        {}          // ShaderGroup
    });

    /* Ray tracing */
    RD::BindPipeline(plt, pipeline);    
    RD::BindDescriptorSet(plt, descSet);
    RD::TraceRays(plt, 0,0,0, extent[0], extent[1]);

    /* Fetch result */
    RD::ReadBuffer(plt, rdImage, imageSize, image);
    stbi_write_jpg("output.jpg", extent[0], extent[1], RD_CHANNEL, image, 100);
}