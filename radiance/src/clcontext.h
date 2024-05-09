#pragma once

// OpenCL includes
#include <CL/cl.h>

// C standard includes
#include <stdio.h>
#include <cstdlib>
#include <chrono>
#include <sys/stat.h>

namespace RD
{

struct CLContext
{
public:
    cl_platform_id platform_id = NULL;
    cl_device_id device_id = NULL;
    cl_context context = NULL;
    cl_command_queue commandQueue = NULL;

    static CLContext* GetCLContext();
    void Cleanup();
};

#define CL_CHECK(_expr)                                                 \
do {                                                                    \
    cl_int _err = _expr;                                                \
    if (_err == CL_SUCCESS)                                             \
        break;                                                          \
    printf("OpenCL Error: '%s' returned %d!\n", #_expr, (int)_err);     \
    ctx->Cleanup();			                                            \
    throw;                                                           \
} while (0)

#define CL_CHECK2(_expr)                                                \
({                                                                      \
    cl_int _err = CL_INVALID_VALUE;                                     \
    decltype(_expr) _ret = _expr;                                       \
    if (_err != CL_SUCCESS) {                                           \
        printf("OpenCL Error: '%s' returned %d at line %d!\n", #_expr, (int)_err, __LINE__); \
    ctx->Cleanup();			                                            \
        throw;                                                       \
    }                                                                   \
    _ret;                                                               \
})

int read_kernel_file_bin(const char* filename, uint8_t** data, size_t* size);
int read_kernel_file_str(const char* filename, char** data, size_t* size);

} // namespace RD
