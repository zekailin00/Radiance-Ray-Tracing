#include "sceneBuilder.h"

#include <assimp/Importer.hpp>      // C++ importer interface
#include <assimp/scene.h>           // Output data structure
#include <assimp/postprocess.h>     // Post processing flags
#include <assimp/material.h>

#include <iostream>
#include <cassert>

#define STB_IMAGE_IMPLEMENTATION
#include "stb_image.h"

#define STB_IMAGE_RESIZE_IMPLEMENTATION
#include "stb_image_resize2.h"

#define STB_IMAGE_WRITE_IMPLEMENTATION
#include "stb_image_write.h"


#define TEX_DIM 4096 // Fixed dimension of textures in texture array for materials.


namespace RD
{

Scene* Scene::Load(std::string path, RD::Platform* plt, bool loadFromCache)
{
    // Create an instance of the Importer class
    Assimp::Importer importer;

    const aiScene* scene = importer.ReadFile(path,
        aiProcess_GenSmoothNormals       |
        aiProcess_Triangulate            |
        aiProcess_JoinIdenticalVertices  |
        aiProcess_SortByPType);

    assert(scene != nullptr);
    RD::ImageArray rdTextureData = RD::CreateImageArray(plt, TEX_DIM, TEX_DIM, scene->mNumTextures);
    RD::Sampler rdSampler = RD::CreateSampler(plt, RD_ADDRESS_REPEAT, RD_FILTER_LINEAR);

    std::vector<RD::MeshInfo>   meshInfoList;
    std::vector<RD::Vec3>       vertexList;
    std::vector<RD::Triangle>   indexList;
    std::vector<RD::Vec3>       uvList;
    std::vector<RD::Vec3>       normalList;
    std::vector<RD::Material>   matList;

    for (int i = 0; i < scene->mNumTextures; i++)
    {
        const aiTexture* tex = scene->mTextures[i];
        assert(tex->mHeight == 0); // Compressed image

        int x, y, ch;
        unsigned char* data = stbi_load_from_memory(
            (const unsigned char*)tex->pcData,
            tex->mWidth, &x, &y, &ch, RD_CHANNEL
        );

        unsigned char* texture = stbir_resize_uint8_linear(
            data, x, y, 0, NULL, TEX_DIM, TEX_DIM, 0, STBIR_RGBA
        );

        RD::WriteImage(plt, rdTextureData, TEX_DIM, TEX_DIM, i, texture);
        free(data);
        stbi_image_free(texture);
    }

    for (int i = 0; i < scene->mNumMeshes; i++)
    {
        const aiMesh* mesh = scene->mMeshes[i];

        RD::MeshInfo meshInfo = { //FIXME: element offset
            .vertexOffset  = (int)(vertexList.size() * 3),// sizeof(RD::Vec3)),
            .indexOffset   = (int)(indexList.size()  * 3),// sizeof(RD::Triangle)),
            .uvOffset      = (int)(uvList.size()     * 3),// sizeof(RD::Vec3)),
            .normalOffset  = (int)(normalList.size() * 3),// sizeof(RD::Vec3)),
            .materialIndex = (int)(mesh->mMaterialIndex)
        };

        for (size_t i = 0; i < mesh->mNumVertices; i++)
        {
            vertexList.push_back(mesh->mVertices[i]);
            normalList.push_back(mesh->mNormals[i]);
            uvList.push_back(mesh->mTextureCoords[0]?
                mesh->mTextureCoords[0][i]: aiVector3D());
        }

        for (size_t i = 0; i < mesh->mNumFaces; i++)
        {
            assert(mesh->mFaces[i].mNumIndices == 3);

            indexList.push_back({
                mesh->mFaces[i].mIndices[0],
                mesh->mFaces[i].mIndices[1],
                mesh->mFaces[i].mIndices[2]
            });
        }

        meshInfoList.push_back(meshInfo);
    }

    for (int i = 0; i < scene->mNumMaterials; i++)
    {
        const aiMaterial* mat = scene->mMaterials[i];
        RD::Material material;

        {
            aiString fileBaseColor; 
            aiReturn res = mat->GetTexture(AI_MATKEY_BASE_COLOR_TEXTURE, &fileBaseColor);
            if (res == aiReturn_SUCCESS)
            {
                assert(fileBaseColor.data[0] == '*');
                material.albedoTexIdx = strtol(&fileBaseColor.data[1], nullptr, 10);
            }
            else
            {
                aiColor4D color;
                aiReturn res = mat->Get(AI_MATKEY_BASE_COLOR, color);
                assert(res == aiReturn_SUCCESS);

                material.albedoTexIdx = -1;
                material.albedo[0] = color[0];
                material.albedo[1] = color[1];
                material.albedo[2] = color[2];
                material.albedo[3] = color[3];
            }
        }

        {
            aiString fileMetallic;
            aiReturn res = mat->GetTexture(AI_MATKEY_METALLIC_TEXTURE, &fileMetallic);
            if (res == aiReturn_SUCCESS)
            {
                assert(fileMetallic.data[0] == '*');
                material.metallicTexIdx = strtol(&fileMetallic.data[1], nullptr, 10);
            }
            else
            {
                float factor = 0.0f;
                aiReturn res = mat->Get(AI_MATKEY_METALLIC_FACTOR, factor);
                assert(res == aiReturn_SUCCESS);

                material.metallicTexIdx = -1;
                material.metallic = factor;
            }
        }

        {
            aiString fileRoughness;
            aiReturn res = mat->GetTexture(AI_MATKEY_ROUGHNESS_TEXTURE, &fileRoughness);
            if (res == aiReturn_SUCCESS)
            {
                assert(fileRoughness.data[0] == '*');
                material.roughnessTexIdx = strtol(&fileRoughness.data[1], nullptr, 10);
            }
            else
            {
                float factor = 0.0f;
                aiReturn res = mat->Get(AI_MATKEY_ROUGHNESS_FACTOR, factor);
                assert(res == aiReturn_SUCCESS);

                material.roughnessTexIdx = -1;
                material.roughness = factor;
            }
        }

        {
            float factor = 0.0f;
            aiReturn res = mat->Get(AI_MATKEY_TRANSMISSION_FACTOR, factor);
            material.transmission = factor;
        }

        {
            float factor = 1.45f;
            aiReturn res = mat->Get(AI_MATKEY_REFRACTI, factor);
            material.ior = factor;
        }

        {
            aiString fileNormals;
            aiReturn res = mat->GetTexture(aiTextureType_NORMALS, 0, &fileNormals);
            if (res == aiReturn_SUCCESS)
            {
                assert(fileNormals.data[0] == '*');
                material.normalTexIdx = strtol(&fileNormals.data[1], nullptr, 10);
            }
            else
            {
                material.normalTexIdx = -1;
            }
        }

        matList.push_back(material);
    }
    
    unsigned int meshInfoSize = meshInfoList.size() * sizeof(RD::MeshInfo);
    RD::Buffer rdMeshInfoData = RD::CreateBuffer(plt, meshInfoSize);
    RD::WriteBuffer(plt, rdMeshInfoData, meshInfoSize, meshInfoList.data());

    unsigned int vertexSize = vertexList.size() * sizeof(RD::Vec3);
    RD::Buffer rdVertexData = RD::CreateBuffer(plt, vertexSize);
    RD::WriteBuffer(plt, rdVertexData, vertexSize, vertexList.data());

    unsigned int indexSize = indexList.size() * sizeof(RD::Triangle);
    RD::Buffer rdIndexData = RD::CreateBuffer(plt, indexSize);
    RD::WriteBuffer(plt, rdIndexData, indexSize, indexList.data());

    unsigned int uvSize = uvList.size() * sizeof(RD::Vec3);
    RD::Buffer rdUVData = RD::CreateBuffer(plt, uvSize);
    RD::WriteBuffer(plt, rdUVData, uvSize, uvList.data());

    unsigned int normalSize = normalList.size() * sizeof(RD::Vec3);
    RD::Buffer rdNormalData = RD::CreateBuffer(plt, normalSize);
    RD::WriteBuffer(plt, rdNormalData, normalSize, normalList.data());

    unsigned int matSize = matList.size() * sizeof(RD::Material);
    RD::Buffer rdMatData = RD::CreateBuffer(plt, matSize);
    RD::WriteBuffer(plt, rdMatData, matSize, matList.data());


    RD::TopAccelStruct rdTopAS;
    if (loadFromCache)
    {
        std::string cachePath = path + ".cache";
        RD::FileToTopAccelStruct(plt, cachePath.c_str(), &rdTopAS);
    }
    else
    {
        time_t start_t, end_t;
        double diff_t;
        time(&start_t);
        int totalTriangles = 0, totalVertices = 0;

        std::vector<RD::BottomAccelStruct> rdBotASList;
        for (int i = 0; i < scene->mNumMeshes; i++)
        {
            const aiMesh* mesh = scene->mMeshes[i];
            RD::Mesh rdMesh;

            totalTriangles += mesh->mNumFaces;
            totalVertices += mesh->mNumVertices;

            for (size_t i = 0; i < mesh->mNumVertices; i++)
                rdMesh.vertexData.push_back(mesh->mVertices[i]);

            for (size_t i = 0; i < mesh->mNumFaces; i++)
                rdMesh.indexData.push_back({
                    mesh->mFaces[i].mIndices[0],
                    mesh->mFaces[i].mIndices[1],
                    mesh->mFaces[i].mIndices[2]
                });

            rdBotASList.push_back(RD::BuildAccelStruct(plt, rdMesh));
        }

        std::vector<RD::Instance> rdInstanceList;
        BuildInstance(scene->mRootNode, rdInstanceList, RD::Mat4x4{}, scene, rdBotASList);
        
        rdTopAS = RD::BuildAccelStruct(plt, rdInstanceList);
        std::string cachePath = path + ".cache";
        RD::TopAccelStructToFile(plt, rdTopAS, cachePath.c_str());

        time(&end_t);
        diff_t = difftime(end_t, start_t);
        printf("\nBVH build report:\n");
        printf("\tNumber of meshes: %d\n", scene->mNumMeshes);
        printf("\tNumber of vertices: %d\n", totalVertices);
        printf("\tNumber of triangles: %d\n", totalTriangles);
        printf("\tBuild time cost: %f (sec)\n", diff_t);
    }

    RD::Scene* rdScene = new RD::Scene();
    rdScene->meshInfoData   = rdMeshInfoData;
    rdScene->vertexData     = rdVertexData;
    rdScene->indexData      = rdIndexData;
    rdScene->uvData         = rdUVData;
    rdScene->normalData     = rdNormalData;
    rdScene->materialData   = rdMatData;
    rdScene->textureData    = rdTextureData;
    rdScene->sampler        = rdSampler;
    rdScene->topAccelStruct = rdTopAS;

    return rdScene;
}

void Scene::BuildInstance(aiNode* node, std::vector<RD::Instance>& rdInstanceList,
    const RD::Mat4x4& parentTF,const aiScene* scene,
    const std::vector<RD::BottomAccelStruct>& rdBotASList)
{
    if (node == nullptr) return;

    RD::Mat4x4 currentTF = parentTF * node->mTransformation;

    for (int i = 0; i < node->mNumMeshes; i++)
    {
        unsigned int meshIdx = node->mMeshes[i];
        const aiMesh* mesh = scene->mMeshes[meshIdx];

        RD::Instance inst = {
            .transform = currentTF,
            .SBTOffset = 0,
            .customInstanceID = mesh->mMaterialIndex,
            .bottomAccelStruct = rdBotASList[meshIdx]
        };

        rdInstanceList.push_back(inst);
    }

    for (int i = 0; i < node->mNumChildren; i++)
    {
        BuildInstance(node->mChildren[i], rdInstanceList,
            currentTF, scene, rdBotASList);
    }
}

} // namespace RD