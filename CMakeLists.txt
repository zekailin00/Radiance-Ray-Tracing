cmake_minimum_required(VERSION 3.10)
project(ray-tracing)


find_package(OpenCL REQUIRED)

add_subdirectory(external/assimp)
add_subdirectory(external/imgui)

add_subdirectory(radiance)
add_subdirectory(samples)
add_subdirectory(visualization)

# add_executable(example
#     main.cpp
# )

# target_include_directories(example PUBLIC
#     ${CMAKE_CURRENT_SOURCE_DIR}
#     external
#     .
#     # external/assimp/includeb
# )

# target_link_libraries(example
#     ${OpenCL_LIBRARY}
#     assimp
# )
# set(OpenGL_GL_PREFERENCE "GLVND")
# find_package(OpenGL REQUIRED)
# find_package(glfw3 REQUIRED)

# add_executable(visualization
#     viz.cpp
# )

# target_include_directories(visualization PUBLIC
#     ${OPENGL_INCLUDE_DIRS} 
# )

# target_link_libraries(visualization
#     ${OPENGL_LIBRARIES}
#     glad
#     glfw
# )

# message("-- libraries:" ${OPENGL_LIBRARIES})


# add_subdirectory(radiance)

# target_link_libraries(example

# )