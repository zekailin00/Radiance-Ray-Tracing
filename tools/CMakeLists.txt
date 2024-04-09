
add_executable(modelViewer modelViewer.cpp)
target_link_libraries(modelViewer assimp)
target_include_directories(modelViewer PUBLIC ${CMAKE_SOURCE_DIR}/external)

add_library(sceneLoader sceneBuilder.cpp sceneBuilder.h)
target_link_libraries(sceneLoader assimp radiance)
target_include_directories(sceneLoader PUBLIC ${CMAKE_SOURCE_DIR}/external .)