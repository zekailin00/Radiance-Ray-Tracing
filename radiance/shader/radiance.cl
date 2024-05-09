
#include "data.cl"
#include "math.cl"

struct Payload;
struct SceneData;

struct HitData
{
    float3 hitPoint;
    float distance;
    unsigned int primitiveIndex;        // Bottom-level triangle index (gl_PrimitiveID)
    unsigned int instanceIndex;         // Top-level instance index (gl_InstanceID)
    unsigned int instanceCustomIndex;   // Top-level instance custom index (gl_InstanceCustomIndexEXT)
    unsigned int instanceSBTOffset;     // VkAccelerationStructureInstanceKHR::instanceShaderBindingTableRecordOffset
    float3 barycentric;
    mat4x4 transform;                   // gl_ObjectToWorldEXT 4x3 matrix
};


#ifdef IMAGE_SUPPORT
    #define TEXTURE_TYPE , image2d_array_t imageArray, sampler_t sampler
    #define TEXTURE_PARAM , imageArray, sampler
#else
    #define TEXTURE_TYPE 
    #define TEXTURE_PARAM 
#endif

/* User defined begin */
struct Payload;

void callHit(int sbtRecordOffset, struct Payload* payload, struct HitData* hitData,
    struct SceneData* sceneData TEXTURE_TYPE);
void callMiss(int missIndex, struct Payload* payload, 
    struct SceneData* sceneData TEXTURE_TYPE);
void callAnyHit(bool* cont, int sbtRecordOffset, struct Payload* payload, struct HitData* hitData,
    struct SceneData* sceneData TEXTURE_TYPE);
/* User defined end */


bool intersectTriangle(float3 origin, float3 direction, 
                       __global const struct Triangle* triangle, __global Vertex* vertexList,
                       float3* intersectPoint, float* distance, float3* bary);
bool intersectAABB(float3 rayOrigin, float3 rayDir, float3 boxMin, float3 boxMax);


#define BVH_TOP_STACK_SIZE 8
#define BVH_BOT_STACK_SIZE 100

bool intersectBot(
    __global struct AccelStruct* accelStruct, float3 origin, float3 direction,
    float Tmin, float Tmax, struct HitData* hitData, bool* cont, int sbtRecordOffset,
    struct Payload* payload, struct SceneData* sceneData TEXTURE_TYPE)
{
    bool hasIntersected = false;
	unsigned int stack[BVH_BOT_STACK_SIZE];     // Stack pointing to BVH node index
	int stackIdx = 0;                       // Always point to the first empty element
	stack[stackIdx++] = 0;

	// while the stack is not empty
	while (stackIdx)
    {
		// pop a BVH node from the stack
		unsigned int nodeIdx = stack[stackIdx - 1];
		stackIdx--;

        __global struct BVHNode* nodeList = TO_BVH_NODE(accelStruct);
		__global struct BVHNode* node = nodeList + nodeIdx;

		if (!IS_LEAF(node)) // INNER NODE
        {
			// if ray intersects inner node, push indices of left and right child nodes on the stack
			if (intersectAABB(origin, direction, node->_bottom.xyz, node->_top.xyz))
            {
				stack[stackIdx++] = node->node.inner._idxRight; // right child node index
				stack[stackIdx++] = node->node.inner._idxLeft;  // left child node index
				
				// return if stack size is exceeded
				if (stackIdx > BVH_BOT_STACK_SIZE)
                {
                    printf("ERROR: Bottom AS stack overflow\n");
                    return false; 
                }
			}
		}
        else if (node->node.leaf._type == TYPE_TRIG)
        {
            __global Vertex* vertexList = TO_VERTEX(accelStruct);
            __global struct Triangle* faceList = TO_FACE(accelStruct);

            // loop over every triangle in the leaf node
            for (unsigned int i = 0; i < GET_COUNT(node); i++)
            {
                __global struct Triangle* face = &faceList[node->node.leaf._startIndexList + i];

                float3 intersectPoint;
                float distance;
                float3 bary;
                if (intersectTriangle(origin, direction, face, vertexList, &intersectPoint, &distance, &bary) &&
                    distance < hitData->distance && distance > Tmin && distance < Tmax)
                {
                    hitData->distance       = distance;
                    hitData->hitPoint       = intersectPoint;
                    hitData->primitiveIndex = face->primID;
                    hitData->barycentric    = bary;

                    hasIntersected = true;
                    callAnyHit(cont, sbtRecordOffset, payload, hitData, sceneData TEXTURE_PARAM);
                    if (*cont == false)
                        return hasIntersected;
                }
            }
        }
	}

	return hasIntersected;
}

bool intersectTop(
    __global struct AccelStruct* accelStruct, float3 origin, float3 direction,
    float Tmin, float Tmax, struct HitData* hitData, int sbtRecordOffset,
    struct Payload* payload, struct SceneData* sceneData TEXTURE_TYPE)
{
    bool hasIntersected = false;
	unsigned int stack[BVH_TOP_STACK_SIZE];     // Stack pointing to BVH node index
	int stackIdx = 0;                       // Always point to the first empty element
	stack[stackIdx++] = 0;
    bool cont = true;

	// while the stack is not empty
	while (stackIdx)
    {
		// pop a BVH node from the stack
		unsigned int nodeIdx = stack[stackIdx - 1];
		stackIdx--;

        __global struct BVHNode* nodeList = TO_BVH_NODE(accelStruct);
		__global struct BVHNode* node = nodeList + nodeIdx;

		if (!IS_LEAF(node)) // INNER NODE
        {
			// if ray intersects inner node, push indices of left and right child nodes on the stack
			if (intersectAABB(origin, direction, node->_bottom.xyz, node->_top.xyz))
            {
				stack[stackIdx++] = node->node.inner._idxRight; // right child node index
				stack[stackIdx++] = node->node.inner._idxLeft;  // left child node index
				
				// return if stack size is exceeded
				if (stackIdx > BVH_TOP_STACK_SIZE)
                {
                    printf("ERROR: Top AS stack overflow\n");
                    return false; 
                }
			}
		}
        else if (node->node.leaf._type == TYPE_INST)
        {
            __global struct Instance* instanceList = TO_INST(accelStruct);

            for (unsigned int i = 0; i < GET_COUNT(node); i++)
            {
                __global struct Instance* instance = &instanceList[node->node.leaf._startIndexList + i];
                __global struct AccelStruct* botAccelStruct = TO_BOT_AS(accelStruct, instance);

                mat4x4 transform                    = hitData->transform;
                unsigned int instanceIndex          = hitData->instanceIndex;         // Top-level instance index (gl_InstanceID)
                unsigned int instanceCustomIndex    = hitData->instanceCustomIndex;   // Top-level instance custom index (gl_InstanceCustomIndexEXT)
                unsigned int instanceSBTOffset      = hitData->instanceSBTOffset;     // VkAccelerationStructureInstanceKHR::instanceShaderBindingTableRecordOffset

                float4 rayPos = {origin.x, origin.y, origin.z, 1.0f};
                float4 rayDir = {direction.x, direction.y, direction.z, 0.0f};
                float4 localOrigin, localDir;
                mat4x4 inverse;

                Vec4ToMat4x4(instance->r0, instance->r1, instance->r2, instance->r3, &hitData->transform);
                InverseMat4x4(&hitData->transform, &inverse);
                MultiplyMat4Vec4(&inverse, &rayPos, &localOrigin);
                MultiplyMat4Vec4(&inverse, &rayDir, &localDir);

                hitData->instanceIndex       = instance->instanceID;
                hitData->instanceCustomIndex = instance->customInstanceID;
                hitData->instanceSBTOffset   = instance->SBTOffset;

                bool result = intersectBot(botAccelStruct, localOrigin.xyz, localDir.xyz, Tmin, Tmax,
                    hitData, &cont, sbtRecordOffset, payload, sceneData TEXTURE_PARAM);
                hasIntersected = hasIntersected || result;
                if (cont == false)
                    return hasIntersected;
                if (!result)
                {
                    hitData->transform = transform;
                    hitData->instanceIndex = instanceIndex;
                    hitData->instanceCustomIndex = instanceCustomIndex;
                    hitData->instanceSBTOffset = instanceSBTOffset;
                }
            }
        }
	}

	return hasIntersected;
}

// https://gist.github.com/DomNomNom/46bb1ce47f68d255fd5d
bool intersectAABB(float3 rayOrigin, float3 rayDir, float3 boxMin, float3 boxMax)
{
    float3 tMin = (boxMin - rayOrigin) / rayDir;
    float3 tMax = (boxMax - rayOrigin) / rayDir;
    float3 t1 = min(tMin, tMax);
    float3 t2 = max(tMin, tMax);
    float tNear = max(max(t1.x, t1.y), t1.z);
    float tFar = min(min(t2.x, t2.y), t2.z);

    if (tFar > max(tNear, 0.0f))
        return true;
    
    return false;
}

// https://en.wikipedia.org/wiki/M%C3%B6ller%E2%80%93Trumbore_intersection_algorithm
bool intersectTriangle(float3 origin, float3 direction, 
                       __global const struct Triangle* triangle, __global Vertex* vertexList,
                       float3* intersectPoint, float* distance, float3* bary)
{
    float3 edge1 = vertexList[triangle->idx1].xyz - vertexList[triangle->idx0].xyz;
    float3 edge2 = vertexList[triangle->idx2].xyz - vertexList[triangle->idx0].xyz;

    float3 ray_cross_e2 = cross(direction, edge2);
    float det = dot(edge1, ray_cross_e2);

    if (det == 0)
        return false;    // This ray is parallel to this triangle.

    float inv_det = 1.0f / det;
    float3 s = origin - vertexList[triangle->idx0].xyz;
    float b1 = inv_det * dot(s, ray_cross_e2);

    float3 s_cross_e1 = cross(s, edge1);
    float b2 = inv_det * dot(direction, s_cross_e1);

    // At this stage we can compute t to find out where the intersection point is on the line.
    float t = inv_det * dot(edge2, s_cross_e1);

    if (b1 < 0 || b1 > 1)
        return false;

    if (b2 < 0 || b1 + b2 > 1)
        return false;

    if (t > 0) // ray intersection
    {
        *distance = t;
        *intersectPoint = origin + direction * t;
        bary->x = 1 - b1 - b2;
        bary->y = b1;
        bary->z = b2;
        return true;
    }
    else // This means that there is a line intersection but not a ray intersection.
        return false;
}

//!raygen 
void traceRay(
    __global struct AccelStruct* topLevel,
    int sbtRecordOffset, int missIndex,
    float3 origin,
    float3 direction,
    float Tmin, float Tmax,
    struct Payload* payload,
    struct SceneData* sceneData
    TEXTURE_TYPE)
{
    struct HitData hitData;
    hitData.distance = FLT_MAX;
    if (intersectTop(topLevel, origin, direction, Tmin, Tmax, &hitData, sbtRecordOffset,
        payload, sceneData TEXTURE_PARAM))
    {
        callHit(sbtRecordOffset, payload, &hitData, sceneData TEXTURE_PARAM);
    }
    else
    {
        callMiss(missIndex, payload, sceneData TEXTURE_PARAM);
    }
}

/***********************************************************************************
// case @<index>:@<funct>(payload, &hitData, sceneData);break;
void callHit(int sbtRecordOffset, struct Payload* payload, struct HitData* hitData, struct SceneData* sceneData)
{
    int index = hitData->instanceSBTOffset + sbtRecordOffset;
    switch (index)
    {
        @<insert>
        default: printf("Error: No hit shader found.");
    }
}



// case @<index>:@<funct>(payload, sceneData);break;
void callMiss(int missIndex, struct Payload* ray, struct SceneData* sceneData)
{
    switch (missIndex)
    {
         @<insert>
         default: printf("Error: No miss shader found.");
    }
}
***********************************************************************************************/