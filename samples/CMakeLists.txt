add_executable(sample1
    sample1.cpp
)

target_link_libraries(sample1 PUBLIC
    radiance
    sceneLoader
)

if (NOT POCL_SUPPORT)
    target_link_libraries(sample1 PUBLIC
        inspector
    )
endif()
