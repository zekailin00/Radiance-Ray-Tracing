#include "radiance.h"
#include "bvh.h"


namespace RD
{

void _buildBottomAccelStruct(CLContext* ctx,
    const std::vector<DeviceBVHNode>& nodeList,
    const std::vector<DeviceTriangle>& faceList,
    const std::vector<Vec3>& vertexList,
    std::vector<char>& data);

TopAccelStruct _buildTopAccelStruct(CLContext* ctx,
    const std::vector<DeviceBVHNode>& nodeList,
    const std::vector<DeviceInstance>& deviceInstList,
    const std::vector<Instance>& instList,
    const std::map<BottomAccelStruct, unsigned int>& instOffsetMap);

BottomAccelStruct BuildAccelStruct(Platform* platform, Mesh& mesh)
{
    CLContext* ctx = platform->clContext;
    BVHNode* root = CreateBVH(mesh.vertexData, mesh.indexData);

    _BottomAccelStruct* accelStruct = new _BottomAccelStruct();
    accelStruct->root = root;

    std::vector<DeviceTriangle> deviceTrigList;
    std::vector<DeviceBVHNode> nodeList;
    CreateDeviceBVH(root, mesh.indexData, deviceTrigList, nodeList);

    printf("device face list size: %ld\n", deviceTrigList.size());
    printf("node list size: %ld\n", nodeList.size());

    _buildBottomAccelStruct(ctx, nodeList, deviceTrigList,
        mesh.vertexData, accelStruct->data);
    return accelStruct;
}

TopAccelStruct BuildAccelStruct(Platform* platform, std::vector<Instance>& instances)
{
    CLContext* ctx = platform->clContext;
    BVHNode* root = CreateBVH(instances);

    std::vector<DeviceInstance> deviceInstList;
    std::vector<DeviceBVHNode> nodeList;
    std::map<BottomAccelStruct, unsigned int> instOffsetList;
    CreateDeviceBVH(root, instances, deviceInstList, nodeList, instOffsetList);

    printf("device instance list size: %ld\n", deviceInstList.size());
    printf("node list size: %ld\n", nodeList.size());
    printf("Instance offset list size: %ld\n", instOffsetList.size());

    TopAccelStruct topAccelStruct = _buildTopAccelStruct(ctx,
        nodeList, deviceInstList, instances, instOffsetList);

    return topAccelStruct;
}

Image CreateImage(Platform* platform, unsigned int width, unsigned int height)
{
    CLContext* ctx = platform->clContext;
    cl_mem handle = CL_CHECK2(clCreateBuffer(
        ctx->context, CL_MEM_READ_WRITE, width * height * CHANNEL, NULL, &_err));

    return handle;
}


ImageArray CreateImageArray(Platform* platform,
    unsigned int width, unsigned int height, unsigned int arraySize)
{
    const cl_image_format imgFmt = {
        .image_channel_order = CL_RGBA,
        .image_channel_data_type = CL_UNSIGNED_INT8
    };

    const cl_image_desc imgDesc = {
        .image_type = CL_MEM_OBJECT_IMAGE2D_ARRAY,
        .image_width = width,
        .image_height = height,
        .image_depth = 1,
        .image_array_size = arraySize,
        .image_row_pitch = 0,
        .image_slice_pitch = 0,
        .num_mip_levels = 0,
        .num_samples = 0
    };

    cl_int errCode;
    CLContext* ctx = platform->clContext;
    cl_mem handle = clCreateImage(ctx->context,
        CL_MEM_READ_WRITE, &imgFmt, &imgDesc, NULL, &errCode);
    return handle;
}

Sampler CreateSampler(Platform* platform,
    AddressingMode addressingMode, FilterMode filterMode)
{
    cl_int errCode;
    CLContext* ctx = platform->clContext;
    cl_sampler sampler = clCreateSampler(ctx->context,
        CL_TRUE, addressingMode, filterMode, &errCode);
    return sampler;
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
    includeDir = "-g -I" + includeDir;
    if(clBuildProgram(tracingProgram, 1, &ctx->device_id, includeDir.c_str(), NULL, NULL) < 0)
    {
        char log[10000];
        size_t retSize;
        clGetProgramBuildInfo(tracingProgram, ctx->device_id, CL_PROGRAM_BUILD_LOG, 10000, log, &retSize);
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

void ReadBuffer(Platform* platform,
    Buffer handle, size_t size, void* data, size_t offset)
{
    CLContext* ctx = platform->clContext;
    CL_CHECK(clEnqueueReadBuffer(ctx->commandQueue, handle,
        CL_TRUE, offset, size, data, 0, NULL, NULL));
}

void WriteBuffer(Platform* platform,
    Buffer handle, size_t size, void* data, size_t offset)
{
    CLContext* ctx = platform->clContext;
    CL_CHECK(clEnqueueWriteBuffer(ctx->commandQueue, handle,
        CL_TRUE, offset, size, data, 0, NULL, NULL));
}

void ReadImage(Platform* platform, ImageArray handle,
    unsigned int width, unsigned int height, size_t arrayIndex, void* data)
{
    size_t origin[3] = {0, 0, arrayIndex};
    size_t region[3] = {width, height, 1};

    CLContext* ctx = platform->clContext;
    CL_CHECK(clEnqueueReadImage(ctx->commandQueue, handle,
        CL_TRUE, origin, region, 0, 0, data,
        0, 0, NULL));
}

void WriteImage(Platform* platform, ImageArray handle,
    unsigned int width, unsigned int height, size_t arrayIndex, void* data)
{
    size_t origin[3] = {0, 0, arrayIndex};
    size_t region[3] = {width, height, 1};

    CLContext* ctx = platform->clContext;
    CL_CHECK(clEnqueueWriteImage(ctx->commandQueue, handle,
        CL_TRUE, origin, region, 0, 0, data,
        0, 0, NULL));
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
    // printf("Execute the kernel\n");
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
    // printf("Elapsed time: %lg ms\n", elapsed);
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

void _buildBottomAccelStruct(CLContext* ctx,
    const std::vector<DeviceBVHNode>& nodeList,
    const std::vector<DeviceTriangle>& faceList,
    const std::vector<Vec3>& vertexList,
    std::vector<char>& data)
{
    unsigned int nodeListSize = nodeList.size() * sizeof(DeviceBVHNode),
                 faceListSize = faceList.size() * sizeof(DeviceTriangle),
                 vertexListSize = vertexList.size() * sizeof(DeviceVertex);
    
    // header size + data size
    unsigned int bufferSizeByte = sizeof(AccelStructBottom) +
        nodeListSize + faceListSize + vertexListSize;

#ifndef NDEBUG
    printf("DeviceBVHNode size: %ld\n\t %ld elements\n\t array bytes: %u\n",
        sizeof(DeviceBVHNode), nodeList.size(), nodeListSize);
    printf("Triangle size: %ld\n\t %ld elements\n\t array bytes: %u\n",
        sizeof(DeviceTriangle), faceList.size(), faceListSize);
    printf("Vertex size: %ld\n\t %ld elements\n\t array bytes: %u\n",
        sizeof(DeviceVertex), vertexList.size(), vertexListSize);
    printf("AccelStruct header size: %lu\n", sizeof(AccelStructBottom));
    printf("Total AccelStruct data size: %u\n", bufferSizeByte);
#endif

    data.resize(bufferSizeByte);

    AccelStructBottom accelStruct = {
        .type           = TYPE_BOT_AS,
        .nodeByteOffset = sizeof(AccelStructBottom),
        .faceByteOffset = (unsigned int) sizeof(AccelStructBottom) + nodeListSize,
        .vertexOffset   = (unsigned int) sizeof(AccelStructBottom) + nodeListSize + faceListSize,
    };

    char* ptr = data.data();
    memcpy(ptr, &accelStruct, sizeof(AccelStructBottom));
    memcpy(ptr + accelStruct.nodeByteOffset, nodeList.data(), nodeListSize);
    memcpy(ptr + accelStruct.faceByteOffset, faceList.data(), faceListSize);
    DeviceVertex* pVertex = (DeviceVertex*)(ptr + accelStruct.vertexOffset);
    for (int i = 0; i < vertexList.size(); i++)
    {
        DeviceVertex* ptr = pVertex + i;
        ptr->x = vertexList[i].x;
        ptr->y = vertexList[i].y;
        ptr->z = vertexList[i].z;
    }
}

TopAccelStruct _buildTopAccelStruct(CLContext* ctx,
    const std::vector<DeviceBVHNode>& nodeList,
    const std::vector<DeviceInstance>& deviceInstList,
    const std::vector<Instance>& instList,
    const std::map<BottomAccelStruct, unsigned int>& instOffsetMap)
{
    unsigned int nodeListSize = nodeList.size() * sizeof(DeviceBVHNode),
                 deviceInstListSize = deviceInstList.size() * sizeof(DeviceInstance),
                 instanceTotalSize = 0;

    for (auto it = instOffsetMap.begin(); it != instOffsetMap.end(); it++)
    {
        instanceTotalSize += it->first->data.size();
    }

    // header size + data size
    unsigned int bufferSizeByte = sizeof(AccelStructTop) +
        nodeListSize + deviceInstListSize + instanceTotalSize;

#ifndef NDEBUG
    printf("DeviceBVHNode size: %ld\n\t %ld elements\n\t array bytes: %u\n",
        sizeof(DeviceBVHNode), nodeList.size(), nodeListSize);
    printf("Device instance size: %ld\n\t %ld elements\n\t array bytes: %u\n",
        sizeof(DeviceInstance), deviceInstList.size(), deviceInstListSize);
    printf("Instance data size: %ld\n\t %ld elements\n\t array bytes: %u\n",
        sizeof(BottomAccelStruct), instOffsetMap.size(), instanceTotalSize);
    printf("AccelStruct header size: %lu\n", sizeof(AccelStructTop));
    printf("Total AccelStruct data size: %u\n", bufferSizeByte);
#endif

    cl_mem accelStructBuf = CL_CHECK2(clCreateBuffer(
        ctx->context, CL_MEM_READ_WRITE, bufferSizeByte, NULL, &_err));

    AccelStructTop accelStruct = {
        .type            = TYPE_TOP_AS,
        .nodeByteOffset  = sizeof(AccelStructTop),
        .instByteOffset  = (unsigned int) sizeof(AccelStructTop) + nodeListSize,
        .totalBufferSize = (unsigned int) bufferSizeByte
    };


    CL_CHECK(clEnqueueWriteBuffer(ctx->commandQueue, accelStructBuf, CL_TRUE,
        0, sizeof(accelStruct), &accelStruct,
        0, NULL, NULL));
    CL_CHECK(clEnqueueWriteBuffer(ctx->commandQueue, accelStructBuf, CL_TRUE,
        accelStruct.nodeByteOffset, nodeListSize, nodeList.data(),
        0, NULL, NULL));
    CL_CHECK(clEnqueueWriteBuffer(ctx->commandQueue, accelStructBuf, CL_TRUE,
        accelStruct.instByteOffset, deviceInstListSize, deviceInstList.data(),
        0, NULL, NULL));
    
    for (auto &e: instOffsetMap)
    {
        CL_CHECK(clEnqueueWriteBuffer(ctx->commandQueue, accelStructBuf, CL_TRUE,
            e.second, e.first->data.size(), e.first->data.data(),
            0, NULL, NULL));
    }

    return accelStructBuf;
}


void TopAccelStructToFile(Platform* platform,
    TopAccelStruct accelStruct, const char* path)
{
    AccelStructTop header;
    ReadBuffer(platform, accelStruct, sizeof(AccelStructTop), &header);

    unsigned char* buffer = (unsigned char*) malloc(header.totalBufferSize);
    ReadBuffer(platform, accelStruct, header.totalBufferSize, buffer);

    FILE* fp = fopen(path, "w");

    unsigned int byteWritten = 0;
    while(header.totalBufferSize - byteWritten > 0)
    {
        byteWritten += fwrite(
            buffer + byteWritten, 1,
            header.totalBufferSize - byteWritten, fp);
    }

    free(buffer);
}

void FileToTopAccelStruct(Platform* platform,
    const char* path, TopAccelStruct* accelStruct)
{
    CLContext* ctx = platform->clContext;
    AccelStructTop header;

    FILE* fp = fopen(path, "r");
    unsigned int byteRead = fread(&header, 1, sizeof(AccelStructTop), fp);
    if (byteRead != sizeof(AccelStructTop))
        throw;

    cl_mem accelStructBuf = CL_CHECK2(clCreateBuffer(
        ctx->context, CL_MEM_READ_WRITE, header.totalBufferSize, NULL, &_err));

    rewind(fp);
    unsigned char* buffer = (unsigned char*) malloc(header.totalBufferSize);

    byteRead = 0;
    while (header.totalBufferSize - byteRead > 0)
    {
        byteRead += fread(
            buffer + byteRead, 1,
            header.totalBufferSize - byteRead, fp);
    }

    WriteBuffer(platform, accelStructBuf, header.totalBufferSize, buffer, 0);
    free(buffer);

    *accelStruct = accelStructBuf;
}

} // namespace RD
