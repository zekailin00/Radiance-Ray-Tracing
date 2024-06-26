#pragma once

#include <assimp/Importer.hpp>      // C++ importer interface
#include <assimp/scene.h>           // Output data structure
#include <assimp/postprocess.h>     // Post processing flags

#include <list>
#include <vector>


namespace RD
{

typedef aiVector2t<float> Vec2;
typedef aiVector3f Vec3;
typedef aiMatrix4x4 Mat4x4;

struct Triangle
{
	unsigned int idx0;
	unsigned int idx1;
	unsigned int idx2;
};

struct AccelStructHeader // mapped
{
    unsigned int nodeByteOffset;
    unsigned int faceByteOffset;
    unsigned int faceRefByteOffset;
    unsigned int _; // alignment
};


struct AccelStructTop // 1 block mapped
{
    unsigned int type;
    unsigned int nodeByteOffset;
    unsigned int instByteOffset;
    unsigned int totalBufferSize;
};

struct AccelStructBottom // 1 block mapped
{
    unsigned int type;
    unsigned int nodeByteOffset;
    unsigned int faceByteOffset;
    unsigned int vertexOffset;
};

struct DeviceInstance
{
    Mat4x4 transform;
    unsigned int SBTOffset;
    unsigned int instanceID;
    unsigned int customInstanceID;
    unsigned int bottomAccelStructOffset;
};

struct DeviceBVHNode // mapped
{
	// bounding box
	aiVector3f _bottom;
    float _0;
	aiVector3f _top;
    float _1;

	// parameters for leafnodes and innernodes occupy same space (union) to save memory
	// top bit discriminates between leafnode and innernode
	// no pointers, but indices (int): faster

	union {
		// inner node - stores indexes to array of CacheFriendlyBVHNode
		struct {
			unsigned _idxLeft;
			unsigned _idxRight;
            unsigned int _2, _3;
		} inner;
		// leaf node: stores triangle count and starting index in triangle list
		struct {
			unsigned _count; // Top-most bit set, leafnode if set, innernode otherwise
			unsigned _startIndexList;
            unsigned int _type;
            unsigned int _3;
		} leaf;

	} node;
};


struct DeviceTriangle // mapped
{
	unsigned int idx0;
	unsigned int idx1;
	unsigned int idx2;
    unsigned int primID;
};

struct DeviceVertex // mapped
{
    float x, y, z, w;
};

struct RayTraceProperties
{
    unsigned int totalSamples;
    unsigned int batchSize;
    unsigned int depth;
    unsigned int debug;
};

struct Material
{
    float albedo[4];

    float metallic;
    float roughness;
    float transmission;
    float ior;

    // -1 := not used
    int albedoTexIdx;
    int metallicTexIdx;
    int roughnessTexIdx;
    int normalTexIdx;
};

struct MeshInfo
{
    // -1 := not used
    int vertexOffset;
    int indexOffset;
    int uvOffset;   
    int normalOffset;

    int materialIndex;
    int _0, _1, _2;
};

struct DirLight
{
    float direction[4];
    float color[4];
};

struct SceneProperties
{
    uint lightCount[4]; // only 1st is used
    struct DirLight lights[5];
};

struct PhysicalCamera
{
    float widthPixel, heightPixel;  // integer pixel count; e.g. [1920.0f, 1080.0f]
    float focalLength, sensorWidth; // in meter; controls fov; e.g. 0.0025m = 25mm
    float focalDistance, fStop;     // in meter, depth of view; F/N = aperture diameter
    float x, y, z;                  // camera position in meter
    float wx, wy, wz;               // camera rotation in degree
};

} // namespace RD
