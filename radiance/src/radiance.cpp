#include "radiance.h"
#include "bvh.h"

namespace RD
{

cl_mem _buildAccelStruct(CLContext* ctx,
    const std::vector<DeviceBVHNode>& nodeList,
    const std::vector<unsigned int>& faceRefList,
    const std::vector<DeviceTriangle>& deviceTriangleList);

AccelStruct BuildAccelStruct(Platform* platform, Mesh& mesh)
{
    CLContext* ctx = platform->clContext;
    BVHNode* root = CreateBVH(mesh.vertexData, mesh.indexData);

    std::vector<unsigned int> faceRefList;
    std::vector<DeviceBVHNode> nodeList;
    CreateDeviceBVH(root, mesh.indexData, faceRefList, nodeList);

    printf("face ref list size: %ld\n", faceRefList.size());
    printf("node list size: %ld\n", nodeList.size());

    std::vector<DeviceTriangle> deviceTriangleList;
    for (const Triangle& f: mesh.indexData)
    {
        //FIXME:
        deviceTriangleList.push_back({
            mesh.vertexData[f.idx0], 0.0f,
            mesh.vertexData[f.idx1], 0.0f,
            mesh.vertexData[f.idx2], 0.0f
        });
    }

    cl_mem accelStructBuf = _buildAccelStruct(ctx, nodeList, faceRefList, deviceTriangleList);
    return accelStructBuf;
}

Image CreateImage(Platform* platform, unsigned int width, unsigned int height)
{
    CLContext* ctx = platform->clContext;
    cl_mem handle = CL_CHECK2(clCreateBuffer(
        ctx->context, CL_MEM_READ_WRITE, width * height * CHANNEL, NULL, &_err));

    return handle;
}

Buffer CreateBuffer(Platform* platform, unsigned int size)
{
    CLContext* ctx = platform->clContext;
    cl_mem handle = CL_CHECK2(clCreateBuffer(
        ctx->context, CL_MEM_READ_WRITE, size, NULL, &_err));

    return handle;
}

DescriptorSet CreateDescriptorSet(std::vector<Handle> handles)
{
    return handles;
}

PipelineLayout CreatePipelineLayout(std::vector<DescriptorType> descriptorTypes)
{
    return descriptorTypes;
}

ShaderModule CreateShaderModule(Platform* platform, char* code, unsigned int size, char* name)
{
    CLContext* ctx = platform->clContext;
    cl_program tracingProgram;
    cl_int libraryStatus;

    const char* programs[1] = {code};
    const size_t programSizes[1] = {size};
    tracingProgram = CL_CHECK2(clCreateProgramWithSource(
        ctx->context, 1, programs, programSizes, &_err));
    
    printf("build program and get raygen kernel\n"); fflush(stdout);

    std::string includeDir = SHADER_LIB_PATH;
    includeDir = "-I" + includeDir;
    if(clBuildProgram(tracingProgram, 1, &ctx->device_id, includeDir.c_str(), NULL, NULL) < 0)
    {
        char log[1000];
        size_t retSize;
        clGetProgramBuildInfo(tracingProgram, ctx->device_id, CL_PROGRAM_BUILD_LOG, 1000, log, &retSize);
        printf("error output: %s\n", log);

        throw;
    }

    cl_kernel raygen = CL_CHECK2(clCreateKernel(tracingProgram, "raygen", &_err));
    return raygen;
}

Pipeline CreatePipeline(PipelineCreateInfo pipelineCreateInfo)
{
    return pipelineCreateInfo;
}

void ReadBuffer(Platform* platform, Handle handle, size_t size, void* data)
{
    CLContext* ctx = platform->clContext;
    CL_CHECK(clEnqueueReadBuffer(ctx->commandQueue, handle,
        CL_TRUE, 0, size, data, 0, NULL, NULL));
}

void WriteBuffer(Platform* platform, Handle handle, size_t size, void* data)
{
    CLContext* ctx = platform->clContext;
    CL_CHECK(clEnqueueWriteBuffer(ctx->commandQueue, handle,
        CL_TRUE, 0, size, data, 0, NULL, NULL));
}

void BindPipeline(Platform* platform, Pipeline pipeline)
{
    platform->activePipeline = pipeline;
}

void BindDescriptorSet(Platform* platform, DescriptorSet descriptorSet)
{
    Pipeline pipeline =  platform->activePipeline;
    CLContext* ctx = platform->clContext;

    for (int i = 0; i < descriptorSet.size(); i++)
    {
         CL_CHECK(clSetKernelArg(pipeline.modules[0], i, sizeof(cl_mem), (void *)&(descriptorSet[i])));
    }
}

void TraceRays(Platform* platform,
    unsigned int raygenGroupIndex,
    unsigned int missGroupIndex,
    unsigned int hitGroupIndex,
    unsigned int width,
    unsigned int height)
{
    printf("Execute the kernel\n");
    size_t global_work_size[1] = {width * height};
    size_t local_work_size[1] = {1};
    auto time_start = std::chrono::high_resolution_clock::now();

    cl_kernel raygen = platform->activePipeline.modules[0];
    CLContext* ctx = platform->clContext;


    CL_CHECK(clEnqueueNDRangeKernel(ctx->commandQueue, raygen, 1, NULL,
        global_work_size, local_work_size, 0, NULL, NULL));

    CL_CHECK(clFinish(ctx->commandQueue));
    
    auto time_end = std::chrono::high_resolution_clock::now();
    double elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(time_end - time_start).count();
    printf("Elapsed time: %lg ms\n", elapsed);
    fflush(stdout);    
}

cl_mem _buildAccelStruct(CLContext* ctx,
    const std::vector<DeviceBVHNode>& nodeList,
    const std::vector<unsigned int>& faceRefList,
    const std::vector<DeviceTriangle>& deviceTriangleList)
{
    unsigned int nodeListSize = nodeList.size() * sizeof(DeviceBVHNode),
                 triListSize = deviceTriangleList.size() * sizeof(DeviceTriangle),
                 faceRefListSize = faceRefList.size() * sizeof(unsigned int);
    
    // header size + data size
    unsigned int bufferSizeByte = sizeof(AccelStructHeader) +
        nodeListSize + faceRefListSize + triListSize;

#ifndef NDEBUG
    printf("DeviceBVHNode size: %ld\n\t %ld elements\n\t array bytes: %u\n",
        sizeof(DeviceBVHNode), nodeList.size(), nodeListSize);
    printf("Triangle size: %ld\n\t %ld elements\n\t array bytes: %u\n",
        sizeof(DeviceTriangle), deviceTriangleList.size(), triListSize);
    printf("FaceRef (unsigned int) size: %ld\n\t %ld elements\n\t array bytes: %u\n",
        sizeof(unsigned int), faceRefList.size(), faceRefListSize);
    printf("AccelStruct header size: %lu\n", sizeof(AccelStructHeader));
    printf("Total AccelStruct data size: %u\n", bufferSizeByte);
#endif

    cl_mem accelStructBuf = CL_CHECK2(clCreateBuffer(
        ctx->context, CL_MEM_READ_WRITE, bufferSizeByte, NULL, &_err));

    AccelStructHeader accelStruct = {
        .nodeByteOffset = (unsigned int)sizeof(AccelStructHeader),
        .faceByteOffset = (unsigned int)sizeof(AccelStructHeader) + nodeListSize,
        .faceRefByteOffset = (unsigned int)sizeof(AccelStructHeader) + nodeListSize + triListSize,
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

} // namespace RD
