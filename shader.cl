#include <radiance.cl>

struct Payload
{
    int x;
    int y;
    uchar color[3];
    bool hit;
};

__kernel void raygen(
    __global uchar* image /* <row major> */,
    __global unsigned int* extent /* <x,y> */,
    __global struct AccelStruct* topLevel)
{
    /* the unique global id of the work item for the current pixel */
    const int work_item_id = get_global_id(0);

    if (get_global_id(0) == 0)
    {
        printf("\n[OpenCL Device] Start Executing Raygen\n");
        unsigned int nodeByteOffset = topLevel->nodeByteOffset;
        unsigned int faceRefByteOffset = topLevel->faceRefByteOffset;
        unsigned int faceByteOffset = topLevel->faceByteOffset;
        printf("[OpenCL Device] nodeByteOffset: %d\n", nodeByteOffset);
        printf("[OpenCL Device] faceRefByteOffset: %d\n", faceRefByteOffset);
        printf("[OpenCL Device] faceByteOffset: %d\n", faceByteOffset);
    }

    int x = work_item_id % (int)extent[0]; /* x-coordinate of the pixel */
    int y = work_item_id / (int)extent[0]; /* y-coordinate of the pixel */
    float fx = (float)x / (float)extent[0]; /* convert int to float in range [0-1] */
    float fy = (float)y / (float)extent[1]; /* convert int to float in range [0-1] */

    float f0 = 5; // focal length
    float3 direction = {fx, fy, f0};
    direction = normalize(direction);
    float3 origin = {0.0, 0.0, -5.0};

    __local struct Payload payload;
    payload.x = (int)(fx * 256);
    payload.y = (int)(fy * 256);

    traceRay(topLevel, origin, direction, 0.01, 100, &payload);

    const int CHANNEL = 4;
    int index = work_item_id; //(int)(extent[0] * y + x);
    image[CHANNEL * index + 0] = payload.color[0];
    image[CHANNEL * index + 1] = payload.color[1];
    image[CHANNEL * index + 2] = payload.color[2];
    image[CHANNEL * index + 3] = 0;
}


void hit(struct Payload* payload, struct HitData* hitData)
{
    payload->color[0] = 255;
    payload->color[1] = 0;
    payload->color[2] = 0;
    payload->hit = true;
}

void miss(struct Payload* payload)
{
    payload->color[0] = payload->x;
    payload->color[1] = payload->y;
    payload->color[2] = 0;
    payload->hit = false;
}