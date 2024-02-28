
#include "data.cl"//////////////////////////////////////////////////////////////////////


struct Payload;

struct HitData
{
    float3 hitPoint;
    float distance;
    unsigned int primitiveIndex;        // Bottom-level triangle index (gl_PrimitiveID)
    unsigned int instanceIndex;         // Top-level instance index (gl_InstanceID)
    unsigned int instanceCustomIndex;   // Top-level instance custom index (gl_InstanceCustomIndexEXT)

    //tmp
    struct Triangle* face;
};

/* User defined begin */
struct Payload;
void hit (struct Payload* payload, struct HitData* hitData);
void miss(struct Payload* ray);
/* User defined end */


bool intersectTriangle(float3 origin, float3 direction, 
                       const struct Triangle* triangle, Vertex* vertexList,
                       float3* intersectPoint, float* distance);
bool intersectAABB(float3 rayOrigin, float3 rayDir, float3 boxMin, float3 boxMax);


#define BVH_STACK_SIZE 64

bool intersect(
    struct AccelStruct* accelStruct,
    float3 origin, float3 direction,
    float Tmin, float Tmax, struct HitData* hitData, int depth)
{
	// Closest hit data
    float bestFaceDist = FLT_MAX;

    if (depth > 2)
    {
        printf("Interset depth:%d\n", depth);
        return false;
    }

    // Stack pointing to BVH node index
	unsigned int stack[BVH_STACK_SIZE];
	int stackIdx = 0; // Always point to the first empty element
	stack[stackIdx++] = 0;

	// while the stack is not empty
	while (stackIdx)
    {
		// pop a BVH node from the stack
		unsigned int nodeIdx = stack[stackIdx - 1];
		stackIdx--;

        struct BVHNode* nodeList = TO_BVH_NODE(accelStruct);
		struct BVHNode* node = nodeList + nodeIdx;

		if (!IS_LEAF(node)) // INNER NODE
        {
			// if ray intersects inner node, push indices of left and right child nodes on the stack
			if (intersectAABB(origin, direction, node->_bottom.xyz, node->_top.xyz))
            {
				stack[stackIdx++] = node->node.inner._idxRight; // right child node index
				stack[stackIdx++] = node->node.inner._idxLeft;  // left child node index
				
				// return if stack size is exceeded
				if (stackIdx > BVH_STACK_SIZE)
                {
                    printf("ERROR: stack overflow\n");
                    return false; 
                }
			}
		}
		else // LEAF NODE
        {
            if (node->node.leaf._type == TYPE_INST)
            {
                struct Instance* instanceList = TO_INST(accelStruct);

                for (unsigned int i = 0; i < GET_COUNT(node); i++)
                {
                    struct Instance* instance = &instanceList[node->node.leaf._startIndexList + i];
                    struct AccelStruct* botAccelStruct = TO_BOT_AS(accelStruct, instance);

                    // TODO: transform ray
                    float3 position = {instance->r0.w, instance->r1.w, instance->r2.w};
                    float3 localOrigin = origin - position;
                    float3 localDir = direction;

                    struct HitData localHitData;
                    if (intersect(botAccelStruct, localOrigin, localDir, Tmin, Tmax, &localHitData, depth + 1))
                    {
                        if (localHitData.distance < bestFaceDist)
                        {
                            // maintain the closest hit
                            bestFaceDist = localHitData.distance;

                            hitData->hitPoint = localHitData.hitPoint;
                            hitData->face = localHitData.face;
                            hitData->distance = localHitData.distance;
                            hitData->primitiveIndex = localHitData.face->primID;
                            
                            hitData->instanceIndex = instance->instanceID;
                            hitData->instanceCustomIndex = instance->customInstanceID;
                            
                            // store barycentric coordinates (for texturing, not used for now)
                        }
                    }
                }
            }
            else
            {
                Vertex* vertexList = TO_VERTEX(accelStruct);
                struct Triangle* faceList = TO_FACE(accelStruct);

                // loop over every triangle in the leaf node
                for (unsigned int i = 0; i < GET_COUNT(node); i++)
                {
                    struct Triangle* face = &faceList[node->node.leaf._startIndexList + i];

                    float3 intersectPoint;
                    float distance;
                    if (intersectTriangle(origin, direction, face, vertexList, &intersectPoint, &distance))
                    {
                        if (distance < bestFaceDist)
                        {
                            // maintain the closest hit
                            bestFaceDist = distance;

                            hitData->face = face;
                            hitData->distance = distance;
                            hitData->hitPoint = intersectPoint;
                            hitData->primitiveIndex = face->primID;
                            
                            // store barycentric coordinates (for texturing, not used for now)
                        }
                    }
                }
            }
		}
	}

	return bestFaceDist < FLT_MAX;
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
                       const struct Triangle* triangle, Vertex* vertexList,
                       float3* intersectPoint, float* distance)
{
    float3 edge1 = vertexList[triangle->idx1].xyz - vertexList[triangle->idx0].xyz;
    float3 edge2 = vertexList[triangle->idx2].xyz - vertexList[triangle->idx0].xyz;

    float3 ray_cross_e2 = cross(direction, edge2);
    float det = dot(edge1, ray_cross_e2);

    if (det > -FLT_EPSILON && det < FLT_EPSILON)
        return false;    // This ray is parallel to this triangle.

    float inv_det = 1.0 / det;
    float3 s = origin - vertexList[triangle->idx0].xyz;
    float u = inv_det * dot(s, ray_cross_e2);

    float3 s_cross_e1 = cross(s, edge1);
    float v = inv_det * dot(direction, s_cross_e1);

    // At this stage we can compute t to find out where the intersection point is on the line.
    float t = inv_det * dot(edge2, s_cross_e1);


    if (u < 0 || u > 1)
        return false;

    if (v < 0 || u + v > 1)
        return false;

    if (t > FLT_EPSILON) // ray intersection
    {
        *distance = t;
        *intersectPoint = origin + direction * t;
        return true;
    }
    else // This means that there is a line intersection but not a ray intersection.
        return false;
}

//!raygen 
void traceRay(
    __global struct AccelStruct* topLevel,
    float3 origin,
    float3 direction,
    float Tmin, float Tmax,
    struct Payload* payload)
{
    struct HitData hitData;
    if (intersect(topLevel, origin, direction, Tmin, Tmax, &hitData, 1))
    {
        hit(payload, &hitData);
    }
    else
    {
        miss(payload);
    }
}