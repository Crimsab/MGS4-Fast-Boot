cmake_minimum_required(VERSION 3.24)

file(READ "${CMAKE_CURRENT_SOURCE_DIR}/release.json" RELEASE_JSON)
string(JSON PRODUCT_VERSION GET "${RELEASE_JSON}" version)
string(JSON LAUNCHER_SHA256 GET "${RELEASE_JSON}" launcherSha256)
string(JSON GAME_SHA256 GET "${RELEASE_JSON}" gameSha256)

project(MGS4FastBoot VERSION ${PRODUCT_VERSION} LANGUAGES C CXX)

if(NOT WIN32 OR NOT MSVC OR NOT CMAKE_SIZEOF_VOID_P EQUAL 8)
    message(FATAL_ERROR "MGS4 Fast Boot supports only Windows x64 builds with MSVC.")
endif()

if(NOT DEFINED MINHOOK_DIR)
    message(FATAL_ERROR "Set MINHOOK_DIR to the MinHook v1.3.4 source root.")
endif()

add_library(minhook STATIC
    "${MINHOOK_DIR}/src/buffer.c"
    "${MINHOOK_DIR}/src/hook.c"
    "${MINHOOK_DIR}/src/trampoline.c"
    "${MINHOOK_DIR}/src/hde/hde64.c"
)
target_include_directories(minhook PUBLIC "${MINHOOK_DIR}/include")
target_include_directories(minhook PRIVATE "${MINHOOK_DIR}/src" "${MINHOOK_DIR}/src/hde")

configure_file(
    "${CMAKE_CURRENT_SOURCE_DIR}/cmake/release_config.h.in"
    "${CMAKE_CURRENT_BINARY_DIR}/generated/release_config.h"
    @ONLY
)

add_library(MGS4FastBoot SHARED src/fastboot.cpp)
target_compile_features(MGS4FastBoot PRIVATE cxx_std_17)
target_compile_definitions(MGS4FastBoot PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
target_include_directories(MGS4FastBoot PRIVATE "${CMAKE_CURRENT_BINARY_DIR}/generated")
target_link_libraries(MGS4FastBoot PRIVATE minhook bcrypt shell32)

if(MSVC)
    set_property(TARGET minhook PROPERTY MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
    set_property(TARGET MGS4FastBoot PROPERTY MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
    target_compile_options(MGS4FastBoot PRIVATE /W4 /WX /permissive-)
    target_link_options(MGS4FastBoot PRIVATE /Brepro)
endif()

set_target_properties(MGS4FastBoot PROPERTIES PREFIX "" SUFFIX ".asi")
