
add_executable(modelViewer modelViewer.cpp)
target_link_libraries(modelViewer assimp)
target_include_directories(modelViewer PUBLIC ${CMAKE_SOURCE_DIR}/external)