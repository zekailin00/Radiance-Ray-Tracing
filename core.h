#pragma once

#include <assimp/Importer.hpp>      // C++ importer interface
#include <assimp/scene.h>           // Output data structure
#include <assimp/postprocess.h>     // Post processing flags


struct Triangle {

    unsigned int index;

    // bounding box
	float _bottom[3];
	float _top[3];

    // indexes in vertices array
	unsigned _idx0;
	unsigned _idx1;
	unsigned _idx2;

    aiVector3f v0;
    aiVector3f v1;
    aiVector3f v2;

    aiVector3f _normal;

	// // RGB Color Vector3Df 
	// Vector3Df _colorf;
	// // Center point
	// Vector3Df _center;
	// // triangle normal
	// Vector3Df _normal;
	// // ignore back-face culling flag
	// bool _twoSided;
	// // Raytracing intersection pre-computed cache:
	// float _d, _d1, _d2, _d3;
	// Vector3Df _e1, _e2, _e3;
};

struct AccelStruct // mapped
{
    unsigned int nodeByteOffset;
    unsigned int faceByteOffset;
    unsigned int faceRefByteOffset;
    unsigned int _; // alignment
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
		} inner;
		// leaf node: stores triangle count and starting index in triangle list
		struct {
			unsigned _count; // Top-most bit set, leafnode if set, innernode otherwise
			unsigned _startIndexInTriIndexList;
		} leaf;
	} node;

    unsigned int _2, _3;
};


struct DeviceTriangle // mapped
{
    // FIXME: use indices for optimization
    // // indexes in vertices array
	// unsigned _idx0;
	// unsigned _idx1;
	// unsigned _idx2;

    aiVector3f v0;
    float _0;
    aiVector3f v1;
    float _1;
    aiVector3f v2;
    float _2;
};
