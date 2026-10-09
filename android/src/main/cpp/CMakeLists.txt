cmake_minimum_required(VERSION 3.18)
project(flutter_gguf LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Configure llama.cpp options
set(LLAMA_BUILD_COMMON OFF CACHE BOOL "Build common utils" FORCE)
set(LLAMA_BUILD_TESTS OFF CACHE BOOL "Build tests" FORCE)
set(LLAMA_BUILD_EXAMPLES OFF CACHE BOOL "Build examples" FORCE)
set(LLAMA_BUILD_SERVER OFF CACHE BOOL "Build server" FORCE)
set(BUILD_SHARED_LIBS OFF CACHE BOOL "Build shared libs" FORCE)
set(GGML_OPENMP OFF CACHE BOOL "Disable OpenMP on mobile" FORCE)
set(GGML_LLAMAFILE OFF CACHE BOOL "Disable llamafile SGEMM" FORCE)

# ARM Optimization Flags for Android
if (${ANDROID_ABI} STREQUAL "arm64-v8a")
    add_compile_options(-O3 -march=armv8.2-a+fp16+dotprod)
elseif (${ANDROID_ABI} STREQUAL "armeabi-v7a")
    add_compile_options(-O3 -mfpu=neon)
else()
    add_compile_options(-O3)
endif()

# Add llama.cpp submodule/directory
add_subdirectory(llama.cpp)

# Plugin Bridge Shared Library
add_library(flutter_gguf_plugin SHARED
    flutter_gguf_bridge.cpp
)

target_include_directories(flutter_gguf_plugin PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_CURRENT_SOURCE_DIR}/llama.cpp/include
    ${CMAKE_CURRENT_SOURCE_DIR}/llama.cpp/ggml/include
)

target_link_libraries(flutter_gguf_plugin PRIVATE
    llama
    ggml
    log
)
