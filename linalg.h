#pragma once

#include "core.h"


static void calculateSurfaceNormal(aiVector3f& norm,
    const aiVector3f& v1, const aiVector3f& v2, const aiVector3f& v3)
{
    float
    u[3] = {
        v2[0] - v1[0],
        v2[1] - v1[1],
        v2[2] - v1[2]
    },
    v[3] = {
        v3[0] - v1[0],
        v3[1] - v1[1],
        v3[2] - v1[2]
    };

    norm[0] = u[1] * v[2] - u[2] * v[1];
    norm[1] = u[2] * v[0] - u[0] * v[2];
    norm[2] = u[0] * v[1] - u[1] * v[0];
}

static void minVec3(aiVector3f& out, const aiVector3f& v0, const aiVector3f& v1)
{
    out[0] = v0[0] < v1[0]? v0[0]: v1[0];
    out[1] = v0[1] < v1[1]? v0[1]: v1[1];
    out[2] = v0[2] < v1[2]? v0[2]: v1[2];
}

static void maxVec3(aiVector3f& out, const aiVector3f& v0, const aiVector3f& v1)
{
    out[0] = v0[0] > v1[0]? v0[0]: v1[0];
    out[1] = v0[1] > v1[1]? v0[1]: v1[1];
    out[2] = v0[2] > v1[2]? v0[2]: v1[2];   
}