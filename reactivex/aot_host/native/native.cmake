if(NOT WIN32 OR NOT MSVC)
  message(FATAL_ERROR "Native integration host currently requires Windows/MSVC SDK")
endif()
if(NOT EXISTS "${LIBHV_SOURCE_DIR}/CMakeLists.txt")
  message(FATAL_ERROR "Pass the pinned libhv headers source via LIBHV_SOURCE_DIR")
endif()
# Only configure/copy headers. The SDK's original shared module performs I/O.
set(WITH_OPENSSL OFF CACHE BOOL "" FORCE)
set(BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(BUILD_UNITTEST OFF CACHE BOOL "" FORCE)
set(BUILD_SHARED OFF CACHE BOOL "" FORCE)
set(BUILD_STATIC ON CACHE BOOL "" FORCE)
add_subdirectory("${LIBHV_SOURCE_DIR}" "${CMAKE_CURRENT_BINARY_DIR}/hv-headers" EXCLUDE_FROM_ALL)
set(overlay "${CMAKE_CURRENT_BINARY_DIR}/native-sdk")
file(MAKE_DIRECTORY "${overlay}/include" "${overlay}/modules/dasHV/src")
configure_file("${CMAKE_CURRENT_LIST_DIR}/aot_hv.h" "${overlay}/modules/dasHV/src/aot_hv.h" COPYONLY)
configure_file("${CMAKE_CURRENT_LIST_DIR}/native_binding.h" "${overlay}/modules/dasHV/src/native_binding.h" COPYONLY)
configure_file("${CMAKE_CURRENT_LIST_DIR}/native_types.h" "${overlay}/modules/dasHV/src/native_types.h" COPYONLY)
target_compile_options(reactivex_aot PRIVATE "/FI${CMAKE_CURRENT_LIST_DIR}/native_glfw.h")
target_include_directories(reactivex_aot PRIVATE "${overlay}/include"
  "${LIBHV_SOURCE_DIR}/include"
  "${DAS_SDK_ROOT}/modules/dasGlfw/glfw_dyn/Release/include")
target_compile_definitions(reactivex_aot PRIVATE GLFW_INCLUDE_NONE)
target_link_libraries(reactivex_aot PRIVATE
  "${DAS_SDK_ROOT}/modules/dasGlfw/dasModuleGlfw.lib"
  "${DAS_SDK_ROOT}/modules/dasGlfw/glfw_dyn/Release/lib/glfw3dll.lib")
# The runner puts the original SDK directories on PATH. Do not copy a second
# module DLL: its callback globals/handle registry must have one identity.
