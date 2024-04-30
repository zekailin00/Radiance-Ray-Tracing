#pragma once
#include "radiance.h"

#include <map>

namespace RD
{

#define MAX_LEAF_PRIM_SIZE 8

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
	std::list<const void*> _primitive;
	virtual bool IsLeaf() { return true; }
};

#define TYPE_INST 1
#define TYPE_TRIG 2

#define TYPE_TOP_AS 1
#define TYPE_BOT_AS 2

BVHNode *CreateBVH(const std::vector<aiVector3f>& vertices, const std::vector<Triangle>& triangles);
BVHNode *CreateBVH(const std::vector<Instance>& instances);

void CreateDeviceBVH(BVHNode* root, const std::vector<Triangle>& faces,
    std::vector<DeviceTriangle>& faceList, std::vector<DeviceBVHNode>& nodeList);
void CreateDeviceBVH(BVHNode* root, const std::vector<Instance>& faces,
    std::vector<DeviceInstance>& faceList, std::vector<DeviceBVHNode>& nodeList,
    std::map<BottomAccelStruct, unsigned int>& instOffsetList);

} // namespace RD
