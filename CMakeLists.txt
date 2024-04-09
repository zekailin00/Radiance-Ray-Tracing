cmake_minimum_required(VERSION 3.10)
project(ray-tracing)


find_package(OpenCL REQUIRED)

add_subdirectory(external/assimp)
add_subdirectory(external/imgui)

add_subdirectory(radiance)
add_subdirectory(visualization)
add_subdirectory(samples)
add_subdirectory(tools)