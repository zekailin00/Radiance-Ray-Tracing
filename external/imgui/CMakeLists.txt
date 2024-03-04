

file(GLOB IMGUI_SRC "*.cpp")
file(GLOB IMGUI_HEADER "*.h")

message("-- ImGUI sources: ${IMGUI_SRC}")
message("-- ImGUI headers: ${IMGUI_HEADER}")

add_library(imgui
    ${IMGUI_SRC}
    ${IMGIU_HEADER}
)

target_include_directories(imgui PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}
)