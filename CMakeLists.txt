cmake_minimum_required(VERSION 3.24)
project(MGS4FastBoot LANGUAGES C CXX)

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

add_library(MGS4FastBoot SHARED fastboot.cpp)
target_compile_features(MGS4FastBoot PRIVATE cxx_std_17)
target_compile_definitions(MGS4FastBoot PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
target_link_libraries(MGS4FastBoot PRIVATE minhook bcrypt shell32)

if(MSVC)
    set_property(TARGET minhook PROPERTY MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
    set_property(TARGET MGS4FastBoot PROPERTY MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
endif()

set_target_properties(MGS4FastBoot PROPERTIES PREFIX "" SUFFIX ".asi")
