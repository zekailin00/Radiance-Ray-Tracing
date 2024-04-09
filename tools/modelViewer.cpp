#include <assimp/Importer.hpp>      // C++ importer interface
#include <assimp/scene.h>           // Output data structure
#include <assimp/postprocess.h>     // Post processing flags
#include <assimp/material.h>

#include <iostream>
#include <cassert>

#define STB_IMAGE_IMPLEMENTATION
#include "stb_image.h"

#define modelFile "/home/zekailin00/Desktop/ray-tracing/framework/assets/helmet.gltf"
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
        printf("\tNumber of vertices: %d\n", mesh->mNumVertices);
        printf("\tNumber of faces: %d\n", mesh->mNumFaces);
    }

    printf("\n\n");
    for (int i = 0; i < scene->mNumMaterials; i++)
    {
        const aiMaterial* mat = scene->mMaterials[i];
        printf("Material %d\n", i);

        aiString fileBaseColor, fileMetallic, fileRoughness, fileNormals;

        mat->GetTexture(AI_MATKEY_BASE_COLOR_TEXTURE, &fileBaseColor);
        mat->GetTexture(AI_MATKEY_METALLIC_TEXTURE, &fileMetallic);
        mat->GetTexture(AI_MATKEY_ROUGHNESS_TEXTURE, &fileRoughness);
        mat->GetTexture(aiTextureType_NORMALS, 0, &fileNormals);
        printf("\tfileBaseColor(%d): %s\n", fileBaseColor.length, fileBaseColor.C_Str());
        printf("\tfileMetallic(%d): %s\n", fileMetallic.length, fileMetallic.C_Str());
        printf("\tfileRoughness(%d): %s\n", fileRoughness.length, fileMetallic.C_Str());
        printf("\tfileNormals(%d): %s\n", fileNormals.length, fileNormals.C_Str());

        // TODO: material prop factors
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
    Indent(level); printf("mNumMeshes: %d\n", node->mNumMeshes);
    Indent(level); printf("mNumChildren: %d\n", node->mNumChildren);
    for (int i = 0; i < node->mNumChildren; i++)
    {
        PrintChildren(node->mChildren[i], level + 1); 
        printf("\n");
    }
}
