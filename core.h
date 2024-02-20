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

struct AccelStruct
{
    unsigned int nodeByteOffset;
    unsigned int faceRefByteOffset;
    unsigned int faceByteOffset;
};