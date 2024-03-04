

set(OpenGL_GL_PREFERENCE "GLVND")
find_package(glfw3 3.3 REQUIRED)
find_package(OpenGL REQUIRED)

add_executable(inspector
    ${CMAKE_CURRENT_SOURCE_DIR}/main.cpp
)

target_link_libraries(inspector
    OpenGL::GL
    imgui
    glfw
)