

set(OpenGL_GL_PREFERENCE "GLVND")
find_package(glfw3 3.3 REQUIRED)
find_package(OpenGL REQUIRED)

add_library(inspector
    ${CMAKE_CURRENT_SOURCE_DIR}/inspector.cpp
)

target_include_directories(inspector PUBLIC
    ${CMAKE_SOURCE_DIR}/external
    ${CMAKE_CURRENT_SOURCE_DIR}
)

target_link_libraries(inspector
    OpenGL::GL
    imgui
    glfw
)