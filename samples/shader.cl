#include "radiance.cl"
#include "pbr.cl"

struct Payload
{
    int x; // horizontal pixel index
    int y; // vertical pixel index

    float3 color;
    bool hit;

    bool shadowTest; // Merge light hit test with color shader

    float3 nextFactor;
    float3 nextRayOrigin;
    float3 nextRayDirection;
};

struct SceneData
{
    float*                     camData;
    float*                     vertexData;
    float*                     normalData;
    float*                     uvData;
    uint*                      indexData;
    struct Material*           materials;
    struct SceneProperties*    scene;
    int                        depth;
    unsigned int               frameID;
    struct AccelStruct*        topLevel;
};

__kernel void raygen(
    __global struct RayTraceProperties* RTProp,
    __global float*                     imageScratch,
    __global uchar*                     image /* <row major> */,
    __global unsigned int*              extent /* <x,y> */,
    __global float*                     camData,
    __global float*                     vertexData,
    __global float*                     normalData,
    __global float*                     uvData,
    __global uint*                      indexData,
    __global struct Material*           materials,
    __global struct SceneProperties*    scene,
    __global struct AccelStruct*        topLevel)
{
    /* the unique global id of the work item for the current pixel */
    const int work_item_id = get_global_id(0);

    int    x = work_item_id % (int)extent[0]; /* x-coordinate of the pixel */
    int    y = work_item_id / (int)extent[0]; /* y-coordinate of the pixel */
    float fx = ((float)x / (float)extent[0]); /* convert int to float in range [0-1] */
    float fy = ((float)y / (float)extent[1]); /* convert int to float in range [0-1] */

    float f0 = 2; // focal length
    float3 dir = {fx - 0.5, fy - 0.5f, f0};
    dir = normalize(dir);

    float theta = camData[3];
    float3 c0 = {cos(theta), 0, -sin(theta)};
    float3 c1 = {0         , 1,  0         };
    float3 c2 = {sin(theta), 0,  cos(theta)};
    dir = dir[0] * c0 + dir[1] * c1 + dir[2] * c2;

    float3 origin = {camData[0], camData[1], camData[2]};

    // Index for accessing image data
    const int CHANNEL = 4;
    int index = (int)(extent[0] * (extent[1] - y - 1) + (extent[0] - x - 1));


    int iteration = RTProp->batchSize;
    unsigned int frameID = RTProp->totalSamples;
    while (iteration > 0)
    {
        iteration--;
        // sceneData.depth = RTProp->depth;
        // sceneData.frameID = frameID;
        // payload.nextRayOrigin = origin;
        // payload.nextRayDirection = dir;

        struct Payload payload;
        payload.x = x;
        payload.y = y;
        payload.color[0] = 0.0f;
        payload.color[1] = 0.0f;
        payload.color[2] = 0.0f;
        payload.shadowTest = false;
        payload.nextFactor = 1.0f;
        payload.nextRayOrigin = origin;
        payload.nextRayDirection = dir;

        struct SceneData sceneData;
        sceneData.camData       = camData;
        sceneData.vertexData    = vertexData;
        sceneData.normalData    = normalData;
        sceneData.uvData        = uvData;
        sceneData.indexData     = indexData;
        sceneData.materials     = materials;
        sceneData.scene         = scene;
        sceneData.depth         = RTProp->depth;
        sceneData.frameID       = frameID;
        sceneData.topLevel      = topLevel;

        float3 color = 0.0f;
        float3 contribution = 1.0f;

        while (sceneData.depth > 0)
        {
            // printf("depth:<%d>\n", sceneData.depth);
            sceneData.depth--;
        
            traceRay(topLevel, payload.nextRayOrigin, payload.nextRayDirection,
                0.01, 1000, &payload, &sceneData);

            color += contribution * payload.color;
            contribution *= payload.nextFactor;
        }

        // HDR mapping
        color = color / (color + 1.0f);


        if (frameID == 0)
        {
            imageScratch[CHANNEL * index + 0] = color[0];
            imageScratch[CHANNEL * index + 1] = color[1];
            imageScratch[CHANNEL * index + 2] = color[2];
        }
        else
        {
            float pixel;
            pixel = imageScratch[CHANNEL * index + 0];
            imageScratch[CHANNEL * index + 0] = (frameID * pixel + color[0]) / (frameID + 1);

            pixel = imageScratch[CHANNEL * index + 1];
            imageScratch[CHANNEL * index + 1] = (frameID * pixel + color[1]) / (frameID + 1);
            
            pixel = imageScratch[CHANNEL * index + 2];
            imageScratch[CHANNEL * index + 2] = (frameID * pixel + color[2]) / (frameID + 1);
        }
        frameID++;
    }

    float3 color = {
        imageScratch[CHANNEL * index + 0],
        imageScratch[CHANNEL * index + 1],
        imageScratch[CHANNEL * index + 2]
    };

    // Gamma correct
    color = pow(color, 0.4545f);

    image[CHANNEL * index + 0] = (int)(color[0] * 255);
    image[CHANNEL * index + 1] = (int)(color[1] * 255);
    image[CHANNEL * index + 2] = (int)(color[2] * 255);
    image[CHANNEL * index + 3] = 255;
}

// printNormalDebug(float3 n0, float3 n1, float3 n2, float3 bary)
// {
//     printf( "n0: <%f, %f, %f>\n"
//             "n1: <%f, %f, %f>\n"
//             "n2: <%f, %f, %f>\n"
//             , n0[0], n0[1], n0[2]
//             , n1[0], n1[1], n1[2]
//             , n2[0], n2[1], n2[2]);
// }

// printIndexDebug(uint idx0, uint idx1, uint idx2)
// {
//     printf( "idx: <%d, %d, %d>\n"
//             , idx0, idx1, idx2);
// }

void hit(struct Payload* payload, struct HitData* hitData, struct SceneData* sceneData)
{
    payload->hit = true;
    if (payload->shadowTest)
        return;


    float* vertexData = sceneData->vertexData;
    uint* indexData = sceneData->indexData;
    float* normalData = sceneData->normalData;
    uint i0 = indexData[hitData->primitiveIndex * 3 + 0];
    uint i1 = indexData[hitData->primitiveIndex * 3 + 1];
    uint i2 = indexData[hitData->primitiveIndex * 3 + 2];

    float3 v0 = {vertexData[i0 * 3 + 0], vertexData[i0 * 3 + 1], vertexData[i0 * 3 + 2]};
    float3 v1 = {vertexData[i1 * 3 + 0], vertexData[i1 * 3 + 1], vertexData[i1 * 3 + 2]};
    float3 v2 = {vertexData[i2 * 3 + 0], vertexData[i2 * 3 + 1], vertexData[i2 * 3 + 2]};

    float3 n0 = {normalData[i0 * 3 + 0], normalData[i0 * 3 + 1], normalData[i0 * 3 + 2]};
    float3 n1 = {normalData[i1 * 3 + 0], normalData[i1 * 3 + 1], normalData[i1 * 3 + 2]};
    float3 n2 = {normalData[i2 * 3 + 0], normalData[i2 * 3 + 1], normalData[i2 * 3 + 2]};


    int matIndex = hitData->instanceIndex % 3;
    struct Material* material = &sceneData->materials[matIndex];


    float metallicFrag;
    if (material->useMetallicTex == 0)
        metallicFrag = material->metallic;
    // else
    //     metallicFrag = texture(MetallicTexture, texCoords).x;

    float roughnessFrag;
    if (material->useRoughnessTex == 0)
        roughnessFrag = clamp(material->roughness, 0.0f, 1.0f);
    // else
    //     roughnessFrag = clamp(texture(RoughnessTexture, texCoords).x, 0.0, 1.0);

    float3 albedoFrag;
    if (material->useAlbedoTex == 0)
        albedoFrag = material->albedo.rgb;
    // else
    //     albedoFrag = texture(AlbedoTexture, texCoords).rgb;


    struct SceneProperties* scene = sceneData->scene;
    float3 dir = normalize(-scene->lights[0].direction.xyz);

    float3 normal = hitData->barycentric.x * n0 +
                    hitData->barycentric.y * n1 + 
                    hitData->barycentric.z * n2;
    float3 N = normalize(normal);

    float3 origin = hitData->hitPoint + hitData->translate + N * 0.0001f;
    float3 viewPos = {
        sceneData->camData[0],
        sceneData->camData[1],
        sceneData->camData[2]};
    float3 V = normalize(viewPos - origin);
    float3 L = normalize(scene->lights[0].direction.xyz);

    payload->shadowTest = true;
    traceRay(sceneData->topLevel, origin, dir, 0.01, 1000, payload, sceneData);
    payload->shadowTest = false;

    float3 color = {0.0f, 0.0f, 0.0f};
    if (payload->hit)
    {
        // Specular contribution
        float3 Lo = {0.0f, 0.0f, 0.0f};

        // TODO: support multiple lights
        float3 lightColor = scene->lights[0].color.rgb;
        Lo += BRDF(L, V, N, metallicFrag, roughnessFrag, albedoFrag, lightColor);

        color += Lo;
    }

#ifndef RAY_TRACING
    // Combine with ambient
    // color += albedoFrag * 0.05f;
#endif

    payload->color[0] = color.x;
    payload->color[1] = color.y;
    payload->color[2] = color.z;

    //////////////////////////////////
    //      Global illumination     //
    //////////////////////////////////

    // different random value for each pixel and each frame
    uint3 randInput = {sceneData->frameID, (uint)get_global_id(0), sceneData->depth};
    float3 random = random_pcg3d(randInput);
    // printf("input: <%d, %d, %d>\nrandom: <%f, %f, %f>\n",
    //     randInput.x, randInput.y, randInput.z,
    //     random.x, random.y, random.z);
    
    // sample indirect direction
    float3 nextFactor = {0.0f, 0.0f, 0.0f};
    float3 nextDir = sampleMicrofacetBRDF(V, N, 
        albedoFrag, metallicFrag, roughnessFrag,
        random, &nextFactor);

    // indirect ray
    payload->nextRayOrigin = origin;
    payload->nextRayDirection = nextDir;
    payload->nextFactor = nextFactor;

    // // [debug] barycentric viz
    // payload->color[0] = hitData->barycentric.x * 255;
    // payload->color[1] = hitData->barycentric.y * 255;
    // payload->color[2] = hitData->barycentric.z * 255;

    // // [debug] normal viz
    // normal = fabs(normal);
    // payload->color[0] = normal.x * 255;
    // payload->color[1] = normal.y * 255;
    // payload->color[2] = normal.z * 255;

    // // [debug] custom inst index viz
    // payload->color[0] = (uchar)hitData->instanceCustomIndex;
    // payload->color[1] = (uchar)hitData->instanceCustomIndex;
    // payload->color[2] = (uchar)hitData->instanceCustomIndex;
}

void miss(struct Payload* payload, struct SceneData* sceneData)
{
    payload->color[0] = 0.5f;
    payload->color[1] = 0.5f;
    payload->color[2] = 0.5f;
    payload->hit = false;
}