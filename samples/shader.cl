#include <radiance.cl>

struct Payload
{
    uchar x;
    uchar y;
    uchar color[3];
    bool hit;

    float*                     camData;
    float*                     vertexData;
    uint*                      indexData;
    struct Material*           materials;
    struct SceneProperties*    scene;
};

__kernel void raygen(
    __global uchar*                     image /* <row major> */,
    __global unsigned int*              extent /* <x,y> */,
    __global float*                     camData,
    __global float*                     vertexData,
    __global uint*                      indexData,
    __global struct Material*           materials,
    __global struct SceneProperties*    scene,
    __global struct AccelStruct*        topLevel)
{
    /* the unique global id of the work item for the current pixel */
    const int work_item_id = get_global_id(0);

    int x = work_item_id % (int)extent[0]; /* x-coordinate of the pixel */
    int y = work_item_id / (int)extent[0]; /* y-coordinate of the pixel */
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

    struct Payload payload;
    payload.x = (int)(fx * 256);
    payload.y = (int)(fy * 256);
    payload.color[0] = 0.0f;
    payload.color[1] = 0.0f;
    payload.color[2] = 0.0f;
    payload.camData = camData;
    payload.vertexData = vertexData;
    payload.indexData = indexData;
    payload.materials = materials;
    payload.scene = scene;

    traceRay(topLevel, origin, dir, 0.01, 100, &payload);

    const int CHANNEL = 4;
    int index = (int)(extent[0] * (extent[1] - y - 1) + (extent[0] - x - 1));
    image[CHANNEL * index + 0] = payload.color[0];
    image[CHANNEL * index + 1] = payload.color[1];
    image[CHANNEL * index + 2] = payload.color[2];
    image[CHANNEL * index + 3] = 255;
}


void hit(struct Payload* payload, struct HitData* hitData)
{
    float* vertexData = payload->vertexData;
    uint* indexData = payload->indexData;
    uint i0 = indexData[hitData->primitiveIndex * 3 + 0];
    uint i1 = indexData[hitData->primitiveIndex * 3 + 1];
    uint i2 = indexData[hitData->primitiveIndex * 3 + 2];

    float3 v0 = {vertexData[i0 * 3 + 0], vertexData[i0 * 3 + 1], vertexData[i0 * 3 + 2]};
    float3 v1 = {vertexData[i1 * 3 + 0], vertexData[i1 * 3 + 1], vertexData[i1 * 3 + 2]};
    float3 v2 = {vertexData[i2 * 3 + 0], vertexData[i2 * 3 + 1], vertexData[i2 * 3 + 2]};

    float3 e1 = v1 - v0;
    float3 e2 = v2 - v0;
    float3 normal = cross(e1, e2);
    normal = normalize(normal);

    int matIndex = hitData->instanceIndex % 3;

    float3 viwePos = {
        payload->camData[0],
        payload->camData[1],
        payload->camData[2]
    };
    float4 color = CalculatePixelColor(
        &payload->materials[matIndex],
        payload->scene,
        &hitData->hitPoint,
        (float3*)payload->camData,
        &normal
    );

    payload->color[0] = color.x * 255;
    payload->color[1] = color.y * 255;
    payload->color[2] = color.z * 255;

    // normal = fabs(normal);
    // payload->color[0] = normal.x * 255;
    // payload->color[1] = normal.y * 255;
    // payload->color[2] = normal.z * 255;

    // payload->color[0] = (uchar)hitData->instanceCustomIndex;
    // payload->color[1] = (uchar)hitData->instanceCustomIndex;
    // payload->color[2] = (uchar)hitData->instanceCustomIndex;

    payload->hit = true;
}

void miss(struct Payload* payload)
{
    payload->color[0] = payload->x;
    payload->color[1] = payload->y;
    payload->color[2] = 0;
    payload->hit = false;
}