#include <cassert>

#include "radiance.h"

#define STB_IMAGE_WRITE_IMPLEMENTATION
#include "stb_image_write.h"

#include "inspector.h"

#define OFF_SCREEN

bool modelLoader(
    std::vector<RD::Vec3>& vertices,
    std::vector<RD::Vec3>& normals,
    std::vector<RD::Vec3>& uvs,
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
    normals.resize(mesh->mNumVertices);
    uvs.resize(mesh->mNumVertices);
    triangles.resize(mesh->mNumFaces);

    for (size_t i = 0; i < mesh->mNumVertices; i++)
    {
        vertices[i] = mesh->mVertices[i];
        normals[i]  = mesh->mNormals[i];
        uvs[i]      = mesh->mTextureCoords[1]?mesh->mTextureCoords[1][i]:aiVector3D();
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

struct CbData
{
    RD::Platform* plt;
    unsigned int* extent;
    uint8_t* image;
    RD::Buffer rdImage;
    size_t imageSize;

    RD::Buffer rdCamData;
    RD::Buffer rdMatData;
    RD::Buffer rdSceneData;
};

void render(void* data, unsigned char** image, int* out_width, int* out_height);

void GetInstanceList(std::vector<RD::Instance>& instanceList, RD::BottomAccelStruct rdBottomAS);
void GetMaterialList(std::vector<RD::Material>& materialList);
void GetSceneData(RD::SceneProperties* sceneData);
void RenderSceneConfigUI(CbData *d);

int main()
{
    std::string modelFile =
        "/home/zekailin00/Desktop/ray-tracing/framework/assets/monkey-smooth.obj";
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
    std::vector<RD::Vec3> normals;
    std::vector<RD::Vec3> uvs;
    modelLoader(mesh.vertexData, normals, uvs, mesh.indexData, modelFile);

#define AS_PATH "./bvh-cache.bin"
// #define LOAD_FROM_FILE

#ifndef LOAD_FROM_FILE
    RD::BottomAccelStruct rdBottomAS = RD::BuildAccelStruct(plt, mesh);
    std::vector<RD::Instance> instanceList;
    GetInstanceList(instanceList, rdBottomAS);

    RD::TopAccelStruct rdTopAS = RD::BuildAccelStruct(plt, instanceList);
    RD::TopAccelStructToFile(plt, rdTopAS, AS_PATH);
#else
    RD::TopAccelStruct rdTopAS;
    RD::FileToTopAccelStruct(plt, AS_PATH, &rdTopAS);
#endif


    /* Define pipeline data inputs */
    unsigned int depth = 5;
    RD::Buffer rdDepth = RD::CreateBuffer(plt, sizeof(depth));
    RD::WriteBuffer(plt, rdDepth, sizeof(depth), &depth);

    RD::Buffer rdImage   = RD::CreateImage(plt, extent[0], extent[1]);
    RD::Buffer rdExtent  = RD::CreateBuffer(plt, sizeof(extent));
    RD::WriteBuffer(plt, rdExtent, sizeof(extent), extent);

    float camData[4] = {0.0f, -1.0f, -10.0f, 0.0f};
    RD::Buffer rdCamData = RD::CreateBuffer(plt, sizeof(camData));
    RD::WriteBuffer(plt, rdCamData, sizeof(camData), camData);

    unsigned int vertexSize = mesh.vertexData.size() * sizeof(RD::Vec3);
    RD::Buffer rdVertexData = RD::CreateBuffer(plt, vertexSize);
    RD::WriteBuffer(plt, rdVertexData, vertexSize, mesh.vertexData.data());

    unsigned int normalSize = normals.size() * sizeof(RD::Vec3);
    RD::Buffer rdNormalData = RD::CreateBuffer(plt, normalSize);
    RD::WriteBuffer(plt, rdNormalData, normalSize, normals.data());

    unsigned int uvSize = uvs.size() * sizeof(RD::Vec3);
    RD::Buffer rdUVData = RD::CreateBuffer(plt, uvSize);
    RD::WriteBuffer(plt, rdUVData, uvSize, uvs.data());

    unsigned int indexSize = mesh.indexData.size() * sizeof(RD::Triangle);
    RD::Buffer rdIndexData = RD::CreateBuffer(plt, indexSize);
    RD::WriteBuffer(plt, rdIndexData, indexSize, mesh.indexData.data());

    std::vector<RD::Material> materialList;
    GetMaterialList(materialList);
    unsigned int matSize = materialList.size() * sizeof(RD::Material);
    RD::Buffer rdMatData = RD::CreateBuffer(plt, matSize);
    RD::WriteBuffer(plt, rdMatData, matSize, materialList.data());

    RD::SceneProperties sceneData;
    GetSceneData(&sceneData);
    RD::Buffer rdSceneData = RD::CreateBuffer(plt, sizeof(RD::SceneProperties));
    RD::WriteBuffer(plt, rdSceneData, sizeof(sceneData), &sceneData);


    /* Build and configure pipeline */
    RD::DescriptorSet descSet = RD::CreateDescriptorSet({
        rdDepth,      rdImage,      rdExtent,   rdCamData,
        rdVertexData, rdNormalData, rdUVData,
        rdIndexData,  rdMatData,    rdSceneData,
        rdTopAS});
    RD::PipelineLayout layout = RD::CreatePipelineLayout({
        RD::BUFFER_TYPE, RD::IMAGE_TYPE,  RD::BUFFER_TYPE, RD::BUFFER_TYPE,
        RD::BUFFER_TYPE, RD::BUFFER_TYPE, RD::BUFFER_TYPE,
        RD::BUFFER_TYPE, RD::BUFFER_TYPE, RD::BUFFER_TYPE,
        RD::ACCEL_STRUCT_TYPE});
    RD::Pipeline pipeline     = RD::CreatePipeline({
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
        .rdMatData = rdMatData,
        .rdSceneData = rdSceneData
    };

#ifdef OFF_SCREEN
    render((void*)&data, nullptr, nullptr, nullptr);
    stbi_write_jpg("output.jpg", extent[0], extent[1], RD_CHANNEL, data.image, 100);
#else
    // renderLoop(render, &data);
#endif
}

#include "imgui.h"

void render(void* data, unsigned char** image, int* out_width, int* out_height)
{
    CbData *d = (CbData*) data;

#ifndef OFF_SCREEN
    RenderSceneConfigUI(d);
#endif

    RD::TraceRays(d->plt, 0,0,0, d->extent[0], d->extent[1]);

    /* Fetch result */
    RD::ReadBuffer(d->plt, d->rdImage, d->imageSize, d->image);

#ifndef OFF_SCREEN
    *image = d->image;
    *out_height = d->extent[1];
    *out_width  = d->extent[0];
#endif
}

void RenderSceneConfigUI(CbData *d)
{
    float camData[4];
    RD::ReadBuffer(d->plt, d->rdCamData, sizeof(camData), camData);

    RD::SceneProperties scene;
    RD::ReadBuffer(d->plt, d->rdSceneData, sizeof(scene), &scene);

    RD::Material matList[3];
    RD::ReadBuffer(d->plt, d->rdMatData, sizeof(matList), matList);


    {
        ImGui::Begin("Render Config");

        ImGui::Text("Camera:");
        ImGui::SliderFloat3("Camera Position", camData, -20.0f, 20.0f);
        ImGui::SliderFloat("Camera Rotation", &camData[3], -10.0f, 10.0f);

        ImGui::Text("Light:");
        ImGui::SliderFloat4("Light Direction", scene.lights[0].direction, -100.0f, 100.0f);
        ImGui::SliderFloat4("Light Color", scene.lights[0].color, 0.0f, 100.0f);

        ImGui::Text("Material 0:");
        ImGui::SliderFloat4("Albedo##m0", matList[0].albedo, 0.0f, 1.0f);
        ImGui::SliderFloat2("Metallic, Roughness##m0", &matList[0].metallic, 0.0f, 1.0f);

        ImGui::Text("Material 1:");
        ImGui::SliderFloat4("Albedo##m1", matList[1].albedo, 0.0f, 1.0f);
        ImGui::SliderFloat2("Metallic, Roughness##m1", &matList[1].metallic, 0.0f, 1.0f);

        ImGui::Text("Material 2:");
        ImGui::SliderFloat4("Albedo##m2", matList[2].albedo, 0.0f, 1.0f);
        ImGui::SliderFloat2("Metallic, Roughness##m2", &matList[2].metallic, 0.0f, 1.0f);

        ImGui::End();
    }

    RD::WriteBuffer(d->plt, d->rdCamData, sizeof(camData), camData);
    RD::WriteBuffer(d->plt, d->rdSceneData, sizeof(scene), &scene);
    RD::WriteBuffer(d->plt, d->rdMatData, sizeof(matList), matList);
}

void GetMaterialList(std::vector<RD::Material>& materialList)
{
    materialList.push_back({
        .albedo = {1.0f, 0.0f, 0.0f, 1.0f},
        .metallic = 0.0,
        .roughness = 0.5,
        ._1 = 0.0f,
        ._2 = 0.0f,
        .useAlbedoTex = 0.0f,
        .useMetallicTex = 0.0f,
        .useRoughnessTex = 0.0f,
        .useNormalTex = 0.0f
    });

    materialList.push_back({
        .albedo = {0.0f, 1.0f, 0.0f, 1.0f},
        .metallic = 0.5,
        .roughness = 0.5,
        ._1 = 0.0f,
        ._2 = 0.0f,
        .useAlbedoTex = 0.0f,
        .useMetallicTex = 0.0f,
        .useRoughnessTex = 0.0f,
        .useNormalTex = 0.0f
    });

    materialList.push_back({
        .albedo = {0.0f, 0.0f, 1.0f, 1.0f},
        .metallic = 0.0,
        .roughness = 0.25,
        ._1 = 0.0f,
        ._2 = 0.0f,
        .useAlbedoTex = 0.0f,
        .useMetallicTex = 0.0f,
        .useRoughnessTex = 0.0f,
        .useNormalTex = 0.0f
    });
}

void GetInstanceList(
    std::vector<RD::Instance>& instanceList, RD::BottomAccelStruct rdBottomAS)
{
    instanceList.push_back({
        {
            {1.0f, 1.0f, 1.0f}, // scaling
            aiQuaterniont<float>(), // rotation
            {0.0f, 0.0f, 0.0f} // position
        }, // transform
        0, // SBT offset
        10, // customInstanceID
        rdBottomAS // accelStruct handle
    });

    instanceList.push_back({
        {
            {1.0f, 1.0f, 1.0f}, // scaling
            aiQuaterniont<float>(), // rotation
            {0.0f, -1.0f, 0.0f} // position
        }, // transform
        0, // SBT offset
        40, // customInstanceID
        rdBottomAS // accelStruct handle
    });

    instanceList.push_back({
        {
            {1.0f, 1.0f, 1.0f}, // scaling
            aiQuaterniont<float>(), // rotation
            {0.0f, -2.0f, 0.0f} // position
        }, // transform
        0, // SBT offset
        70, // customInstanceID
        rdBottomAS // accelStruct handle
    });

    instanceList.push_back({
        {
            {1.0f, 1.0f, 1.0f}, // scaling
            aiQuaterniont<float>(), // rotation
            {1.0f, 0.0f, 0.0f} // position
        }, // transform
        0, // SBT offset
        100, // customInstanceID
        rdBottomAS // accelStruct handle
    });

    instanceList.push_back({
        {
            {1.0f, 1.0f, 1.0f}, // scaling
            aiQuaterniont<float>(), // rotation
            {1.0f, -1.0f, 0.0f} // position
        }, // transform
        0, // SBT offset
        130, // customInstanceID
        rdBottomAS // accelStruct handle
    });

    instanceList.push_back({
        {
            {1.0f, 1.0f, 1.0f}, // scaling
            aiQuaterniont<float>(), // rotation
            {1.0f, -2.0f, 0.0f} // position
        }, // transform
        0, // SBT offset
        160, // customInstanceID
        rdBottomAS // accelStruct handle
    });

    instanceList.push_back({
        {
            {1.0f, 1.0f, 1.0f}, // scaling
            aiQuaterniont<float>(), // rotation
            {-1.0f, 0.0f, 0.0f} // position
        }, // transform
        0, // SBT offset
        190, // customInstanceID
        rdBottomAS // accelStruct handle
    });

    instanceList.push_back({
        {
            {1.0f, 1.0f, 1.0f}, // scaling
            aiQuaterniont<float>(), // rotation
            {-1.0f, -1.0f, 0.0f} // position
        }, // transform
        0, // SBT offset
        220, // customInstanceID
        rdBottomAS // accelStruct handle
    });

    instanceList.push_back({
        {
            {1.0f, 1.0f, 1.0f}, // scaling
            aiQuaterniont<float>(), // rotation
            {-1.0f, -2.0f, 0.0f} // position
        }, // transform
        0, // SBT offset
        250, // customInstanceID
        rdBottomAS // accelStruct handle
    });
}

void GetSceneData(RD::SceneProperties* sceneData)
{
    sceneData->lightCount[0] = 1;
    sceneData->lights[0] = {
        .direction = {0.0f, -100.0f, -20.0f},
        .color = {1.0f, 1.0f, 1.0f, 1.0f}
    };
}