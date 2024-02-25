#pragma once

#include <assimp/Importer.hpp>      // C++ importer interface
#include <assimp/scene.h>           // Output data structure
#include <assimp/postprocess.h>     // Post processing flags

#include <list>
#include <vector>


namespace RD
{

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

} // namespace RD
