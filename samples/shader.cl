#include "radiance.cl"
#include "pbr.cl"

struct Payload
{
    float3 radiance;
    float3 ambience;
    bool hit;

    float3 shadowOrigin;
    float3 shadowDirection;

    float3 nextFactor;
    float3 nextRayOrigin;
    float3 nextRayDirection;
};

struct SceneData
{
    __global struct PhysicalCamera*     camData;
    __global struct SceneProperties*    scene;
    
    __global struct MeshInfo*           meshInfoData;
    __global float*                     vertexData;
    __global uint*                      indexData;
    __global float*                     uvData;
    __global float*                     normalData;
    __global struct Material*           materials;
    __global struct AccelStruct*        topLevel;

    int                        depth;
    unsigned int               frameID;
    unsigned int               debug;
};

struct Camera
{
    float x, y, z, focal;
    float wx, wy, wz, exposure;
};

struct PhysicalCamera
{
    float widthPixel, heightPixel;  // integer pixel count; e.g. [1920.0f, 1080.0f]
    float focalLength, sensorWidth; // in meter; controls fov; e.g. 0.0025m = 25mm
    float focalDistance, fStop;     // in meter, depth of view; F/N = aperture diameter
    float x, y, z;                  // camera position in meter
    float wx, wy, wz;               // camera rotation in degree
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

inline float2 sampleUniformDisk(float2 u)
{
    // Map _u_ to $[-1,1]^2$ and handle degeneracy at the origin
    float2 uOffset = 2.0f * u - 1.0f;
    if (uOffset.x == 0.0f && uOffset.y == 0.0f)
        return 0.0f;

    // Apply concentric mapping to point
    float theta, r;
    if (fabs(uOffset.x) > fabs(uOffset.y)) {
        r = uOffset.x;
        theta = (PI / 4.0f) * (uOffset.y / uOffset.x);
    }
    else {
        r = uOffset.y;
        theta = (PI / 2.0f) - (PI / 4.0f) * (uOffset.x / uOffset.y);
    }

    float2 tmp = {cos(theta), sin(theta)};
    return r * tmp;
}

void generateRay(const global struct PhysicalCamera* cam,
    const uint3 randomInput, float3* position, float3* direction)
{
    /* the unique global id of the work item for the current pixel */
    const int index = get_global_id(0);

    // Index for accessing image data
    const int x = index % (int)cam->widthPixel; /* x-coordinate of the pixel */
    const int y = index / (int)cam->widthPixel; /* y-coordinate of the pixel */

    float3 random = random_pcg3d(randomInput);

    /* convert int to float in range [-0.5, 0.5]  */
    float fx = (((float)x + random.x)/ cam->widthPixel) - 0.5f;
    float fy = 0.5f - (((float)y + random.y) / cam->heightPixel);

    float aspectRatio = cam->heightPixel / cam->widthPixel;
    float4 pinholeDirection = {
        fx * cam->sensorWidth, 
        fy * cam->sensorWidth * aspectRatio,
        -cam->focalLength, 0.0f
    };
    pinholeDirection = normalize(pinholeDirection);
    float3 pinholeOrigin = {cam->x, cam->y, cam->z};
    float time = -cam->focalDistance / pinholeDirection.z;

    // Transform camera position
    mat4x4 rotX, rotY, rotZ;
    float4 tmp;
    EulerXToMat4x4(cam->wx, &rotX);
    EulerYToMat4x4(cam->wy, &rotY);
    EulerZToMat4x4(cam->wz, &rotZ);
    MultiplyMat4Vec4(&rotZ, &pinholeDirection, &tmp);
    MultiplyMat4Vec4(&rotY, &tmp, &pinholeDirection);
    MultiplyMat4Vec4(&rotX, &pinholeDirection, &tmp);
    pinholeDirection = normalize(tmp);

    // return if camera is a pinhole camera
    if (cam->fStop == 0.0f) {
        *position = pinholeOrigin;
        *direction = pinholeDirection.xyz;
        return;
    }

    // Sample point on lens
    float lensRadius = (cam->focalLength / cam->fStop) / 2.0f;
    float2 lensPos = lensRadius * sampleUniformDisk(random.yz);

    // Compute point on plane of focus
    float3 hitPoint = pinholeOrigin + pinholeDirection.xyz * time;

    // Update ray for effect of lens
    float4 lensOrigin = {lensPos.x, lensPos.y, 0.0f, 1.0f};
    MultiplyMat4Vec4(&rotZ, &lensOrigin, &tmp);
    MultiplyMat4Vec4(&rotY, &tmp, &lensOrigin);
    MultiplyMat4Vec4(&rotX, &lensOrigin, &tmp);
    lensOrigin.xyz = pinholeOrigin + tmp.xyz;

    float3 lensDirection = normalize(hitPoint - lensOrigin.xyz);

    *position = lensOrigin.xyz;
    *direction = lensDirection;
}

__kernel void raygen(
    __global struct RayTraceProperties* RTProp,
    __global float*                     imageScratch,
    __global uchar*                     image /* <row major> */,
    __global struct PhysicalCamera*     camData,
    __global struct SceneProperties*    scene,

    __global struct MeshInfo*           meshInfoData,
    __global float*                     vertexData,
    __global uint*                      indexData,
    __global float*                     uvData,
    __global float*                     normalData,
    __global struct Material*           materials
    TEXTURE_TYPE,
    __global struct AccelStruct*        topLevel)
{
    /* the unique global id of the work item for the current pixel */
    const int index = get_global_id(0);
    const int CHANNEL = 4; // RGBA color output

    // Begin one batch of work
    int iteration = RTProp->batchSize;
    unsigned int frameID = RTProp->totalSamples;
    while (iteration > 0)
    {
        iteration--;

        // ray generation with anti-alising
        float3 rayOrigin, rayDirection;
        uint3 randInput = {frameID, RTProp->totalSamples, index};
        generateRay(camData, randInput, &rayOrigin, &rayDirection);

        struct Payload payload;
        payload.radiance = 0.0f;
        payload.nextFactor = 1.0f;
        payload.nextRayOrigin = rayOrigin;
        payload.nextRayDirection = rayDirection;

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
            int hitShaderIndex;
            if (RTProp->debug)
                hitShaderIndex = RTProp->debug + 4;
            else
                hitShaderIndex = 1;

            traceRay(topLevel, hitShaderIndex, 3, payload.nextRayOrigin, payload.nextRayDirection,
                0.001f, 1000, &payload, &sceneData TEXTURE_PARAM);

            if (payload.hit)
            {
                if (RTProp->debug)
                    color = payload.radiance;
                else
                {
                    // Shadow test 
                    traceRay(topLevel, 2, 4, payload.shadowOrigin, payload.shadowDirection,
                        0.001f, 1000, &payload, &sceneData TEXTURE_PARAM);
                    color += contribution * (payload.radiance + payload.ambience);
                    contribution *= payload.nextFactor;
                }
            }
            else if (sceneData.depth == 0)
            {
                // No direct hit, set background color.
                color = payload.radiance;
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
    __global struct MeshInfo* meshInfo = &sceneData->meshInfoData[hitData->instanceIndex];
    int io = meshInfo->indexOffset;
    __global uint* indexData = sceneData->indexData;

    uint i0 = indexData[io + hitData->primitiveIndex * 3 + 0];
    uint i1 = indexData[io + hitData->primitiveIndex * 3 + 1];
    uint i2 = indexData[io + hitData->primitiveIndex * 3 + 2];

    uint3 indices = {i0, i1, i2};
    return indices;
}

inline float2 getUV(struct SceneData* sceneData, struct HitData* hitData)
{
    __global struct MeshInfo* meshInfo = &sceneData->meshInfoData[hitData->instanceIndex];
    int uo = meshInfo->uvOffset;
    __global float* uvData = sceneData->uvData;
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
    __global struct MeshInfo* meshInfo = &sceneData->meshInfoData[hitData->instanceIndex];
    int no = meshInfo->normalOffset;
    __global float* normalData = sceneData->normalData;
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

inline float3 getMatNormal(struct SceneData* sceneData, struct HitData* hitData TEXTURE_TYPE, float3 faceNormal)
{
    __global struct MeshInfo* meshInfo = &sceneData->meshInfoData[hitData->instanceIndex];
    __global struct Material* material = &sceneData->materials[meshInfo->materialIndex];

#ifdef IMAGE_SUPPORT
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
#endif

    return faceNormal;
}

// float4: {metallicFrag, roughnessFrag, transmissionFrag, iorFrag}
inline float4 getMaterialProp(struct SceneData* sceneData, struct HitData* hitData TEXTURE_TYPE)
{
    __global struct MeshInfo* meshInfo = &sceneData->meshInfoData[hitData->instanceIndex];
    __global struct Material* material = &sceneData->materials[meshInfo->materialIndex];
    float2 uv = getUV(sceneData, hitData);

    float metallicFrag;
    if (material->metallicTexIdx == -1)
        metallicFrag = material->metallic;
#ifdef IMAGE_SUPPORT
    else
    {
        float4 coord = {uv.x, 1.0f - uv.y, (float)material->metallicTexIdx, 0.0f};
        uint4 tex = read_imageui(imageArray, sampler, coord);
        metallicFrag = clamp(tex.z / 255.0f, 0.0f, 1.0f);
    }
#endif

    float roughnessFrag;
    if (material->roughnessTexIdx == -1)
        roughnessFrag = clamp(material->roughness, 0.0f, 1.0f);
#ifdef IMAGE_SUPPORT
    else
    {
        float4 coord = {uv.x, 1.0f - uv.y, (float)material->roughnessTexIdx, 0.0f};
        uint4 tex = read_imageui(imageArray, sampler, coord);
        roughnessFrag = clamp(tex.y / 255.0f, 0.05f, 1.0f);
    }
#endif

    float transFrag = clamp(material->transmission, 0.0f, 1.0f);
    float iorFrag = clamp(material->ior, 0.0f, 10.0f);

    float4 matProp = {metallicFrag, roughnessFrag, transFrag, iorFrag};
    return matProp;
}

inline float3 getAlbedo(struct SceneData* sceneData, struct HitData* hitData TEXTURE_TYPE)
{
    __global struct MeshInfo* meshInfo = &sceneData->meshInfoData[hitData->instanceIndex];
    __global struct Material* material = &sceneData->materials[meshInfo->materialIndex];
    float2 uv = getUV(sceneData, hitData);

    float3 albedoFrag;
    if (material->albedoTexIdx == -1)
        albedoFrag = material->albedo.rgb;
#ifdef IMAGE_SUPPORT
    else
    {
        float4 coord = {uv.x, 1.0f - uv.y, (float)material->albedoTexIdx, 0.0f};
        uint4 tex = read_imageui(imageArray, sampler, coord);
        albedoFrag.x = clamp(tex.x / 255.0f, 0.0f, 1.0f);
        albedoFrag.y = clamp(tex.y / 255.0f, 0.0f, 1.0f);
        albedoFrag.z = clamp(tex.z / 255.0f, 0.0f, 1.0f);
    }
#endif
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
    __global struct SceneProperties* scene = sceneData->scene;
    float3 L = normalize(-scene->lights[0].direction.xyz);
    return L;
}

inline float3 getViewDirection(struct Payload* payload)
{
    return normalize(-payload->nextRayDirection);
}

void material(struct Payload* payload, struct HitData* hitData,
    struct SceneData* sceneData TEXTURE_TYPE)
{
    payload->hit = true;

    float3 faceN = getFaceNormal(sceneData, hitData);
    float3 hitPos = getHitPosition(hitData, faceN);
    
    float3 N = getMatNormal(sceneData, hitData TEXTURE_PARAM, faceN);
    float3 L = getLightDirection(sceneData);
    float3 V = getViewDirection(payload);

    // float4 mat <x,y,z,w> := <metallic, roughness, transmission, ior>
    float4 mat = getMaterialProp(sceneData, hitData TEXTURE_PARAM);
    float3 albedo = getAlbedo(sceneData, hitData TEXTURE_PARAM);

    float3 light = sceneData->scene->lights[0].color.rgb; // dot is included in brdf
    payload->radiance = microfacetBRDF(L, V, N, albedo, mat.x, mat.y, mat.z, mat.w) * light;
    payload->ambience = albedo * 0.1f;
    payload->shadowDirection = L;
    payload->shadowOrigin = hitPos;

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
    struct SceneData* sceneData TEXTURE_TYPE)
{
    payload->hit = false;
}

void environment(struct Payload* payload,
    struct SceneData* sceneData TEXTURE_TYPE)
{
    payload->hit = false;
    payload->radiance.x = 0.2f;
    payload->radiance.y = 0.2f;
    payload->radiance.z = 0.5f;
}

void shadow(struct Payload* payload, struct HitData* hitData,
    struct SceneData* sceneData TEXTURE_TYPE)
{
    // Shadow test
    payload->hit = true;
    payload->radiance = 0.0f;
}

void anyShadow(bool* cont, struct Payload* payload, struct HitData* hitData,
    struct SceneData* sceneData TEXTURE_TYPE)
{
    // Shadow test
    *cont = false;
}

////////// Debug shaders begin //////////////////////

void dbgNorm(struct Payload* payload, struct HitData* hitData,
    struct SceneData* sceneData TEXTURE_TYPE)
{
    payload->hit = true;
    float3 faceN = getFaceNormal(sceneData, hitData);
    float3 N = getMatNormal(sceneData, hitData TEXTURE_PARAM, faceN);

    // [debug] normal viz
    // R:x, G:y, B:z = [0.0, 0.1]
    //      +y        in:  -z
    //  +x      -x
    //      -y        out: +z
    payload->radiance = N / 2.0f + 0.5f;
}

void dbgBary(struct Payload* payload, struct HitData* hitData,
    struct SceneData* sceneData TEXTURE_TYPE)
{
    payload->hit = true;
    payload->radiance.xyz = hitData->barycentric.xyz;
}

void dbgAlbedo(struct Payload* payload, struct HitData* hitData,
    struct SceneData* sceneData TEXTURE_TYPE)
{
    payload->hit = true;
    float3 albedo = getAlbedo(sceneData, hitData TEXTURE_PARAM);
    payload->radiance = albedo;
}

void dbgMetal(struct Payload* payload, struct HitData* hitData,
    struct SceneData* sceneData TEXTURE_TYPE)
{
    payload->hit = true;
    // float4 mat <x,y,z,w> := <metallic, roughness, transmission, ior>
    float4 mat = getMaterialProp(sceneData, hitData TEXTURE_PARAM);
    payload->radiance = mat.x;
}

void dbgRough(struct Payload* payload, struct HitData* hitData,
    struct SceneData* sceneData TEXTURE_TYPE)
{
    payload->hit = true;
    // float4 mat <x,y,z,w> := <metallic, roughness, transmission, ior>
    float4 mat = getMaterialProp(sceneData, hitData TEXTURE_PARAM);
    payload->radiance = mat.y;
}

void dbgBRDF(struct Payload* payload, struct HitData* hitData,
    struct SceneData* sceneData TEXTURE_TYPE)
{
    payload->hit = true;

    float3 faceN = getFaceNormal(sceneData, hitData);
    
    float3 N = getMatNormal(sceneData, hitData TEXTURE_PARAM, faceN);
    float3 L = getLightDirection(sceneData);
    float3 V = getViewDirection(payload);

    // float4 mat <x,y,z,w> := <metallic, roughness, transmission, ior>
    float4 mat = getMaterialProp(sceneData, hitData TEXTURE_PARAM);
    float3 albedo = getAlbedo(sceneData, hitData TEXTURE_PARAM);

    float3 brdf = microfacetBRDF(L, V, N, albedo, mat.x, mat.y, mat.z, mat.w);
    payload->radiance = brdf / (brdf + 1.0f);
}

void dbgFres(struct Payload* payload, struct HitData* hitData,
    struct SceneData* sceneData TEXTURE_TYPE)
{
    payload->hit = true;

    float3 L = getLightDirection(sceneData);
    float3 V = getViewDirection(payload);

    // float4 mat <x,y,z,w> := <metallic, roughness, transmission, ior>
    float4 mat = getMaterialProp(sceneData, hitData TEXTURE_PARAM);
    float3 albedo = getAlbedo(sceneData, hitData TEXTURE_PARAM);
    
    // Frensel reflection
    float3 H = normalize(V + L);
    float dotVH = clamp(dot(V, H), 0.0f, 1.0f);
    payload->radiance = F_Schlick(dotVH, mat.x, albedo);
}

void dbgGGX(struct Payload* payload, struct HitData* hitData,
    struct SceneData* sceneData TEXTURE_TYPE)
{
    payload->hit = true;

    // float4 mat <x,y,z,w> := <metallic, roughness, transmission, ior>
    float4 mat = getMaterialProp(sceneData, hitData TEXTURE_PARAM);
    float3 faceN = getFaceNormal(sceneData, hitData);

    float3 N = getMatNormal(sceneData, hitData TEXTURE_PARAM, faceN);
    float3 L = getLightDirection(sceneData);
    float3 V = getViewDirection(payload);
    float3 H = normalize(V + L);
    float dotNH = clamp(dot(N, H), 0.0f, 1.0f);

    float D = D_GGX(dotNH, mat.y);
    payload->radiance = clamp(D, 0.0f, 1.0f);
}

void dbgMask(struct Payload* payload, struct HitData* hitData,
    struct SceneData* sceneData TEXTURE_TYPE)
{
    payload->hit = true;

    // float4 mat <x,y,z,w> := <metallic, roughness, transmission, ior>
    float4 mat = getMaterialProp(sceneData, hitData TEXTURE_PARAM);
    float3 faceN = getFaceNormal(sceneData, hitData);

    float3 N = getMatNormal(sceneData, hitData TEXTURE_PARAM, faceN);
    float3 L = getLightDirection(sceneData);
    float3 V = getViewDirection(payload);

    float G = G_pbrt(V, L, N, mat.y);
    payload->radiance = G;
}

////////// Debug shaders end //////////////////////
void callAnyHit(bool* cont, int sbtRecordOffset, struct Payload* payload, struct HitData* hitData,
    struct SceneData* sceneData TEXTURE_TYPE)
{
    int index = hitData->instanceSBTOffset + sbtRecordOffset;
    switch (index)
    {
		case 2:anyShadow(cont, payload, hitData, sceneData TEXTURE_PARAM);break;

    }
}


void callHit(int sbtRecordOffset, struct Payload* payload, struct HitData* hitData,
    struct SceneData* sceneData TEXTURE_TYPE)
{
    int index = hitData->instanceSBTOffset + sbtRecordOffset;
    switch (index)
    {
		case 1:material(payload, hitData, sceneData TEXTURE_PARAM);break;
		case 2:shadow(payload, hitData, sceneData TEXTURE_PARAM);break;
		case 5:dbgNorm(payload, hitData, sceneData TEXTURE_PARAM);break;
		case 6:dbgBary(payload, hitData, sceneData TEXTURE_PARAM);break;
		case 7:dbgAlbedo(payload, hitData, sceneData TEXTURE_PARAM);break;
		case 8:dbgMetal(payload, hitData, sceneData TEXTURE_PARAM);break;
		case 9:dbgRough(payload, hitData, sceneData TEXTURE_PARAM);break;
		case 10:dbgBRDF(payload, hitData, sceneData TEXTURE_PARAM);break;
		case 11:dbgFres(payload, hitData, sceneData TEXTURE_PARAM);break;
		case 12:dbgGGX(payload, hitData, sceneData TEXTURE_PARAM);break;
		case 13:dbgMask(payload, hitData, sceneData TEXTURE_PARAM);break;

    }
}


void callMiss(int missIndex, struct Payload* payload,
    struct SceneData* sceneData TEXTURE_TYPE)
{
    switch (missIndex)
    {
		case 3:environment(payload, sceneData TEXTURE_PARAM);break;
		case 4:shadowMiss(payload, sceneData TEXTURE_PARAM);break;

    }
}

