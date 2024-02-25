

add_library(radiance
    ${CMAKE_CURRENT_SOURCE_DIR}/src/bvh.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/src/radiance.cpp
)

target_link_libraries(radiance PUBLIC
    ${OpenCL_LIBRARY}
    assimp
)

target_include_directories(radiance PUBLIC
    ${CMAKE_SOURCE_DIR}/external
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_CURRENT_SOURCE_DIR}/include
    ${CMAKE_CURRENT_SOURCE_DIR}/src
)