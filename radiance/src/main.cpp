#include "core.h"
#include "clcontext.h"
#include "bvh.h"
#include "linalg.h"

#define STB_IMAGE_WRITE_IMPLEMENTATION
#include "stb_image_write.h"

#include <limits.h>
#include <vector>

bool modelLoader(
    std::vector<aiVector3f>& vertices,
    std::vector<Triangle>& triangles,
    std::string modelFile);

int directGen();

int triangleHit(CLContext* ctx, cl_mem& accelStructBuf);

cl_mem buildAccelStruct(CLContext* ctx,
    const std::vector<DeviceBVHNode>& nodeList,
    const std::vector<unsigned int>& faceRefList,
    const std::vector<DeviceTriangle>& triangleList);

std::string cwd = "/home/zekailin00/Desktop/ray-tracing/framework";

int main()
{
    std::string modelFile = cwd + "/stanford-bunny.obj";
    std::vector<aiVector3f> vertices;
    std::vector<Triangle> triangles;

    modelLoader(vertices, triangles, modelFile);
    BVHNode* root = CreateBVH(vertices, triangles);

    std::vector<unsigned int> faceRefList;
    std::vector<DeviceBVHNode> nodeList;
    CreateDeviceBVH(root, triangles, faceRefList, nodeList);

    printf("face ref list size: %ld\n", faceRefList.size());
    printf("node list size: %ld\n", nodeList.size());

    CLContext* ctx = CLContext::GetCLContext();

    std::vector<DeviceTriangle> deviceTriangleList;
    for (const Triangle& f: triangles)
    {
        deviceTriangleList.push_back({
            f.v0, 0.0f, f.v1, 0.0f, f.v2, 0.0f
        });
    }

    cl_mem accelStructBuf = buildAccelStruct(ctx, nodeList, faceRefList, deviceTriangleList);
    triangleHit(ctx, accelStructBuf);

    // directGen();
}

cl_mem buildAccelStruct(CLContext* ctx,
    const std::vector<DeviceBVHNode>& nodeList,
    const std::vector<unsigned int>& faceRefList,
    const std::vector<DeviceTriangle>& deviceTriangleList)
{
    unsigned int nodeListSize = nodeList.size() * sizeof(DeviceBVHNode),
                 triListSize = deviceTriangleList.size() * sizeof(DeviceTriangle),
                 faceRefListSize = faceRefList.size() * sizeof(unsigned int);
    
    // header size + data size
    unsigned int bufferSizeByte = sizeof(AccelStruct) +
        nodeListSize + faceRefListSize + triListSize;

#ifndef NDEBUG
    printf("DeviceBVHNode size: %ld\n\t %ld elements\n\t array bytes: %u\n",
        sizeof(DeviceBVHNode), nodeList.size(), nodeListSize);
    printf("Triangle size: %ld\n\t %ld elements\n\t array bytes: %u\n",
        sizeof(DeviceTriangle), deviceTriangleList.size(), triListSize);
    printf("FaceRef (unsigned int) size: %ld\n\t %ld elements\n\t array bytes: %u\n",
        sizeof(unsigned int), faceRefList.size(), faceRefListSize);
    printf("AccelStruct header size: %lu\n", sizeof(AccelStruct));
    printf("Total AccelStruct data size: %u\n", bufferSizeByte);
#endif

    cl_mem accelStructBuf = CL_CHECK2(clCreateBuffer(
        ctx->context, CL_MEM_READ_WRITE, bufferSizeByte, NULL, &_err));

    AccelStruct accelStruct = {
        .nodeByteOffset = (unsigned)sizeof(AccelStruct),
        .faceByteOffset = (unsigned)sizeof(AccelStruct) + nodeListSize,
        .faceRefByteOffset = (unsigned)sizeof(AccelStruct) + nodeListSize + triListSize,
    };

    CL_CHECK(clEnqueueWriteBuffer(ctx->commandQueue, accelStructBuf, CL_TRUE,
        0, sizeof(accelStruct), &accelStruct,
        0, NULL, NULL));
    CL_CHECK(clEnqueueWriteBuffer(ctx->commandQueue, accelStructBuf, CL_TRUE,
        accelStruct.nodeByteOffset, nodeListSize, nodeList.data(),
        0, NULL, NULL));
    CL_CHECK(clEnqueueWriteBuffer(ctx->commandQueue, accelStructBuf, CL_TRUE,
        accelStruct.faceByteOffset, triListSize, deviceTriangleList.data(),
        0, NULL, NULL));
    CL_CHECK(clEnqueueWriteBuffer(ctx->commandQueue, accelStructBuf, CL_TRUE,
        accelStruct.faceRefByteOffset, faceRefListSize, faceRefList.data(),
        0, NULL, NULL));

    return accelStructBuf;
}

bool modelLoader(
    std::vector<aiVector3f>& vertices,
    std::vector<Triangle>& triangles,
    std::string modelFile)
{
    // Create an instance of the Importer class
    Assimp::Importer importer;

    // And have it read the given file with some example postprocessing
    // Usually - if speed is not the most important aspect for you - you'll
    // probably to request more postprocessing than we do in this example.
    const aiScene* scene = importer.ReadFile( modelFile,
        aiProcess_GenSmoothNormals       |
        aiProcess_Triangulate            |
        aiProcess_JoinIdenticalVertices  |
        aiProcess_SortByPType);

    // If the import failed, report it
    if (nullptr == scene) {
        printf("%s", importer.GetErrorString());
        return false;
    }

    assert(scene->mNumMeshes == 1);

    const aiMesh* mesh = scene->mMeshes[0];

    printf("Number of vertices: %d\n", mesh->mNumVertices);
    printf("Number of faces: %d\n", mesh->mNumFaces);

    vertices.resize(mesh->mNumVertices);
    triangles.resize(mesh->mNumFaces);

    for (size_t i = 0; i < mesh->mNumVertices; i++)
    {
        vertices[i] = mesh->mVertices[i];
    }

    for (size_t i = 0; i < mesh->mNumFaces; i++)
    {
        assert(mesh->mFaces[i].mNumIndices == 3);

        triangles[i].index = i;

        triangles[i].idx0 = mesh->mFaces[i].mIndices[0];
        triangles[i].idx1 = mesh->mFaces[i].mIndices[1];
        triangles[i].idx2 = mesh->mFaces[i].mIndices[2];
        triangles[i].v0 = vertices[triangles[i].idx0];
        triangles[i].v1 = vertices[triangles[i].idx1];
        triangles[i].v2 = vertices[triangles[i].idx2];

        calculateSurfaceNormal(triangles[i]._normal,
            vertices[triangles[i].idx0],
            vertices[triangles[i].idx1],
            vertices[triangles[i].idx2]
        );

        aiVector3f tmp;
        minVec3(tmp, vertices[triangles[i].idx0], vertices[triangles[i].idx1]);
        minVec3(tmp, tmp, vertices[triangles[i].idx2]);
        // triangles[i]._bottom[0] = tmp[0];
        // triangles[i]._bottom[1] = tmp[1];
        // triangles[i]._bottom[2] = tmp[2];

        maxVec3(tmp, vertices[triangles[i].idx0], vertices[triangles[i].idx1]);
        maxVec3(tmp, tmp, vertices[triangles[i].idx2]);
        // triangles[i]._top[0] = tmp[0];
        // triangles[i]._top[1] = tmp[1];
        // triangles[i]._top[2] = tmp[2];
    }

    return true;
}


int triangleHit(CLContext* ctx, cl_mem& accelStructBuf)
{
    const size_t WIDTH = 1080;
    const size_t HEIGHT = 1080;
    // const size_t WIDTH = 20;
    // const size_t HEIGHT = 20;
    const size_t CHANNEL = 4;

    unsigned int extent[2] = {WIDTH, HEIGHT};
    uint8_t* image = (uint8_t*)malloc(WIDTH * HEIGHT * CHANNEL);

    printf("Allocate device buffers\n"); fflush(stdout);

    cl_mem imageBuf = CL_CHECK2(clCreateBuffer(
        ctx->context, CL_MEM_READ_WRITE, WIDTH * HEIGHT * CHANNEL, NULL, &_err));
    cl_mem extentBuf = CL_CHECK2(clCreateBuffer(
        ctx->context, CL_MEM_READ_WRITE, sizeof(unsigned int) * 2, NULL, &_err));

    char* codeShader;
    size_t shaderSize;
    std::string shaderPath = cwd + "/shader.cl";
    read_kernel_file_str(shaderPath.c_str(), &codeShader, &shaderSize);

    cl_program tracingProgram;
    cl_int libraryStatus;

    const char* programs[1] = {codeShader};
    const size_t programSizes[1] = {shaderSize};
    tracingProgram = CL_CHECK2(clCreateProgramWithSource(
        ctx->context, 1, programs, programSizes, &_err));
    
    printf("build program and get raygen kernel\n"); fflush(stdout);
    std::string includeDir = "-I" + cwd;
    if(clBuildProgram(tracingProgram, 1, &ctx->device_id, includeDir.c_str(), NULL, NULL) < 0)
    {
        char log[1000];
        size_t retSize;
        clGetProgramBuildInfo(tracingProgram, ctx->device_id, CL_PROGRAM_BUILD_LOG, 1000, log, &retSize);
        printf("error output: %s\n", log);

        return -1;
    }

    cl_kernel raygen = CL_CHECK2(clCreateKernel(tracingProgram, "raygen", &_err));
    // // Set kernel arguments
    CL_CHECK(clSetKernelArg(raygen, 0, sizeof(cl_mem), (void *)&(imageBuf)));
    CL_CHECK(clSetKernelArg(raygen, 1, sizeof(cl_mem), (void *)&(extentBuf)));
    CL_CHECK(clSetKernelArg(raygen, 2, sizeof(cl_mem), (void *)&(accelStructBuf)));
    fflush(stdout);

    CL_CHECK(clEnqueueWriteBuffer(ctx->commandQueue, extentBuf,
        CL_TRUE, 0, sizeof(extent), extent, 0, NULL, NULL));

    printf("Execute the kernel\n");
    size_t global_work_size[1] = {WIDTH * HEIGHT};
    size_t local_work_size[1] = {1};
    auto time_start = std::chrono::high_resolution_clock::now();
    CL_CHECK(clEnqueueNDRangeKernel(ctx->commandQueue, raygen, 1, NULL,
        global_work_size, local_work_size, 0, NULL, NULL));

    CL_CHECK(clFinish(ctx->commandQueue));
    
    printf("Download destination buffer\n"); fflush(stdout);
    CL_CHECK(clEnqueueReadBuffer(ctx->commandQueue,
        imageBuf, CL_TRUE, 0, WIDTH * HEIGHT * CHANNEL, image, 0, NULL, NULL));
    
    auto time_end = std::chrono::high_resolution_clock::now();
    double elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(time_end - time_start).count();
    printf("Elapsed time: %lg ms\n", elapsed);
    fflush(stdout);

    stbi_write_jpg("output.jpg", WIDTH, HEIGHT, CHANNEL, image, 100);
    ctx->Cleanup();

    return 0;
}


int directGen()
{
    CLContext* ctx = CLContext::GetCLContext();

    const size_t WIDTH = 720;
    const size_t HEIGHT = 720;
    const size_t CHANNEL = 4;
    AccelStruct accelStruct = {
        .nodeByteOffset = 1,
        .faceByteOffset = 2,
        .faceRefByteOffset = 3
    };
    unsigned int extent[2] = {WIDTH, HEIGHT};
    uint8_t* image = (uint8_t*)malloc(WIDTH * HEIGHT * CHANNEL);

    printf("Allocate device buffers\n"); fflush(stdout);

    cl_mem imageBuf = CL_CHECK2(clCreateBuffer(
        ctx->context, CL_MEM_READ_WRITE, WIDTH * HEIGHT * CHANNEL, NULL, &_err));
    cl_mem extentBuf = CL_CHECK2(clCreateBuffer(
        ctx->context, CL_MEM_READ_ONLY, sizeof(unsigned int) * 2, NULL, &_err));
    cl_mem accelStructBuf = CL_CHECK2(clCreateBuffer(
        ctx->context, CL_MEM_READ_ONLY, sizeof(AccelStruct), NULL, &_err));

    char* codeShader;
    size_t shaderSize;
    std::string shaderPath = cwd + "/shader.cl";
    read_kernel_file_str(shaderPath.c_str(), &codeShader, &shaderSize);

    cl_program tracingProgram;
    cl_int libraryStatus;

    const char* programs[1] = {codeShader};
    const size_t programSizes[1] = {shaderSize};
    tracingProgram = CL_CHECK2(clCreateProgramWithSource(
        ctx->context, 1, programs, programSizes, &_err));
    
    printf("build program and get raygen kernel\n"); fflush(stdout);
    std::string includeDir = "-I" + cwd;
    if(clBuildProgram(tracingProgram, 1, &ctx->device_id, includeDir.c_str(), NULL, NULL) < 0)
    {
        char log[1000];
        size_t retSize;
        clGetProgramBuildInfo(tracingProgram, ctx->device_id, CL_PROGRAM_BUILD_LOG, 1000, log, &retSize);
        printf("error output: %s\n", log);

        return -1;
    }

    cl_kernel raygen = CL_CHECK2(clCreateKernel(tracingProgram, "raygen", &_err));
    // // Set kernel arguments
    CL_CHECK(clSetKernelArg(raygen, 0, sizeof(cl_mem), (void *)&(imageBuf)));
    CL_CHECK(clSetKernelArg(raygen, 1, sizeof(cl_mem), (void *)&(extentBuf)));
    CL_CHECK(clSetKernelArg(raygen, 2, sizeof(cl_mem), (void *)&(accelStructBuf)));
    fflush(stdout);

    CL_CHECK(clEnqueueWriteBuffer(ctx->commandQueue, extentBuf,
        CL_TRUE, 0, sizeof(extent), extent, 0, NULL, NULL));
    CL_CHECK(clEnqueueWriteBuffer(ctx->commandQueue, accelStructBuf,
        CL_TRUE, 0, sizeof(accelStruct), &accelStruct, 0, NULL, NULL));

    printf("Execute the kernel\n");
    size_t global_work_size[1] = {WIDTH * HEIGHT};
    size_t local_work_size[1] = {1};
    auto time_start = std::chrono::high_resolution_clock::now();
    CL_CHECK(clEnqueueNDRangeKernel(ctx->commandQueue, raygen, 1, NULL,
        global_work_size, local_work_size, 0, NULL, NULL));

    CL_CHECK(clFinish(ctx->commandQueue));
    
    printf("Download destination buffer\n"); fflush(stdout);
    CL_CHECK(clEnqueueReadBuffer(ctx->commandQueue,
        imageBuf, CL_TRUE, 0, WIDTH * HEIGHT * CHANNEL, image, 0, NULL, NULL));
    
    auto time_end = std::chrono::high_resolution_clock::now();
    double elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(time_end - time_start).count();
    printf("Elapsed time: %lg ms\n", elapsed);
    fflush(stdout);

    stbi_write_jpg("output.jpg", WIDTH, HEIGHT, CHANNEL, image, 100);
    ctx->Cleanup();

    return 0;
}