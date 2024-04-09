#include <assimp/Importer.hpp>      // C++ importer interface
#include <assimp/scene.h>           // Output data structure
#include <assimp/postprocess.h>     // Post processing flags
#include <assimp/material.h>

#include <iostream>
#include <cassert>

#define STB_IMAGE_IMPLEMENTATION
#include "stb_image.h"

#define modelFile "/home/zekailin00/Desktop/ray-tracing/framework/assets/helmet.gltf"
// #define modelFile "/home/zekailin00/Desktop/ray-tracing/framework/assets/material-test.gltf"
// #define modelFile "/home/zekailin00/Desktop/ray-tracing/framework/assets/sample1.gltf"

void PrintChildren(aiNode* node, int level);

int main(int, char**)
{
    // Create an instance of the Importer class
    Assimp::Importer importer;

    const aiScene* scene = importer.ReadFile(modelFile,
        aiProcess_GenSmoothNormals       |
        aiProcess_Triangulate            |
        aiProcess_JoinIdenticalVertices  |
        aiProcess_SortByPType);

    assert(scene != nullptr);

    for (int i = 0; i < scene->mNumMeshes; i++)
    {
        const aiMesh* mesh = scene->mMeshes[i];
        printf("Mesh %d\n", i);
        printf("\tName: %s\n", mesh->mName.C_Str());
        printf("\tNumber of vertices: %d\n", mesh->mNumVertices);
        printf("\tNumber of faces: %d\n", mesh->mNumFaces);
        printf("\tMaterial Index: %d\n", mesh->mMaterialIndex);
        printf("\tHas UV: %d\n", mesh->mTextureCoords[0] != nullptr);
    }

    printf("\n\n");
    for (int i = 0; i < scene->mNumMaterials; i++)
    {
        const aiMaterial* mat = scene->mMaterials[i];
        printf("Material %d\n", i);


        {
            aiString fileBaseColor; 
            aiReturn res = mat->GetTexture(AI_MATKEY_BASE_COLOR_TEXTURE, &fileBaseColor);
            if (res == aiReturn_SUCCESS)
            {
                if (fileBaseColor.data[0] == '*')
                {
                    printf("\tfileBaseColorTex(%d): %ld\n",
                        fileBaseColor.length,
                        strtol(&fileBaseColor.data[1], nullptr, 10));
                }
                else
                {
                    printf("\tfileBaseColorTex(%d): %s\n",
                        fileBaseColor.length, fileBaseColor.C_Str());
                }
            }
            else {
                aiColor4D color;
                aiReturn res = mat->Get(AI_MATKEY_BASE_COLOR, color);
                if (res == aiReturn_SUCCESS) printf("\tfileBaseColorFactors: <%f, %f, %f, %f>\n",
                        color[0], color[1], color[2], color[3]);
            }
        }

        {
            aiString fileMetallic;
            aiReturn res = mat->GetTexture(AI_MATKEY_METALLIC_TEXTURE, &fileMetallic);
            if (res == aiReturn_SUCCESS)
            {
                if (fileMetallic.data[0] == '*')
                {
                    printf("\tfileMetallicTex(%d): %ld\n",
                        fileMetallic.length,
                        strtol(&fileMetallic.data[1], nullptr, 10));
                }
                else
                {
                    printf("\tfileMetallicTex(%d): %s\n",
                        fileMetallic.length, fileMetallic.C_Str());
                }
            }
            else {
                float factor = 0.0f;
                aiReturn res = mat->Get(AI_MATKEY_METALLIC_FACTOR, factor);
                if (res == aiReturn_SUCCESS) printf("\tfileMetallicFactor: %f\n", factor);
            }
        }

        {
            aiString fileRoughness;
            aiReturn res = mat->GetTexture(AI_MATKEY_ROUGHNESS_TEXTURE, &fileRoughness);
            if (res == aiReturn_SUCCESS) printf("\tfileRoughnessTex(%d): %s\n",
                fileRoughness.length, fileRoughness.C_Str());
            else {
                float factor = 0.0f;
                aiReturn res = mat->Get(AI_MATKEY_ROUGHNESS_FACTOR, factor);
                if (res == aiReturn_SUCCESS) printf("\tfileRoughnessFactor: %f\n", factor);
            }
        }

        {
            aiString fileNormals;
            aiReturn res = mat->GetTexture(aiTextureType_NORMALS, 0, &fileNormals);
            if (res == aiReturn_SUCCESS) printf("\tfileNormalsTex(%d): %s\n",
                fileNormals.length, fileNormals.C_Str());
        }
    }

    printf("\n\n");
    for (int i = 0; i < scene->mNumTextures; i++)
    {
        const aiTexture* tex = scene->mTextures[i];
        printf("Texture %d\n", i);
        printf("\tName: %s\n", tex->mFilename.C_Str());
        printf("\tFormat: %s\n", tex->achFormatHint);

        if (tex->mHeight == 0)
        {
            int x, y, ch;
            unsigned char* data = stbi_load_from_memory(
                (const unsigned char*)tex->pcData,
                tex->mWidth, &x, &y, &ch, 4
            );
            printf("\tExtent(decompressed): <%u, %u>\n", x, y);
            free(data);
        }
        else
        {
            printf("\tExtent: <%u, %u>\n", tex->mWidth, tex->mHeight);
        }
    }

    printf("\n\nNode Tree:\n");
    PrintChildren(scene->mRootNode, 0);
}

inline void Indent(int level)
{
    while(level-- > 0) printf("\t");
}

void PrintChildren(aiNode* node, int level)
{
    if (node == nullptr) return;
    Indent(level); printf("Name: %s\n", node->mName.C_Str());
    Indent(level); printf("mNumMeshes: %d", node->mNumMeshes);
    printf(": ");
    for (int i = 0; i < node->mNumMeshes; i++)
        printf("%d, ", node->mMeshes[i]);
    printf("\n");
    Indent(level); printf("mNumChildren: %d\n", node->mNumChildren);
    for (int i = 0; i < node->mNumChildren; i++)
    {
        PrintChildren(node->mChildren[i], level + 1); 
        printf("\n");
    }
}
