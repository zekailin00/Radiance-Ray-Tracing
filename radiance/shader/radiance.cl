
struct Payload;

struct AccelStruct
{
    unsigned int nodeByteOffset;
    unsigned int faceByteOffset;
    unsigned int faceRefByteOffset;
    unsigned int _; // alignment
};

struct BVHNode
{
   	float4 _bottom;
	float4 _top;

	union {
		// inner node - stores indexes to children
		struct {
			unsigned int _idxLeft;
			unsigned int _idxRight;
            unsigned int _2, _3; // alignment
		} inner;

		// leaf node: stores face count and references
		struct {
			unsigned int _count; // Top-most bit set, leafnode if set, innernode otherwise
			unsigned int _startIndexFaceRefList;
            unsigned int _2, _3; // alignment
		} leaf;
	} node;
};

struct Triangle
{
    // FIXME: use indices for optimization
    // // indexes in vertices array
	// unsigned _idx0;
	// unsigned _idx1;
	// unsigned _idx2;

    float4 v0;// v0.xyz is vertex; v0.w is not used
    float4 v1;
    float4 v2;
};

struct HitData
{
    float3 hitPoint;
    float3 normal;
    unsigned int primitiveIndex;        // Bottom-level triangle index (gl_PrimitiveID)
    unsigned int instanceIndex;         // Top-level instance index (gl_InstanceID)
    unsigned int instanceCustomIndex;   // Top-level instance custom index (gl_InstanceCustomIndexEXT)
};

/* User defined begin */
struct Payload;
void hit (struct Payload* payload, struct HitData* hitData);
void miss(struct Payload* ray);
/* User defined end */


bool intersectTriangle(float3 origin, float3 direction, 
                       const struct Triangle* triangle,
                       float3* intersectPoint, float* distance);
bool intersectAABB(float3 rayOrigin, float3 rayDir, float3 boxMin, float3 boxMax);

#define TO_BVH_NODE(accelStruct) (struct BVHNode*)(((char*)accelStruct) + accelStruct->nodeByteOffset)
#define TO_FACE_REF(accelStruct) (unsigned int*)(((char*)accelStruct) + accelStruct->faceRefByteOffset)
#define TO_FACE(accelStruct) (struct Triangle*)(((char*)accelStruct) + accelStruct->faceByteOffset)
#define IS_LEAF(BVHNode) (BVHNode->node.leaf._count & 0x80000000)
#define GET_COUNT(BVHNode) (BVHNode->node.leaf._count & 0x7fffffff)
#define BVH_STACK_SIZE 128

bool intersect(
    __global struct AccelStruct* topLevel,
    float3 origin, float3 direction,
    float Tmin, float Tmax, struct HitData* hitData)
{
    // return false;
	// Closest triangle hit
	int bestFaceIndex = -1;
	float bestFaceDist = FLT_MAX;
    float3 hitPoint;

    struct BVHNode* nodeList  = TO_BVH_NODE(topLevel);
    unsigned int* faceRefList = TO_FACE_REF(topLevel);
    struct Triangle* faceList = TO_FACE(topLevel);


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
					return false; 
				
			}
		}
		else // LEAF NODE
        {
            unsigned int beginIdx = node->node.leaf._startIndexFaceRefList;
            unsigned int endIdx = beginIdx + GET_COUNT(node);

			// loop over every triangle in the leaf node
			for (unsigned i = beginIdx; i < endIdx; i++)
            {
				unsigned int faceIdx = faceRefList[i];
                struct Triangle* face = faceList + faceIdx;

                float3 intersectPoint;
                float distance;

                if (intersectTriangle(origin, direction, face, &intersectPoint, &distance))
                {
                    if (distance < bestFaceDist)
                    {
                        // maintain the closest hit
                        bestFaceIndex = (int)faceIdx;
                        bestFaceDist = distance;
                        hitPoint = intersectPoint;
                        
                        // store barycentric coordinates (for texturing, not used for now)
                    }
                }
			}
		}
	}

    if (bestFaceIndex != -1)
    {
        struct Triangle* face = faceList + bestFaceIndex;
        hitData->normal = (normalize(cross(face->v1.xyz - face->v0.xyz, face->v2.xyz - face->v0.xyz)));
    }

    hitData->hitPoint = hitPoint;
    hitData->primitiveIndex = bestFaceIndex;
	return bestFaceIndex != -1;
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
                       const struct Triangle* triangle,
                       float3* intersectPoint, float* distance)
{
    float3 edge1 = triangle->v1.xyz - triangle->v0.xyz;
    float3 edge2 = triangle->v2.xyz - triangle->v0.xyz;

    float3 ray_cross_e2 = cross(direction, edge2);
    float det = dot(edge1, ray_cross_e2);

    if (det > -FLT_EPSILON && det < FLT_EPSILON)
        return false;    // This ray is parallel to this triangle.

    float inv_det = 1.0 / det;
    float3 s = origin - triangle->v0.xyz;
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
    if (intersect(topLevel, origin, direction, Tmin, Tmax, &hitData))
    {
        hit(payload, &hitData);
    }
    else
    {
        miss(payload);
    }
}