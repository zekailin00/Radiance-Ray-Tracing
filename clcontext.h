
// OpenCL includes
#include <CL/cl.h>

// C standard includes
#include <stdio.h>
#include <cstdlib>
#include <chrono>
#include <sys/stat.h>


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
    exit(-1);                                                           \
} while (0)

#define CL_CHECK2(_expr)                                                \
({                                                                      \
    cl_int _err = CL_INVALID_VALUE;                                     \
    decltype(_expr) _ret = _expr;                                       \
    if (_err != CL_SUCCESS) {                                           \
        printf("OpenCL Error: '%s' returned %d at line %d!\n", #_expr, (int)_err, __LINE__); \
    ctx->Cleanup();			                                            \
        exit(-1);                                                       \
    }                                                                   \
    _ret;                                                               \
})

void CLContext::Cleanup() {
    if (commandQueue) clReleaseCommandQueue(commandQueue);
    if (context) clReleaseContext(context);
    if (device_id) clReleaseDevice(device_id);
}

CLContext* CLContext::GetCLContext()
{
    CLContext* ctx = new CLContext();

    CL_CHECK(clGetPlatformIDs(1, &ctx->platform_id, NULL));
    CL_CHECK(clGetDeviceIDs(ctx->platform_id, CL_DEVICE_TYPE_DEFAULT, 1, &ctx->device_id, NULL));

    //////////////////////////////  Platform Info  ////////////////////////////////
    char buffer[256];
    size_t retSize;

    CL_CHECK(clGetPlatformInfo(ctx->platform_id, CL_PLATFORM_NAME, 256, buffer, &retSize));
    printf("CL_PLATFORM_NAME: %s\n", buffer);
    CL_CHECK(clGetPlatformInfo(ctx->platform_id, CL_PLATFORM_VENDOR, 256, buffer, &retSize));
    printf("CL_PLATFORM_VENDOR: %s\n", buffer);
    CL_CHECK(clGetPlatformInfo(ctx->platform_id, CL_PLATFORM_PROFILE, 256, buffer, &retSize));
    printf("CL_PLATFORM_PROFILE: %s\n", buffer);

    CL_CHECK(clGetDeviceInfo(ctx->device_id, CL_DEVICE_VENDOR, 256, buffer, &retSize));
    printf("CL_DEVICE_VENDOR: %s\n", buffer);
    //////////////////////////////////////////////////////////////////////////////

    printf("Create context\n");
    ctx->context = CL_CHECK2(clCreateContext(NULL, 1, &ctx->device_id, NULL, NULL,  &_err));
    ctx->commandQueue = CL_CHECK2(clCreateCommandQueue(ctx->context, ctx->device_id, 0, &_err));  

    fflush(stdout);
    return ctx;
}

static int read_kernel_file_bin(const char* filename, uint8_t** data, size_t* size) {
  if (nullptr == filename || nullptr == data || 0 == size)
      return -1;
  
  printf("File name: %s\n", filename); fflush(stdout);
  FILE* fp = fopen(filename, "r");

  if (NULL == fp) {

      fprintf(stderr, "Failed to load kernel.");
      return -1;
  }

  long fsize;
  {
      struct stat buffer;
      int         status;
      status = stat(filename, &buffer);
      fsize = buffer.st_size;
  }
  fsize = 100000;

  rewind(fp);

  *data = (uint8_t*)malloc(fsize);
  *size = fread(*data, 1, fsize, fp);

  printf("File size: %ld\n", *size); fflush(stdout);
  fclose(fp);
  
  return 0;
}


static int read_kernel_file_str(const char* filename, char** data, size_t* size) {
  if (nullptr == filename || nullptr == data || 0 == size)
      return -1;
  
  printf("File name: %s\n", filename); fflush(stdout);
  FILE* fp = fopen(filename, "r");

  if (NULL == fp) {
      fprintf(stderr, "Failed to load kernel.");
      return -1;
  }

  long fsize;
  {
      struct stat buffer;
      int         status;
      status = stat(filename, &buffer);
      fsize = buffer.st_size;
  }
//   fsize = 100000;

  rewind(fp);

  *data = (char*)malloc(fsize);
  *size = fread(*data, 1, fsize, fp);

  printf("File size: %ld\n", *size); fflush(stdout);
  fclose(fp);
  
  return 0;
}