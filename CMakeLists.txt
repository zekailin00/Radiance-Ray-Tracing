cmake_minimum_required(VERSION 3.10)
project(ray-tracing)

option(OFF_SCREEN "Running application in off-screen mode" ON)
option(POCL_SUPPORT "Use pocl as the OpenCL runtime" ON)
option(IMAGE_SUPPORT "Support for texture sampling" OFF)

if (OFF_SCREEN)
    add_definitions(-DOFF_SCREEN)
endif()

if (POCL_SUPPORT)
    add_definitions(-DPOCL_SUPPORT)
endif()

if (IMAGE_SUPPORT)
    add_definitions(-DIMAGE_SUPPORT)
endif()

if(NOT POCL_SUPPORT)
    find_package(OpenCL REQUIRED)
else()
    add_library(pocl_runtime SHARED IMPORTED)
    set_property(TARGET pocl_runtime PROPERTY
        IMPORTED_LOCATION "/scratch/zekailin00/pocl2/build_rt/drops/lib/libOpenCL.so"
    )

    add_library(OpenCL INTERFACE)
    target_link_libraries(OpenCL INTERFACE
        pocl_runtime
    )
    target_include_directories(OpenCL INTERFACE
        "/scratch/zekailin00/pocl2/build_rt/drops/include"
    )
    set(OpenCL_LIBRARY OpenCL)
endif()

add_subdirectory(external/assimp)

add_subdirectory(radiance)
if (NOT POCL_SUPPORT OR NOT OFF_SCREEN)
    add_subdirectory(external/imgui)
    add_subdirectory(visualization)
endif()
add_subdirectory(tools)
add_subdirectory(samples)
