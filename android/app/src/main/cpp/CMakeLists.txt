cmake_minimum_required(VERSION 3.22.1)
project(biomatch_native LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

# Directory containing onnxruntime_c_api.h and onnxruntime_cxx_api.h
include_directories(${CMAKE_CURRENT_SOURCE_DIR}/include)

# Import prebuilt libonnxruntime.so per Android ABI if present
if(EXISTS ${CMAKE_CURRENT_SOURCE_DIR}/../jniLibs/${ANDROID_ABI}/libonnxruntime.so)
    add_library(onnxruntime SHARED IMPORTED)
    set_target_properties(
        onnxruntime
        PROPERTIES IMPORTED_LOCATION
        ${CMAKE_CURRENT_SOURCE_DIR}/../jniLibs/${ANDROID_ABI}/libonnxruntime.so
    )
endif()

# Build Kelasagara BioMatch Native FFI Library
add_library(
    biomatch_native
    SHARED
    biomatch_ffi_bridge.cpp
    biomatch_native.cpp
    biomatch_align_ffi.cpp
)

# Standalone aligner library for Dart FFI
add_library(
    biomatch_align
    SHARED
    biomatch_align_ffi.cpp
)
target_include_directories(biomatch_align PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})
target_compile_options(biomatch_align PRIVATE -O3)
target_link_options(biomatch_align PRIVATE "-Wl,-z,max-page-size=16384")

# Architecture-specific SIMD optimizations for budget ARM processors
if(${ANDROID_ABI} STREQUAL "arm64-v8a")
    target_compile_options(biomatch_native PRIVATE
        -O3
        -march=armv8-a+simd
        -ftree-vectorize
        -funroll-loops
    )
elseif(${ANDROID_ABI} STREQUAL "armeabi-v7a")
    target_compile_options(biomatch_native PRIVATE
        -O3
        -mfpu=neon
        -mfloat-abi=softfp
        -ftree-vectorize
    )
endif()

# Prevent symbol stripping on FFI entrypoints and enforce 16KB page alignment (Android 15+)
target_link_options(biomatch_native PRIVATE
    "-Wl,-z,max-page-size=16384"
    "-Wl,--gc-sections"
)

find_library(log-lib log)

if(TARGET onnxruntime)
    target_link_libraries(
        biomatch_native
        onnxruntime
        ${log-lib}
    )
else()
    target_link_libraries(
        biomatch_native
        ${log-lib}
    )
endif()

# Build Kelasagara Apex Native Audio & ADPF Engine
add_library(
    kelasagara_audio
    SHARED
    kelasagara_apex_engine.cpp
)

target_link_libraries(
    kelasagara_audio
    ${log-lib}
)
