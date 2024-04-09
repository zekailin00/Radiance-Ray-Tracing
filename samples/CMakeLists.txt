

add_executable(sample1
    sample1.cpp
)

target_link_libraries(sample1 PUBLIC
    radiance
    inspector
    sceneLoader
)

add_executable(sample2
    sample2.cpp
)

target_link_libraries(sample2 PUBLIC
    radiance
    inspector
)