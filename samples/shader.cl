#include "radiance.cl"
#include "pbr.cl"

struct Payload
{
    int x; // horizontal pixel index
    int y; // vertical pixel index

    float3 color;
    bool hit;

    float3 nextFactor;
    float3 nextRayOrigin;
    float3 nextRayDirection;
};

struct SceneData
{
    float*                     camData;
    struct SceneProperties*    scene;
    
    struct MeshInfo*           meshInfoData;
    float*                     vertexData;
    uint*                      indexData;
    float*                     uvData;
    float*                     normalData;
    struct Material*           materials;
    struct AccelStruct*        topLevel;

    int                        depth;
    unsigned int               frameID;
    unsigned int               debug;
};

__kernel void raygen(
    __global struct RayTraceProperties* RTProp,
    __global float*                     imageScratch,
    __global uchar*                     image /* <row major> */,
    __global unsigned int*              extent /* <x,y> */,
    __global float*                     camData,
    __global struct SceneProperties*    scene,

    __global struct MeshInfo*           meshInfoData,
    __global float*                     vertexData,
    __global uint*                      indexData,
    __global float*                     uvData,
    __global float*                     normalData,
    __global struct Material*           materials,
    image2d_array_t                     imageArray,
    sampler_t                           sampler,
    __global struct AccelStruct*        topLevel)
{
    /* the unique global id of the work item for the current pixel */
    const int index = get_global_id(0);

    // Index for accessing image data
    const int x = index % (int)extent[0]; /* x-coordinate of the pixel */
    const int y = index / (int)extent[0]; /* y-coordinate of the pixel */

    const int CHANNEL = 4; // RGBA color output

    // Begin one batch of work
    int iteration = RTProp->batchSize;
    unsigned int frameID = RTProp->totalSamples;
    while (iteration > 0)
    {
        iteration--;

        // anti-alising
        uint3 randInput = {frameID, RTProp->totalSamples, index};
        float3 random = random_pcg3d(randInput);

        /* convert int to float in range [0-1] */
        float fx = (((float)x + random.x)/ (float)extent[0]) - 0.5;
        float fy = 0.5 - (((float)y + random.y) / (float)extent[1]);

        float f0 = -1; // focal length
        float3 dir = {fx, fy, f0}; /* range [-0.5, 0.5] */
        dir = normalize(dir);
        float3 origin = {camData[0], camData[1], camData[2]};

        // Transform camera position
        float theta = camData[3];
        float3 c0 = {cos(theta), 0, -sin(theta)};
        float3 c1 = {0         , 1,  0         };
        float3 c2 = {sin(theta), 0,  cos(theta)};
        dir = dir[0] * c0 + dir[1] * c1 + dir[2] * c2;


        struct Payload payload;
        payload.x = x;
        payload.y = y;
        payload.color[0] = 0.0f;
        payload.color[1] = 0.0f;
        payload.color[2] = 0.0f;
        payload.nextFactor = 1.0f;
        payload.nextRayOrigin = origin;
        payload.nextRayDirection = dir;

        struct SceneData sceneData;
        sceneData.camData       = camData;
        sceneData.scene         = scene;
        sceneData.meshInfoData  = meshInfoData;
        sceneData.vertexData    = vertexData;
        sceneData.indexData     = indexData;
        sceneData.uvData        = uvData;
        sceneData.normalData    = normalData;
        sceneData.materials     = materials;
        sceneData.topLevel      = topLevel;
        sceneData.depth         = 0;
        sceneData.frameID       = frameID;
        sceneData.debug         = RTProp->debug;
        

        float3 color = 0.0f;
        float3 contribution = 1.0f;
        while (sceneData.depth < RTProp->depth)
        {
            traceRay(topLevel, 1, 3, payload.nextRayOrigin, payload.nextRayDirection,
                0.01, 1000, &payload, &sceneData, imageArray, sampler);

            if (payload.hit)
            {
                color += contribution * payload.color;
                contribution *= payload.nextFactor;
            }
            else if (sceneData.depth == 0)
            {
                // No direct hit, set background color.
                color = payload.color;
            }
            else
            {
                // No hit, stop tracing.
                break;
            }
            sceneData.depth++;
            payload.hit = false;

            if (RTProp->debug)
            {
                break;
            }
        }

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

    if (!RTProp->debug)
    {
        // HDR mapping
        color = color / (color + 1.0f);

        // Gamma correct
        // color = pow(color, 0.4545f);
    }

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

void shadow(struct Payload* payload, struct HitData* hitData,
    struct SceneData* sceneData, image2d_array_t imageArray, sampler_t sampler)
{
    // Shadow test
    payload->hit = true;
    payload->color = 0.0f;
}

void material(struct Payload* payload, struct HitData* hitData,
    struct SceneData* sceneData, image2d_array_t imageArray, sampler_t sampler)
{
    payload->hit = true;

    float* vertexData = sceneData->vertexData;
    uint* indexData = sceneData->indexData;
    float* normalData = sceneData->normalData;
    float* uvData = sceneData->uvData;
    struct MeshInfo* meshInfo = &sceneData->meshInfoData[hitData->instanceIndex];
    //FIXME: instID is not meshIdx

    int vo = meshInfo->vertexOffset;
    int io = meshInfo->indexOffset;
    int uo = meshInfo->uvOffset;
    int no = meshInfo->normalOffset;

    uint i0 = indexData[io + hitData->primitiveIndex * 3 + 0];
    uint i1 = indexData[io + hitData->primitiveIndex * 3 + 1];
    uint i2 = indexData[io + hitData->primitiveIndex * 3 + 2];

    float3 v0 = {vertexData[vo + i0 * 3 + 0], vertexData[vo + i0 * 3 + 1], vertexData[vo + i0 * 3 + 2]};
    float3 v1 = {vertexData[vo + i1 * 3 + 0], vertexData[vo + i1 * 3 + 1], vertexData[vo + i1 * 3 + 2]};
    float3 v2 = {vertexData[vo + i2 * 3 + 0], vertexData[vo + i2 * 3 + 1], vertexData[vo + i2 * 3 + 2]};

    float2 uv0 = {uvData[uo + i0 * 3 + 0], uvData[uo + i0 * 3 + 1]};
    float2 uv1 = {uvData[uo + i1 * 3 + 0], uvData[uo + i1 * 3 + 1]};
    float2 uv2 = {uvData[uo + i2 * 3 + 0], uvData[uo + i2 * 3 + 1]};
    float2 uv  = hitData->barycentric.x * uv0 +
                 hitData->barycentric.y * uv1 + 
                 hitData->barycentric.z * uv2;

    struct Material* material = &sceneData->materials[meshInfo->materialIndex];

    // printf("offsets: <%d, %d, %d, %d>\n"
    //        "Mat indices: <%d, %d, %d, %d>\n",
    //        vo, io, uo, no, 
    //        meshInfo->materialIndex, material->metallicTexIdx, 
    //        material->roughnessTexIdx, material->albedoTexIdx );

    float metallicFrag;
    if (material->metallicTexIdx == -1)
        metallicFrag = material->metallic;
    else
    {
        float4 coord = {uv.x, 1.0f - uv.y, (float)material->metallicTexIdx, 0.0f};
        uint4 tex = read_imageui(imageArray, sampler, coord);
        metallicFrag = clamp(tex.z / 255.0f, 0.0f, 1.0f);
    }

    float roughnessFrag;
    if (material->roughnessTexIdx == -1)
        roughnessFrag = clamp(material->roughness, 0.0f, 1.0f);
    else
    {
        float4 coord = {uv.x, 1.0f - uv.y, (float)material->roughnessTexIdx, 0.0f};
        uint4 tex = read_imageui(imageArray, sampler, coord);
        roughnessFrag = clamp(tex.y / 255.0f, 0.0f, 1.0f);
    }

    float3 albedoFrag;
    if (material->albedoTexIdx == -1)
        albedoFrag = material->albedo.rgb;
    else
    {
        float4 coord = {uv.x, 1.0f - uv.y, (float)material->albedoTexIdx, 0.0f};
        uint4 tex = read_imageui(imageArray, sampler, coord);
        albedoFrag.x = clamp(tex.x / 255.0f, 0.0f, 1.0f);
        albedoFrag.y = clamp(tex.y / 255.0f, 0.0f, 1.0f);
        albedoFrag.z = clamp(tex.z / 255.0f, 0.0f, 1.0f);
    }

    float3 N;
    if (true)//(material->normalTexIdx == -1)/FIXME: transform normal
    {
        float3 n0 = {normalData[no + i0 * 3 + 0], normalData[no + i0 * 3 + 1], normalData[no + i0 * 3 + 2]};
        float3 n1 = {normalData[no + i1 * 3 + 0], normalData[no + i1 * 3 + 1], normalData[no + i1 * 3 + 2]};
        float3 n2 = {normalData[no + i2 * 3 + 0], normalData[no + i2 * 3 + 1], normalData[no + i2 * 3 + 2]};
        float3 normal = hitData->barycentric.x * n0 +
                        hitData->barycentric.y * n1 + 
                        hitData->barycentric.z * n2;
        N = normalize(normal);
    }
    else
    {
        float4 coord = {uv.x, 1.0f - uv.y, (float)material->normalTexIdx, 0.0f};
        uint4 tex = read_imageui(imageArray, sampler, coord);
        float3 normal = {
            clamp(tex.x / 255.0f, 0.0f, 1.0f),
            clamp(tex.y / 255.0f, 0.0f, 1.0f),
            clamp(tex.z / 255.0f, 0.0f, 1.0f)
        };
        N = normalize(normal);
    }

    struct SceneProperties* scene = sceneData->scene;

    float3 origin = hitData->hitPoint + hitData->translate + N * 0.0001f;
    float3 viewPos = {
        sceneData->camData[0],
        sceneData->camData[1],
        sceneData->camData[2]};
    float3 V = normalize(viewPos - origin);
    float3 L = normalize(-scene->lights[0].direction.xyz);

    // Shadow test 
    struct Payload shadowPayload;
    traceRay(sceneData->topLevel, 2, 4, origin, L, 0.01, 1000, &shadowPayload,
        sceneData, imageArray, sampler);

    float3 color = {0.0f, 0.0f, 0.0f};
    if (!shadowPayload.hit)
    {
        // Specular contribution
        float3 Lo = {0.0f, 0.0f, 0.0f};

        // TODO: support multiple lights
        float3 lightColor = scene->lights[0].color.rgb;
        Lo += BRDF(L, V, N, metallicFrag, roughnessFrag, albedoFrag) * lightColor;

        color += Lo;
    }

    // Combine with ambient
    color += albedoFrag * 0.05f;

    payload->color[0] = color.x;
    payload->color[1] = color.y;
    payload->color[2] = color.z;

    ////////////////////////////////////////
    //      Global illumination Begin     //
    ////////////////////////////////////////

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

    ////////////////////////////////////////
    //      Global illumination End       //
    ////////////////////////////////////////

    if (sceneData->debug == 1)
    {
        // [debug] normal viz
        // R:x, G:y, B:z = [0.0, 0.1]
        //      +y        in:  -z
        //  +x      -x
        //      -y        out: +z
        payload->color = N / 2.0f + 0.5f;
    }
    else if (sceneData->debug == 2)
    {
        payload->color = L / 2.0f + 0.5f;
    }
    else if (sceneData->debug == 3)
    {
        payload->color = V / 2.0f + 0.5f;
    }
    else if (sceneData->debug == 4)
    {
        payload->color = dot(N, L) / 2.0f + 0.5f;
    }
    else if (sceneData->debug == 5)
    {
        float3 a = BRDF(L, V, N, metallicFrag, roughnessFrag, albedoFrag);
        payload->color = (a) / ((a) + 1.0f);
    }
    else if (sceneData->debug == 6)
    {
        // Shadow test: white color if no occlusion
        struct Payload shadowPayload;
        traceRay(sceneData->topLevel, 2, 4, origin, L, 0.01, 1000, &shadowPayload,
            sceneData, imageArray, sampler);
        payload->color = shadowPayload.color;
    }
    else if (sceneData->debug == 7)
    {
        payload->color.x = hitData->barycentric.x;
        payload->color.y = hitData->barycentric.y;
        payload->color.z = hitData->barycentric.z;
    }

    // // [debug] custom inst index viz
    // payload->color[0] = (uchar)hitData->instanceCustomIndex;
    // payload->color[1] = (uchar)hitData->instanceCustomIndex;
    // payload->color[2] = (uchar)hitData->instanceCustomIndex;
}

void shadowMiss(struct Payload* payload,
    struct SceneData* sceneData, image2d_array_t imageArray, sampler_t sampler)
{
    payload->hit = false;
    payload->color = 1.0f;
}

void environment(struct Payload* payload,
    struct SceneData* sceneData, image2d_array_t imageArray, sampler_t sampler)
{
    payload->hit = false;
    payload->color.x = 0.2;
    payload->color.y = 0.2;
    payload->color.z = 0.5;
}


void callHit(int sbtRecordOffset, struct Payload* payload, struct HitData* hitData,
    struct SceneData* sceneData, image2d_array_t imageArray, sampler_t sampler)
{
    int index = hitData->instanceSBTOffset + sbtRecordOffset;
    switch (index)
    {
		case 1:material(payload, hitData, sceneData, imageArray, sampler);break;
		case 2:shadow(payload, hitData, sceneData, imageArray, sampler);break;

        default: printf("Error: No hit shader found.");
    }
}


void callMiss(int missIndex, struct Payload* payload,
    struct SceneData* sceneData, image2d_array_t imageArray, sampler_t sampler)
{
    switch (missIndex)
    {
		case 3:environment(payload, sceneData, imageArray, sampler);break;
		case 4:shadowMiss(payload, sceneData, imageArray, sampler);break;

        default: printf("Error: No miss shader found.");
    }
}

