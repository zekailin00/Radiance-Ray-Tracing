#include <radiance.cl>

struct Payload
{
    uchar x;
    uchar y;
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

    int x = work_item_id % (int)extent[0]; /* x-coordinate of the pixel */
    int y = work_item_id / (int)extent[0]; /* y-coordinate of the pixel */
    float fx = ((float)x / (float)extent[0]); /* convert int to float in range [0-1] */
    float fy = ((float)y / (float)extent[1]); /* convert int to float in range [0-1] */

    float f0 = 2; // focal length
    float3 direction = {fx - 0.5, fy - 0.5f, f0};
    direction = normalize(direction);
    float3 origin = {0.0f, 0.0f, -1.0};

    struct Payload payload;
    payload.x = (int)(fx * 256);
    payload.y = (int)(fy * 256);
    payload.color[0] = 0.0f;
    payload.color[1] = 0.0f;
    payload.color[2] = 0.0f;

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
    if (hitData->normal.x < 0.0f)
        hitData->normal.x *= -1.0;
    if (hitData->normal.y < 0.0f)
        hitData->normal.y *= -1.0;
    if (hitData->normal.z < 0.0f)
        hitData->normal.z *= -1.0;
    payload->color[0] = (unsigned int)(hitData->normal.x * 255);
    payload->color[1] = (unsigned int)(hitData->normal.y * 255);
    payload->color[2] = (unsigned int)(hitData->normal.z * 255);
    payload->hit = true;
}

void miss(struct Payload* payload)
{
    payload->color[0] = payload->x;
    payload->color[1] = payload->y;
    payload->color[2] = 0;
    payload->hit = false;
}