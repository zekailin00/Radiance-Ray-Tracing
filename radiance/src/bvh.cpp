#include "bvh.h"

#include <cfloat>
#include <cassert>

#include "linalg.h"

namespace RD
{
//https://github.com/straaljager/GPU-path-tracing-with-CUDA-tutorial-3

// report progress during BVH construction
#define PROGRESS_REPORT
#ifdef PROGRESS_REPORT
#define REPORT(x) x
#define REPORTPRM(x) x,
#else
#define REPORT(x)
#define REPORTPRM(x)
#endif
unsigned g_reportCounter = 0;


struct BBoxTmp
{
    // Bottom point (ie minx,miny,minz)
    aiVector3f _bottom;
    // Top point (ie maxx,maxy,maxz)
    aiVector3f _top;
    // Center point, ie 0.5*(top-bottom)
    aiVector3f _center; // = bbox centroid

    const void* _ptr;
    BBoxTmp()
        :
        _bottom(FLT_MAX, FLT_MAX, FLT_MAX),
        _top(-FLT_MAX, -FLT_MAX, -FLT_MAX),
        _ptr(NULL)
    {}
};

// vector of triangle bounding boxes needed during BVH construction
typedef std::vector<BBoxTmp> BBoxEntries;


BVHNode *Recurse(BBoxEntries& work, REPORTPRM(float pct = 0.) int depth = 0)
{

	REPORT(float pctSpan = 11. / pow(3.f, depth);)

	// terminate recursion case: 
	// if work set has less then 4 elements (triangle bounding boxes), create a leaf node 
	// and create a list of the triangles contained in the node
		
	if (work.size() < MAX_LEAF_PRIM_SIZE) {
			
		BVHLeaf *leaf = new BVHLeaf;
		for (BBoxEntries::iterator it = work.begin(); it != work.end(); it++)
			leaf->_primitive.push_back(it->_ptr);
		return leaf;
		}

	// else, work size > 4, divide  node further into smaller nodes
	// start by finding the working list's bounding box (top and bottom)

	aiVector3f bottom(FLT_MAX, FLT_MAX, FLT_MAX);
	aiVector3f top(-FLT_MAX, -FLT_MAX, -FLT_MAX);

	// loop over all bboxes in current working list, expanding/growing the working list bbox
	for (unsigned i = 0; i < work.size(); i++) {  // meer dan 4 bboxen in work
		BBoxTmp& v = work[i];   
		minVec3(bottom, bottom, v._bottom);
		maxVec3(top, top, v._top);
	}

	// SAH, surface area heuristic calculation
	// find surface area of bounding box by multiplying the dimensions of the working list's bounding box
	float side1 = top.x - bottom.x;  // length bbox along X-axis
	float side2 = top.y - bottom.y;  // length bbox along Y-axis
	float side3 = top.z - bottom.z;  // length bbox along Z-axis

	// the current bbox has a cost of (number of triangles) * surfaceArea of C = N * SA
	float minCost = work.size() * (side1*side2 + side2*side3 + side3*side1);

	float bestSplit = FLT_MAX; // best split along axis, will indicate no split with better cost found (below)

	int bestAxis = -1;

	// Try all 3 axises X, Y, Z
	for (int j = 0; j < 3; j++) {  // 0 = X, 1 = Y, 2 = Z axis

		int axis = j;

		// we will try dividing the triangles based on the current axis,
		// and we will try split values from "start" to "stop", one "step" at a time.
		float start, stop, step;

		// X-axis
		if (axis == 0) {
			start = bottom.x;
			stop = top.x;
		}
		// Y-axis
		else if (axis == 1) {
			start = bottom.y;
			stop = top.y;
		}
		// Z-axis
		else {
			start = bottom.z;
			stop = top.z;
		}

		// In that axis, do the bounding boxes in the work queue "span" across, (meaning distributed over a reasonable distance)?
		// Or are they all already "packed" on the axis? Meaning that they are too close to each other
		if (fabsf(stop - start)<1e-4)
			// BBox side along this axis too short, we must move to a different axis!
			continue; // go to next axis

		// Binning: Try splitting at a uniform sampling (at equidistantly spaced planes) that gets smaller the deeper we go:
		// size of "sampling grid": 1024 (depth 0), 512 (depth 1), etc
		// each bin has size "step"
		step = (stop - start) / (1024. / (depth + 1.));

#ifdef PROGRESS_REPORT
		// Progress report variables...
		float pctStart = pct + j*pctSpan;  // j is axis
		float pctStep = pctSpan / ((stop - start - 2 * step) / step);
#endif

		// for each bin (equally spaced bins of size "step"):
		for (float testSplit = start + step; testSplit < stop - step; testSplit += step) {

#ifdef PROGRESS_REPORT
			if ((1023 & g_reportCounter++) == 0) {
				std::printf("\b\b\b%02d%%", int(pctStart)); fflush(stdout);
			}
			pctStart += pctStep;
#endif

			// Create left and right bounding box
			aiVector3f lbottom(FLT_MAX, FLT_MAX, FLT_MAX);
			aiVector3f ltop(-FLT_MAX, -FLT_MAX, -FLT_MAX);

			aiVector3f rbottom(FLT_MAX, FLT_MAX, FLT_MAX);
			aiVector3f rtop(-FLT_MAX, -FLT_MAX, -FLT_MAX);

			// The number of triangles in the left and right bboxes (needed to calculate SAH cost function)
			int countLeft = 0, countRight = 0;

			// For each test split (or bin), allocate triangles in remaining work list based on their bbox centers
			// this is a fast O(N) pass, no triangle sorting needed (yet)
			for (unsigned i = 0; i<work.size(); i++) {

				BBoxTmp& v = work[i];

				// compute bbox center
				float value;
				if (axis == 0) value = v._center.x;       // X-axis
				else if (axis == 1) value = v._center.y;  // Y-axis
				else value = v._center.z;			   // Z-axis

				if (value < testSplit) { 
					// if center is smaller then testSplit value, put triangle in Left bbox
					minVec3(lbottom, lbottom, v._bottom);
					maxVec3(ltop, ltop, v._top);
					countLeft++;
				}
				else {
					// else put triangle in right bbox
					minVec3(rbottom, rbottom, v._bottom);
					maxVec3(rtop, rtop, v._top);
					countRight++;
				}
			}

			// Now use the Surface Area Heuristic to see if this split has a better "cost"

			// First, check for stupid partitionings, ie bins with 0 or 1 triangles make no sense
			if (countLeft <= 1 || countRight <= 1) continue;

			// It's a real partitioning, calculate the surface areas
			float lside1 = ltop.x - lbottom.x;
			float lside2 = ltop.y - lbottom.y;
			float lside3 = ltop.z - lbottom.z;

			float rside1 = rtop.x - rbottom.x;
			float rside2 = rtop.y - rbottom.y;
			float rside3 = rtop.z - rbottom.z;

			// calculate SurfaceArea of Left and Right BBox
			float surfaceLeft = lside1*lside2 + lside2*lside3 + lside3*lside1;
			float surfaceRight = rside1*rside2 + rside2*rside3 + rside3*rside1;

			// calculate total cost by multiplying left and right bbox by number of triangles in each
			float totalCost = surfaceLeft*countLeft + surfaceRight*countRight;

			// keep track of cheapest split found so far
			if (totalCost < minCost) {
				minCost = totalCost;
				bestSplit = testSplit;
				bestAxis = axis;
			}
		} // end of loop over all bins
	} // end of loop over all axises
	
	// at the end of this loop (which runs for every "bin" or "sample location"), 
	// we should have the best splitting plane, best splitting axis and bboxes with minimal traversal cost

	// If we found no split to improve the cost, create a BVH leaf

	if (bestAxis == -1) {

		BVHLeaf *leaf = new BVHLeaf;
		for (BBoxEntries::iterator it = work.begin(); it != work.end(); it++)
			leaf->_primitive.push_back(it->_ptr); // put triangles of working list in leaf's triangle list
		return leaf;
	}

	// Otherwise, create BVH inner node with L and R child nodes, split with the optimal value we found above

	BBoxEntries left;
	BBoxEntries right;  // BBoxEntries is a vector/list of BBoxTmp 
	aiVector3f lbottom(FLT_MAX, FLT_MAX, FLT_MAX);
	aiVector3f ltop(-FLT_MAX, -FLT_MAX, -FLT_MAX);
	aiVector3f rbottom(FLT_MAX, FLT_MAX, FLT_MAX);
	aiVector3f rtop(-FLT_MAX, -FLT_MAX, -FLT_MAX);
	
	// distribute the triangles in the left or right child nodes
	// for each triangle in the work set
	for (int i = 0; i < (int)work.size(); i++) {

		// create temporary bbox for triangle
		BBoxTmp& v = work[i];

		// compute bbox center 
		float value;
		if (bestAxis == 0) value = v._center.x;
		else if (bestAxis == 1) value = v._center.y;
		else value = v._center.z;

		if (value < bestSplit) { // add temporary bbox v from work list to left BBoxentries list, 
			// becomes new working list of triangles in next step

			left.push_back(v);
			minVec3(lbottom, lbottom, v._bottom);
			maxVec3(ltop, ltop, v._top);
		}
		else {

			// Add triangle bbox v from working list to right BBoxentries, 
			// becomes new working list of triangles in next step  
			right.push_back(v);
			minVec3(rbottom, rbottom, v._bottom);
			maxVec3(rtop, rtop, v._top);
		}
	} // end loop for each triangle in working set

	// create inner node
	BVHInner *inner = new BVHInner;

#ifdef PROGRESS_REPORT
	if ((1023 & g_reportCounter++) == 0) {
		std::printf("\b\b\b%2d%%", int(pct + 3.f*pctSpan)); // Update progress indicator
		fflush(stdout);
	}
#endif
	// recursively build the left child
	inner->_left = Recurse(left, REPORTPRM(pct + 3.f*pctSpan) depth + 1);
	inner->_left->_bottom = lbottom;
	inner->_left->_top = ltop;

#ifdef PROGRESS_REPORT
	if ((1023 & g_reportCounter++) == 0) {
		std::printf("\b\b\b%2d%%", int(pct + 6.f*pctSpan)); // Update progress indicator
		fflush(stdout);
	}
#endif
	// recursively build the right child
	inner->_right = Recurse(right, REPORTPRM(pct + 6.f*pctSpan) depth + 1);
	inner->_right->_bottom = rbottom;
	inner->_right->_top = rtop;

	return inner;
}  // end of Recurse() function, returns the rootnode (when all recursion calls have finished)


BVHNode *CreateBVH(const std::vector<aiVector3f>& vertices, const std::vector<Triangle>& triangles)
{
	/* Summary:
	1. Create work BBox
	2. Create BBox for every triangle and compute bounds
	3. Expand bounds work BBox to fit all triangle bboxes
	4. Compute triangle bbox centre and add triangle to working list
	5. Build BVH tree with Recurse()
	6. Return root node
	*/

	std::vector<BBoxTmp> work;
	aiVector3f bottom(FLT_MAX, FLT_MAX, FLT_MAX);
	aiVector3f top(-FLT_MAX, -FLT_MAX, -FLT_MAX);

	puts("Gathering bounding box info from all triangles...");
	// for each triangle
	for (unsigned j = 0; j < triangles.size(); j++) {

		const Triangle& triangle = triangles[j];

		// create a new temporary bbox per triangle 
		BBoxTmp b;
		b._ptr = &triangle;  

		// loop over triangle vertices and pick smallest vertex for bottom of triangle bbox
		minVec3(b._bottom, b._bottom, vertices[triangle.idx0]);  // index of vertex
		minVec3(b._bottom, b._bottom, vertices[triangle.idx1]);
		minVec3(b._bottom, b._bottom, vertices[triangle.idx2]);

		// loop over triangle vertices and pick largest vertex for top of triangle bbox
		maxVec3(b._top, b._top, vertices[triangle.idx0]);
		maxVec3(b._top, b._top, vertices[triangle.idx1]);
		maxVec3(b._top, b._top, vertices[triangle.idx2]);

		// expand working list bbox by largest and smallest triangle bbox bounds
		minVec3(bottom, bottom, b._bottom);
		maxVec3(top, top, b._top);

		// compute triangle bbox center: (bbox top + bbox bottom) * 0.5
		b._center = (b._top + b._bottom) * 0.5f;

		// add triangle bbox to working list
		work.push_back(b);
	}

	// ...and pass it to the recursive function that creates the SAH AABB BVH
	// (Surface Area Heuristic, Axis-Aligned Bounding Boxes, Bounding Volume Hierarchy)
	
	std::printf("Creating Bounding Volume Hierarchy data...    "); fflush(stdout);
	BVHNode* root = Recurse(work); // builds BVH and returns root node
	printf("\b\b\b100%%\n");

	root->_bottom = bottom; // bottom is bottom of bbox bounding all triangles in the scene
	root->_top = top;

	return root;
}

BVHNode *CreateBVH(const std::vector<Instance>& instances)
{
	/* Summary:
	1. Create work BBox
	2. Create BBox for every triangle and compute bounds
	3. Expand bounds work BBox to fit all triangle bboxes
	4. Compute triangle bbox centre and add triangle to working list
	5. Build BVH tree with Recurse()
	6. Return root node
	*/

	std::vector<BBoxTmp> work;
	aiVector3f bottom(FLT_MAX, FLT_MAX, FLT_MAX);
	aiVector3f top(-FLT_MAX, -FLT_MAX, -FLT_MAX);

	puts("Gathering bounding box info from all triangles...");

    for (const Instance& inst: instances)
    {
        std::vector<char>& meshData = inst.bottomAccelStruct->data;

        AccelStructBottom* header = (AccelStructBottom*) meshData.data();
        DeviceBVHNode* root = (DeviceBVHNode*) (meshData.data() + header->nodeByteOffset);
        
        BBoxTmp b;
        b._top = root->_top;
        b._bottom = root->_bottom;
        b._ptr = &inst;

        Mat4x4 vi0 {
            b._top.x,    b._bottom.x, b._top.x,    b._bottom.x,   
            b._top.y,    b._top.y,    b._bottom.y, b._bottom.y,
            b._top.z,    b._top.z,    b._top.z,    b._top.z,
            1,           1,           1,           1     
        };
        Mat4x4 vi1 {
            b._top.x,    b._bottom.x, b._top.x,    b._bottom.x,   
            b._top.y,    b._top.y,    b._bottom.y, b._bottom.y,
            b._bottom.z, b._bottom.z, b._bottom.z, b._bottom.z,
            1,           1,           1,           1     
        };
        Mat4x4 vf0 = inst.transform * vi0;
        Mat4x4 vf1 = inst.transform * vi1;

        // loop over triangle vertices and pick smallest vertex for bottom of triangle bbox
        aiVector3f tmp0, tmp1, tmp2, tmp3, tmp4, tmp5;
		minVec3(tmp0, {vi0.a2, vi0.b2, vi0.c2}, {vi0.a1, vi0.b1, vi0.c1});
		minVec3(tmp1, {vi0.a4, vi0.b4, vi0.c4}, {vi0.a3, vi0.b3, vi0.c3});
        minVec3(tmp2, {vi1.a2, vi1.b2, vi1.c2}, {vi1.a1, vi1.b1, vi1.c1});
		minVec3(tmp3, {vi1.a4, vi1.b4, vi1.c4}, {vi1.a3, vi1.b3, vi1.c3});
        minVec3(tmp4, tmp1, tmp0);
		minVec3(tmp5, tmp3, tmp2);
        minVec3(b._bottom, tmp4, tmp5);
		
        maxVec3(tmp0, {vi0.a2, vi0.b2, vi0.c2}, {vi0.a1, vi0.b1, vi0.c1});
		maxVec3(tmp1, {vi0.a4, vi0.b4, vi0.c4}, {vi0.a3, vi0.b3, vi0.c3});
        maxVec3(tmp2, {vi1.a2, vi1.b2, vi1.c2}, {vi1.a1, vi1.b1, vi1.c1});
		maxVec3(tmp3, {vi1.a4, vi1.b4, vi1.c4}, {vi1.a3, vi1.b3, vi1.c3});
        maxVec3(tmp4, tmp1, tmp0);
		maxVec3(tmp5, tmp3, tmp2);
        maxVec3(b._top, tmp4, tmp5);

        b._center = (b._top + b._bottom) * 0.5f;
    
        minVec3(bottom, bottom, b._bottom);
        maxVec3(top, top, b._top);
        
        work.push_back(b);
    }

	// ...and pass it to the recursive function that creates the SAH AABB BVH
	// (Surface Area Heuristic, Axis-Aligned Bounding Boxes, Bounding Volume Hierarchy)
	
	std::printf("Creating Bounding Volume Hierarchy data...    "); fflush(stdout);
	BVHNode* root = Recurse(work); // builds BVH and returns root node
	printf("\b\b\b100%%\n");

	root->_bottom = bottom; // bottom is bottom of bbox bounding all triangles in the scene
	root->_top = top;

	return root;
}


// the following functions are required to create the cache-friendly BVH

// recursively count bboxes
int CountBoxes(BVHNode *root)
{
	if (!root->IsLeaf()) {
		BVHInner *p = dynamic_cast<BVHInner*>(root);
		return 1 + CountBoxes(p->_left) + CountBoxes(p->_right);
	}
	else
		return 1;
}

// recursively count triangles
unsigned CountTriangles(BVHNode *root)
{
	if (!root->IsLeaf()) {
		BVHInner *p = dynamic_cast<BVHInner*>(root);
		return CountTriangles(p->_left) + CountTriangles(p->_right);
	}
	else {
		BVHLeaf *p = dynamic_cast<BVHLeaf*>(root);
		return (unsigned)p->_primitive.size();
	}
}

// recursively count depth
void CountDepth(BVHNode *root, int depth, int& maxDepth)
{
	if (maxDepth<depth)
		maxDepth = depth;
	if (!root->IsLeaf()) {
		BVHInner *p = dynamic_cast<BVHInner*>(root);
		CountDepth(p->_left, depth + 1, maxDepth);
		CountDepth(p->_right, depth + 1, maxDepth);
	}
}

// Writes in the BVH nodes and face references into arrays.
// Create a device side BVH
void PopulateCacheFriendlyBVH(
	const Triangle *pFirstTriangle, BVHNode *root, unsigned int& faceIdx, unsigned int& nodeIdx,
    std::vector<DeviceTriangle>& faceList, std::vector<DeviceBVHNode>& nodeList)
{
	unsigned currNodeIdx = nodeIdx;
	nodeList[currNodeIdx]._bottom = root->_bottom;
	nodeList[currNodeIdx]._top = root->_top;

	//DEPTH FIRST APPROACH (left first until complete)
	if (!root->IsLeaf()) { // inner node
		BVHInner *p = dynamic_cast<BVHInner*>(root);
		// recursively populate left and right
		int idxLeft = ++nodeIdx;
		PopulateCacheFriendlyBVH(pFirstTriangle, p->_left, faceIdx, nodeIdx, faceList, nodeList);
		int idxRight = ++nodeIdx;
		PopulateCacheFriendlyBVH(pFirstTriangle, p->_right, faceIdx, nodeIdx, faceList, nodeList);
		nodeList[currNodeIdx].node.inner._idxLeft = idxLeft;
		nodeList[currNodeIdx].node.inner._idxRight = idxRight;
	}

	else { // leaf
		BVHLeaf *p = dynamic_cast<BVHLeaf*>(root);
		unsigned count = p->_primitive.size();
		nodeList[currNodeIdx].node.leaf._count = 0x80000000 | count;  // highest bit set indicates a leaf node (inner node if highest bit is 0)
		nodeList[currNodeIdx].node.leaf._startIndexList = faceIdx;
        nodeList[currNodeIdx].node.leaf._type = TYPE_TRIG;

		for (std::list<const void*>::iterator it = p->_primitive.begin(); it != p->_primitive.end(); it++)
		{
            const Triangle* trig = (const Triangle*) *(it);
			faceList[faceIdx].primID = trig - pFirstTriangle;
            faceList[faceIdx].idx0   = trig->idx0;
            faceList[faceIdx].idx1   = trig->idx1;
            faceList[faceIdx].idx2   = trig->idx2;
            faceIdx++;
		}
	}
}

void CreateDeviceBVH(BVHNode* root, const std::vector<Triangle>& faces,
    std::vector<DeviceTriangle>& faceList, std::vector<DeviceBVHNode>& nodeList)
{
	faceList.resize(faces.size());

	unsigned int nodeCount = CountBoxes(root);
	nodeList.resize(nodeCount);

    unsigned int faceIdx = 0;
	unsigned int nodeIdx = 0;
	PopulateCacheFriendlyBVH(&faces[0], root, faceIdx, nodeIdx, faceList, nodeList);

	if ((nodeIdx != nodeCount - 1) || (faceIdx != faces.size())) {
		puts("Internal bug in CreateCFBVH, please report it..."); fflush(stdout);
		exit(1);
	}

	int maxDepth = 0;
	CountDepth(root, 0, maxDepth);
	printf("Max BVH depth is %d\n", maxDepth);
}

void PopulateCacheFriendlyBVH(
	const Instance *pFirstInstance, BVHNode *root, unsigned int& instIdx, unsigned int& nodeIdx,
    std::map<BottomAccelStruct, unsigned int>& instOffsetMap,
    std::vector<DeviceInstance>& instList, std::vector<DeviceBVHNode>& nodeList)
{
	unsigned currNodeIdx = nodeIdx;
	nodeList[currNodeIdx]._bottom = root->_bottom;
	nodeList[currNodeIdx]._top = root->_top;

	//DEPTH FIRST APPROACH (left first until complete)
	if (!root->IsLeaf()) { // inner node
		BVHInner *p = dynamic_cast<BVHInner*>(root);
		// recursively populate left and right
		int idxLeft = ++nodeIdx;
		PopulateCacheFriendlyBVH(
            pFirstInstance, p->_left, instIdx, nodeIdx, instOffsetMap, instList, nodeList);
		int idxRight = ++nodeIdx;
		PopulateCacheFriendlyBVH(
            pFirstInstance, p->_right, instIdx, nodeIdx, instOffsetMap, instList, nodeList);
		nodeList[currNodeIdx].node.inner._idxLeft = idxLeft;
		nodeList[currNodeIdx].node.inner._idxRight = idxRight;
	}

	else { // leaf
		BVHLeaf *p = dynamic_cast<BVHLeaf*>(root);
		unsigned count = p->_primitive.size();
		nodeList[currNodeIdx].node.leaf._count = 0x80000000 | count;
		nodeList[currNodeIdx].node.leaf._startIndexList = instIdx;
        nodeList[currNodeIdx].node.leaf._type = TYPE_INST;

		for (std::list<const void*>::iterator it = p->_primitive.begin();
            it != p->_primitive.end(); it++)
		{
            const Instance* inst = (const Instance*) *(it);
			instList[instIdx].instanceID                = inst - pFirstInstance;
            instList[instIdx].customInstanceID          = inst->customInstanceID;
            instList[instIdx].SBTOffset                 = inst->SBTOffset;
            instList[instIdx].transform                 = inst->transform;
            instList[instIdx].bottomAccelStructOffset   = instOffsetMap[inst->bottomAccelStruct];
            instIdx++;
		}
	}
}

void CreateDeviceBVH(BVHNode* root, const std::vector<Instance>& instList,
    std::vector<DeviceInstance>& deviceInstList, std::vector<DeviceBVHNode>& nodeList,
    std::map<BottomAccelStruct, unsigned int>& instOffsetMap)
{

    deviceInstList.resize(instList.size());
	nodeList.resize(CountBoxes(root));
    unsigned int topASSize = sizeof(AccelStructTop) + 
        nodeList.size() * sizeof(DeviceBVHNode) +
        deviceInstList.size() * sizeof(DeviceInstance);

    unsigned int nextOffset = 0;
    for (const Instance& i: instList)
    {
        if (instOffsetMap.find(i.bottomAccelStruct) == instOffsetMap.end())
        {
            printf("Building TopAS: Writing to instance offset at: %u\n", nextOffset);
            instOffsetMap[i.bottomAccelStruct] = nextOffset + topASSize;
            nextOffset = nextOffset + i.bottomAccelStruct->data.size();
        }
    }

    unsigned int instIdx = 0;
	unsigned int nodeIdx = 0;
	PopulateCacheFriendlyBVH(&instList[0], root, instIdx, nodeIdx, instOffsetMap, deviceInstList, nodeList);
}


} // namespace RD
