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
    struct Camera*             camData;
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

struct Camera
{
    float x, y, z, focal;
    float wx, wy, wz, exposure;
};

float3 aces_approx(float3 v)
{
    v *= 0.6f;
    float a = 2.51f;
    float b = 0.03f;
    float c = 2.43f;
    float d = 0.59f;
    float e = 0.14f;
    return clamp((v*(a*v+b))/(v*(c*v+d)+e), 0.0f, 1.0f);
}

float3 uncharted2_tonemap_partial(float3 x)
{
    float A = 0.15f;
    float B = 0.50f;
    float C = 0.10f;
    float D = 0.20f;
    float E = 0.02f;
    float F = 0.30f;
    return ((x*(A*x+C*B)+D*E)/(x*(A*x+B)+D*F))-E/F;
}

float3 uncharted2_filmic(float3 v)
{
    float exposure_bias = 2.0f;
    float3 curr = uncharted2_tonemap_partial(v * exposure_bias);

    float3 W = 11.2f;
    float3 white_scale = 1.0f / uncharted2_tonemap_partial(W);
    return clamp(curr * white_scale, 0.0f, 1.0f);
}

float3 clamping(float3 v)
{
    return clamp(v, 0.0f, 1.0f);
}

float3 reinhard(float3 v)
{
    return v / (v + 1.0f);
}

__kernel void raygen(
    __global struct RayTraceProperties* RTProp,
    __global float*                     imageScratch,
    __global uchar*                     image /* <row major> */,
    __global unsigned int*              extent /* <x,y> */,
    __global struct Camera*             camData,
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

        float f0 = camData->focal; // focal length
        float4 dir = {fx, fy, f0, 0.0f}; /* range [-0.5, 0.5] */
        dir = normalize(dir);
        float3 origin = {camData->x, camData->y, camData->z};

        // Transform camera position
        mat4x4 rotX, rotY, rotZ;
        float4 tmpDir;
        EulerXToMat4x4(camData->wx, &rotX);
        EulerYToMat4x4(camData->wy, &rotY);
        EulerZToMat4x4(camData->wz, &rotZ);
        MultiplyMat4Vec4(&rotZ, &dir, &tmpDir);
        MultiplyMat4Vec4(&rotY, &tmpDir, &dir);
        MultiplyMat4Vec4(&rotX, &dir, &tmpDir);
        dir = normalize(tmpDir);

        struct Payload payload;
        payload.x = x;
        payload.y = y;
        payload.color[0] = 0.0f;
        payload.color[1] = 0.0f;
        payload.color[2] = 0.0f;
        payload.nextFactor = 1.0f;
        payload.nextRayOrigin = origin;
        payload.nextRayDirection = dir.xyz;

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
        // color = reinhard(color);
        // color = clamping(color);
        color = aces_approx(color);
        // color = uncharted2_filmic(color);

        // Gamma correct
        color = pow(color, 0.4545f);
    }

    image[CHANNEL * index + 0] = (int)(color[0] * 255);
    image[CHANNEL * index + 1] = (int)(color[1] * 255);
    image[CHANNEL * index + 2] = (int)(color[2] * 255);
    image[CHANNEL * index + 3] = 255;
}

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

    float3 N; {
        float4 n0 = {normalData[no + i0 * 3 + 0], normalData[no + i0 * 3 + 1], normalData[no + i0 * 3 + 2], 0.0f};
        float4 n1 = {normalData[no + i1 * 3 + 0], normalData[no + i1 * 3 + 1], normalData[no + i1 * 3 + 2], 0.0f};
        float4 n2 = {normalData[no + i2 * 3 + 0], normalData[no + i2 * 3 + 1], normalData[no + i2 * 3 + 2], 0.0f};
        float4 normal = hitData->barycentric.x * n0 +
                        hitData->barycentric.y * n1 + 
                        hitData->barycentric.z * n2;
        float4 tmp;
        MultiplyMat4Vec4(&hitData->transform, &normal, &tmp);
        N = normalize(tmp.xyz);
    }

    if (material->normalTexIdx != -1)
    {
        float4 coord = {uv.x, 1.0f - uv.y, (float)material->normalTexIdx, 0.0f};
        uint4 tex = read_imageui(imageArray, sampler, coord);
        float4 localNormal = {
            clamp(tex.x / 255.0f, 0.0f, 1.0f),
            clamp(tex.y / 255.0f, 0.0f, 1.0f),
            clamp(tex.z / 255.0f, 0.0f, 1.0f),
            0.0f
        };
        localNormal = normalize(localNormal * 2.0f - 1.0f);
        mat4x4 transform;
        GetNormalSpace(N, &transform);
        float4 globalNormal;
        MultiplyMat4Vec4(&transform, &localNormal, &globalNormal);
        N = normalize(globalNormal.xyz);
    }

    struct SceneProperties* scene = sceneData->scene;

    float3 hitPos; { // Get global hit position
        float4 tmp0, tmp1 = {hitData->hitPoint.x, hitData->hitPoint.y, hitData->hitPoint.z, 1.0f};
        MultiplyMat4Vec4(&hitData->transform, &tmp1, &tmp0);
        hitPos = tmp0.xyz + N * 0.0001f;
    }
    float3 viewPos = {
        sceneData->camData->x,
        sceneData->camData->y,
        sceneData->camData->z
    };
    float3 V = normalize(viewPos - hitPos);
    float3 L = normalize(-scene->lights[0].direction.xyz);

    // Shadow test 
    struct Payload shadowPayload;
    traceRay(sceneData->topLevel, 2, 4, hitPos, L, 0.01, 1000, &shadowPayload,
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
    payload->nextRayOrigin = hitPos;
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
        traceRay(sceneData->topLevel, 2, 4, hitPos, L, 0.01, 1000, &shadowPayload,
            sceneData, imageArray, sampler);
        payload->color = shadowPayload.color;
    }
    else if (sceneData->debug == 7)
    {
        payload->color.x = hitData->barycentric.x;
        payload->color.y = hitData->barycentric.y;
        payload->color.z = hitData->barycentric.z;
    }
    else if (sceneData->debug == 8)
    {
        payload->color = albedoFrag;
    }
    else if (sceneData->debug == 9)
    {
        payload->color.x = metallicFrag;
        payload->color.y = metallicFrag;
        payload->color.z = metallicFrag;
    }
    else if (sceneData->debug == 10)
    {
        payload->color.x = roughnessFrag;
        payload->color.y = roughnessFrag;
        payload->color.z = roughnessFrag;
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

