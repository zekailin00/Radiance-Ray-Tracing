#pragma once

#include <string>
#include <vector>

#include <radiance.h>

#ifdef IMAGE_SUPPORT

#define INCLUDE_SCENE_DESC(scene)   \
scene->meshInfoData,                \
scene->vertexData,                  \
scene->indexData,                   \
scene->uvData,                      \
scene->normalData,                  \
scene->materialData,                \
scene->textureData,                 \
scene->sampler,                     \
scene->topAccelStruct 

#define INCLUDE_SCENE_LAYOUT        \
RD::BUFFER_TYPE,                    \
RD::BUFFER_TYPE,                    \
RD::BUFFER_TYPE,                    \
RD::BUFFER_TYPE,                    \
RD::BUFFER_TYPE,                    \
RD::BUFFER_TYPE,                    \
RD::TEX_ARRAY_TYPE,                 \
RD::IMAGE_SAMPLER_TYPE,             \
RD::ACCEL_STRUCT_TYPE

#else

#define INCLUDE_SCENE_DESC(scene)   \
scene->meshInfoData,                \
scene->vertexData,                  \
scene->indexData,                   \
scene->uvData,                      \
scene->normalData,                  \
scene->materialData,                \
scene->topAccelStruct 

#define INCLUDE_SCENE_LAYOUT        \
RD::BUFFER_TYPE,                    \
RD::BUFFER_TYPE,                    \
RD::BUFFER_TYPE,                    \
RD::BUFFER_TYPE,                    \
RD::BUFFER_TYPE,                    \
RD::BUFFER_TYPE,                    \
RD::ACCEL_STRUCT_TYPE

#endif

namespace RD
{

struct Scene
{
public:
    static Scene* Load(std::string path, RD::Platform* plt, bool loadFromCache = false);

    RD::Buffer meshInfoData;
    RD::Buffer vertexData;
    RD::Buffer indexData;
    RD::Buffer uvData;
    RD::Buffer normalData;

    RD::Buffer materialData;
    RD::ImageArray textureData;
    RD::Sampler sampler;

    RD::TopAccelStruct topAccelStruct;

private:
    static void BuildInstance(aiNode* node, std::vector<RD::Instance>& rdInstanceList,
        const RD::Mat4x4& parentTF,const aiScene* scene,
        const std::vector<RD::BottomAccelStruct>& rdBotASList);
};

} // namespace RD