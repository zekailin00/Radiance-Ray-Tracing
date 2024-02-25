#pragma once
#include "core.h"


namespace RD
{

#define MAX_LEAF_PRIM_SIZE 4

struct BVHNode
{
	aiVector3f _bottom;
	aiVector3f _top;
	virtual bool IsLeaf() = 0; // pure virtual
};

struct BVHInner: BVHNode
{
	BVHNode *_left;
	BVHNode *_right;
	virtual bool IsLeaf() { return false; }
};

struct BVHLeaf: BVHNode
{
	std::list<const Triangle*> _triangles;
	virtual bool IsLeaf() { return true; }
};

BVHNode *CreateBVH(const std::vector<aiVector3f>& vertices, const std::vector<Triangle>& triangles);

void CreateDeviceBVH(BVHNode* root, const std::vector<Triangle>& faces,
    std::vector<unsigned int>& faceList, std::vector<DeviceBVHNode>& nodeList);

} // namespace RD
