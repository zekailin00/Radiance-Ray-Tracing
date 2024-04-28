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
        color = pow(color, 0.7f);
    }

    image[CHANNEL * index + 0] = (int)(color[0] * 255);
    image[CHANNEL * index + 1] = (int)(color[1] * 255);
    image[CHANNEL * index + 2] = (int)(color[2] * 255);
    image[CHANNEL * index + 3] = 255;
}


inline uint3 getIndices(struct SceneData* sceneData, struct HitData* hitData)
{
    struct MeshInfo* meshInfo = &sceneData->meshInfoData[hitData->instanceIndex];
    int io = meshInfo->indexOffset;
    uint* indexData = sceneData->indexData;

    uint i0 = indexData[io + hitData->primitiveIndex * 3 + 0];
    uint i1 = indexData[io + hitData->primitiveIndex * 3 + 1];
    uint i2 = indexData[io + hitData->primitiveIndex * 3 + 2];

    uint3 indices = {i0, i1, i2};
    return indices;
}

inline float2 getUV(struct SceneData* sceneData, struct HitData* hitData)
{
    struct MeshInfo* meshInfo = &sceneData->meshInfoData[hitData->instanceIndex];
    int uo = meshInfo->uvOffset;
    float* uvData = sceneData->uvData;
    uint3 i = getIndices(sceneData, hitData);

    float2 uv0 = {uvData[uo + i.x * 3 + 0], uvData[uo + i.x * 3 + 1]};
    float2 uv1 = {uvData[uo + i.y * 3 + 0], uvData[uo + i.y * 3 + 1]};
    float2 uv2 = {uvData[uo + i.z * 3 + 0], uvData[uo + i.z * 3 + 1]};
    float2 uv  = hitData->barycentric.x * uv0 +
                 hitData->barycentric.y * uv1 + 
                 hitData->barycentric.z * uv2;
    return uv;
}

inline float3 getFaceNormal(struct SceneData* sceneData, struct HitData* hitData)
{
    struct MeshInfo* meshInfo = &sceneData->meshInfoData[hitData->instanceIndex];
    int no = meshInfo->normalOffset;
    float* normalData = sceneData->normalData;
    uint3 i = getIndices(sceneData, hitData);

    float3 N;
    {
        float4 n0 = {
            normalData[no + i.x * 3 + 0],
            normalData[no + i.x * 3 + 1],
            normalData[no + i.x * 3 + 2], 0.0f};
        float4 n1 = {
            normalData[no + i.y * 3 + 0],
            normalData[no + i.y * 3 + 1],
            normalData[no + i.y * 3 + 2], 0.0f};
        float4 n2 = {
            normalData[no + i.z * 3 + 0],
            normalData[no + i.z * 3 + 1],
            normalData[no + i.z * 3 + 2], 0.0f};
        float4 normal = hitData->barycentric.x * n0 +
                        hitData->barycentric.y * n1 + 
                        hitData->barycentric.z * n2;
        float4 tmp;
        MultiplyMat4Vec4(&hitData->transform, &normal, &tmp);
        N = normalize(tmp.xyz);
    }
    return N;
}

inline float3 getMatNormal(struct SceneData* sceneData, struct HitData* hitData,
    image2d_array_t imageArray, sampler_t sampler, float3 faceNormal)
{
    struct MeshInfo* meshInfo = &sceneData->meshInfoData[hitData->instanceIndex];
    struct Material* material = &sceneData->materials[meshInfo->materialIndex];

    if (material->normalTexIdx != -1)
    {
        float2 uv = getUV(sceneData, hitData);
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
        GetNormalSpace(faceNormal, &transform);
        float4 globalNormal;
        MultiplyMat4Vec4(&transform, &localNormal, &globalNormal);
        faceNormal = normalize(globalNormal.xyz);
    }

    return faceNormal;
}

// float4: {metallicFrag, roughnessFrag, transmissionFrag, iorFrag}
inline float4 getMaterialProp(struct SceneData* sceneData, struct HitData* hitData,
    image2d_array_t imageArray, sampler_t sampler)
{
    struct MeshInfo* meshInfo = &sceneData->meshInfoData[hitData->instanceIndex];
    struct Material* material = &sceneData->materials[meshInfo->materialIndex];
    float2 uv = getUV(sceneData, hitData);

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
        roughnessFrag = clamp(tex.y / 255.0f, 0.05f, 1.0f);
    }

    float transFrag = clamp(material->transmission, 0.0f, 1.0f);
    float iorFrag = clamp(material->ior, 0.0f, 10.0f);

    float4 matProp = {metallicFrag, roughnessFrag, transFrag, iorFrag};
    return matProp;
}

inline float3 getAlbedo(struct SceneData* sceneData, struct HitData* hitData,
    image2d_array_t imageArray, sampler_t sampler)
{
    struct MeshInfo* meshInfo = &sceneData->meshInfoData[hitData->instanceIndex];
    struct Material* material = &sceneData->materials[meshInfo->materialIndex];
    float2 uv = getUV(sceneData, hitData);

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
    return albedoFrag;
}

inline float3 getHitPosition(struct HitData* hitData, float3 N)
{
    // Get global hit position
    float3 hitPos;
    {
        float4 tmp0;
        float4 tmp1 = {
            hitData->hitPoint.x,
            hitData->hitPoint.y,
            hitData->hitPoint.z, 1.0f
        };
        MultiplyMat4Vec4(&hitData->transform, &tmp1, &tmp0);
        hitPos = tmp0.xyz + N * 0.00001f;
    }
    return hitPos;
}

inline float3 getLightDirection(struct SceneData* sceneData)
{
    struct SceneProperties* scene = sceneData->scene;
    float3 L = normalize(-scene->lights[0].direction.xyz);
    return L;
}

inline float3 getViewDirection(struct Payload* payload)
{
    return normalize(-payload->nextRayDirection);
}

void material(struct Payload* payload, struct HitData* hitData,
    struct SceneData* sceneData, image2d_array_t imageArray, sampler_t sampler)
{
    payload->hit = true;

    float3 faceN = getFaceNormal(sceneData, hitData);
    float3 hitPos = getHitPosition(hitData, faceN);
    
    float3 N = getMatNormal(sceneData, hitData, imageArray, sampler, faceN);
    float3 L = getLightDirection(sceneData);
    float3 V = getViewDirection(payload);

    // float4 mat <x,y,z,w> := <metallic, roughness, transmission, ior>
    float4 mat = getMaterialProp(sceneData, hitData, imageArray, sampler);
    float3 albedo = getAlbedo(sceneData, hitData, imageArray, sampler);

    // Shadow test 
    struct Payload shadowPayload;
    traceRay(sceneData->topLevel, 2, 4, hitPos, L, 0.01, 1000,
        &shadowPayload, sceneData, imageArray, sampler);

    float3 color = {0.0f, 0.0f, 0.0f};
    if (!shadowPayload.hit) // TODO: support multiple lights
    {
        struct SceneProperties* scene = sceneData->scene;
        float3 radiance = scene->lights[0].color.rgb; // dot is included in brdf
        color += microfacetBRDF(L, V, N, albedo, mat.x, mat.y, mat.z, mat.w) * radiance;
    }

    // Combine with ambient
    color += albedo * 0.1f;

    payload->color[0] = color.x;
    payload->color[1] = color.y;
    payload->color[2] = color.z;

    ////////////////////////////////////////
    //      Global illumination Begin     //
    ////////////////////////////////////////

    // different random value for each pixel and each frame
    uint3 randInput = {sceneData->frameID, (uint)get_global_id(0), sceneData->depth};
    float3 random = random_pcg3d(randInput);
    
    // sample indirect direction
    float3 nextFactor = {0.0f, 0.0f, 0.0f};
    float3 nextDir = sampleMicrofacetBRDF_transm(V, N, albedo,
        mat.x, mat.y, mat.z, mat.w, random, &nextFactor);
    if (dot(nextDir, N) < 0)
        hitPos = getHitPosition(hitData, -faceN);
    
    // indirect ray
    payload->nextRayOrigin = hitPos;
    payload->nextRayDirection = nextDir;
    payload->nextFactor = nextFactor;

    ////////////////////////////////////////
    //      Global illumination End       //
    ////////////////////////////////////////
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

void shadow(struct Payload* payload, struct HitData* hitData,
    struct SceneData* sceneData, image2d_array_t imageArray, sampler_t sampler)
{
    // Shadow test
    payload->hit = true;
    payload->color = 0.0f;
}

void anyShadow(bool* cont, struct Payload* payload, struct HitData* hitData,
    struct SceneData* sceneData, image2d_array_t imageArray, sampler_t sampler)
{
    // Shadow test
    *cont = false;
}

void callAnyHit(bool* cont, int sbtRecordOffset, struct Payload* payload, struct HitData* hitData,
    struct SceneData* sceneData, image2d_array_t imageArray, sampler_t sampler)
{

    int index = hitData->instanceSBTOffset + sbtRecordOffset;
    switch (index)
    {
		case 2:anyShadow(cont, payload, hitData, sceneData, imageArray, sampler);break;
    }
}

void callHit(int sbtRecordOffset, struct Payload* payload, struct HitData* hitData,
    struct SceneData* sceneData, image2d_array_t imageArray, sampler_t sampler)
{
    int index = hitData->instanceSBTOffset + sbtRecordOffset;
    switch (index)
    {
		case 1:material(payload, hitData, sceneData, imageArray, sampler);break;
		case 2:shadow(payload, hitData, sceneData, imageArray, sampler);break;
    }
}


void callMiss(int missIndex, struct Payload* payload,
    struct SceneData* sceneData, image2d_array_t imageArray, sampler_t sampler)
{
    switch (missIndex)
    {
		case 3:environment(payload, sceneData, imageArray, sampler);break;
		case 4:shadowMiss(payload, sceneData, imageArray, sampler);break;
    }
}

//    if (sceneData->debug == 1)
//     {
//         // [debug] normal viz
//         // R:x, G:y, B:z = [0.0, 0.1]
//         //      +y        in:  -z
//         //  +x      -x
//         //      -y        out: +z
//         payload->color = N / 2.0f + 0.5f;
//     }
//     else if (sceneData->debug == 2)
//     {
//         payload->color = L / 2.0f + 0.5f;
//     }
//     else if (sceneData->debug == 3)
//     {
//         payload->color = V / 2.0f + 0.5f;
//     }
//     else if (sceneData->debug == 4)
//     {
//         payload->color = dot(N, L) / 2.0f + 0.5f;
//     }
//     else if (sceneData->debug == 5)
//     {
//         float3 a = BRDF(L, V, N, metallicFrag, roughnessFrag, albedoFrag);
//         payload->color = (a) / ((a) + 1.0f);
//     }
//     else if (sceneData->debug == 6)
//     {
//         // Shadow test: white color if no occlusion
//         struct Payload shadowPayload;
//         traceRay(sceneData->topLevel, 2, 4, hitPos, L, 0.01, 1000, &shadowPayload,
//             sceneData, imageArray, sampler);
//         payload->color = shadowPayload.color;
//     }
//     else if (sceneData->debug == 7)
//     {
//         payload->color.x = hitData->barycentric.x;
//         payload->color.y = hitData->barycentric.y;
//         payload->color.z = hitData->barycentric.z;
//     }
//     else if (sceneData->debug == 8)
//     {
//         payload->color = albedoFrag;
//     }
//     else if (sceneData->debug == 9)
//     {
//         payload->color.x = metallicFrag;
//         payload->color.y = metallicFrag;
//         payload->color.z = metallicFrag;
//     }
//     else if (sceneData->debug == 10)
//     {
//         payload->color.x = roughnessFrag;
//         payload->color.y = roughnessFrag;
//         payload->color.z = roughnessFrag;
//     }
//     else if (sceneData->debug == 11)
//     {   // Diffuse component
//         float3 H = normalize(V + L);
//         float dotVH = clamp(dot(V, H), 0.0f, 1.0f);
//         float3 F = F_Schlick(dotVH, metallicFrag, albedoFrag);
//         float3 c_diff = albedoFrag * (1.0f - metallicFrag);
//         float3 f_diffuse  = (1 - F) * (1 / 3.1415f) * c_diff;
//         payload->color = f_diffuse;
//     }
//     else if (sceneData->debug == 12)
//     {   // Frensel reflection
//         float3 H = normalize(V + L);
//         float dotVH = clamp(dot(V, H), 0.0f, 1.0f);
//         payload->color = F_Schlick(dotVH, metallicFrag, albedoFrag);
//     }
//     else if (sceneData->debug == 13)
//     {
//         float3 H = normalize(V + L);
//         float dotNH = clamp(dot(N, H), 0.0f, 1.0f);

//         float D = D_GGX(dotNH, roughnessFrag);
//         payload->color = clamp(D, 0.0f, 1.0f);
//     }
//     else if (sceneData->debug == 14)
//     {
//         float dotNV = clamp(dot(N, V), 0.0f, 1.0f);
//         float dotNL = clamp(dot(N, L), 0.0f, 1.0f);

//         float G = G_Smith_Disney(dotNL, dotNV, roughnessFrag);
//         payload->color = G;
//     }
//     else if (sceneData->debug == 15)
//     {
//         float dotNV = clamp(dot(N, V), 0.0f, 1.0f);
//         float dotNL = clamp(dot(N, L), 0.0f, 1.0f);

//         float G = G_SchlicksmithGGX(dotNL, dotNV, roughnessFrag);
//         payload->color = G;
//     }
//     else if (sceneData->debug == 16)
//     {
//         float dotNV = clamp(dot(N, V), 0.0f, 1.0f);
//         float dotNL = clamp(dot(N, L), 0.0f, 1.0f);

//         float G = G_SmithGGXCorrelated(dotNL, dotNV, roughnessFrag);
//         payload->color = (1.0f / (G)) / (1.0f / (G) + 1);
//     }
//     else if (sceneData->debug == 17)
//     {
//         float G = G_pbrt(V, L, N, roughnessFrag);
//         payload->color = G;
//     }