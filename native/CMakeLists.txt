cmake_minimum_required(VERSION 3.20)

project(luna_thread_runtime C)

option(LUNA_THREAD_ENABLE_OPENMP "Enable OpenMP-backed runtime execution" ON)

if(APPLE AND EXISTS "/opt/homebrew/opt/libomp")
  set(OpenMP_ROOT "/opt/homebrew/opt/libomp")
  set(OpenMP_C_FLAGS "-Xpreprocessor -fopenmp -I${OpenMP_ROOT}/include")
  set(OpenMP_C_LIB_NAMES "omp")
  set(OpenMP_omp_LIBRARY "${OpenMP_ROOT}/lib/libomp.dylib")
endif()

add_library(luna_thread_runtime STATIC
  src/runtime.c
)

target_include_directories(luna_thread_runtime
  PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}/include
)

target_compile_features(luna_thread_runtime PUBLIC c_std_11)

if(LUNA_THREAD_ENABLE_OPENMP)
  find_package(OpenMP)
  if(OpenMP_C_FOUND)
    target_link_libraries(luna_thread_runtime PUBLIC OpenMP::OpenMP_C)
    target_compile_definitions(luna_thread_runtime PUBLIC LUNA_THREAD_HAVE_OPENMP=1)
  else()
    message(FATAL_ERROR "OpenMP requested but not found. Install libomp on macOS before native parallel work.")
  endif()
endif()

add_executable(luna_thread_smoke
  tests/smoke.c
)

target_link_libraries(luna_thread_smoke PRIVATE luna_thread_runtime)
