cmake_minimum_required(VERSION 3.20)
project(derive_aot LANGUAGES CXX)
find_package(DAS REQUIRED)
get_filename_component(DAS_SDK_ROOT "${DAS_DIR}/../../.." ABSOLUTE)
if(NOT SCRIPT_MANIFEST)
  message(FATAL_ERROR "Pass -DSCRIPT_MANIFEST=<absolute script paths>")
endif()
file(STRINGS "${SCRIPT_MANIFEST}" scripts)
set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "${SCRIPT_MANIFEST}")
file(GLOB dependencies "${CMAKE_CURRENT_SOURCE_DIR}/../lib/*.das" "${CMAKE_CURRENT_SOURCE_DIR}/../examples/*.das")
set(generated)
file(MAKE_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/generated")
foreach(script IN LISTS scripts)
  get_filename_component(stem "${script}" NAME_WE)
  set(cpp "${CMAKE_CURRENT_BINARY_DIR}/generated/${stem}.cpp")
  add_custom_command(OUTPUT "${cpp}"
    COMMAND $<TARGET_FILE:DAS::daslang> -aot "${script}" "${cpp}"
    DEPENDS "${script}" ${dependencies} VERBATIM)
  list(APPEND generated "${cpp}")
endforeach()
# Non-generic runtime helpers and imported generated model functions.
foreach(script IN ITEMS "${CMAKE_CURRENT_SOURCE_DIR}/../lib/derive_runtime.das" "${CMAKE_CURRENT_SOURCE_DIR}/../examples/game_model.das" "${CMAKE_CURRENT_SOURCE_DIR}/../lib/derive_validation.das" "${CMAKE_CURRENT_SOURCE_DIR}/../examples/validation_model.das" "${CMAKE_CURRENT_SOURCE_DIR}/../lib/derive_json_runtime.das" "${CMAKE_CURRENT_SOURCE_DIR}/../examples/json_game_model.das" "${CMAKE_CURRENT_SOURCE_DIR}/../lib/derive_types.das" "${CMAKE_CURRENT_SOURCE_DIR}/../examples/json_presence_model.das" "${CMAKE_CURRENT_SOURCE_DIR}/../examples/enum_variant_model.das" "${CMAKE_CURRENT_SOURCE_DIR}/../examples/collection_validation_model.das" "${CMAKE_CURRENT_SOURCE_DIR}/../examples/clone_model.das" "${CMAKE_CURRENT_SOURCE_DIR}/../lib/derive_diff.das" "${CMAKE_CURRENT_SOURCE_DIR}/../examples/diff_model.das" "${CMAKE_CURRENT_SOURCE_DIR}/../lib/derive_patch.das" "${CMAKE_CURRENT_SOURCE_DIR}/../examples/patch_model.das" "${CMAKE_CURRENT_SOURCE_DIR}/../lib/derive_builder.das" "${CMAKE_CURRENT_SOURCE_DIR}/../examples/builder_model.das" "${CMAKE_CURRENT_SOURCE_DIR}/../examples/schema_model.das" "${CMAKE_CURRENT_SOURCE_DIR}/../examples/workflow_model.das" "${CMAKE_CURRENT_SOURCE_DIR}/../lib/derive_optics_runtime.das" "${CMAKE_CURRENT_SOURCE_DIR}/../examples/optics_model.das" "${CMAKE_CURRENT_SOURCE_DIR}/../examples/prism_model.das")
  get_filename_component(stem "${script}" NAME_WE)
  set(cpp "${CMAKE_CURRENT_BINARY_DIR}/generated/lib_${stem}.cpp")
  add_custom_command(OUTPUT "${cpp}"
    COMMAND $<TARGET_FILE:DAS::daslang> -aotlib "${script}" "${cpp}"
    DEPENDS "${script}" ${dependencies} VERBATIM)
  list(APPEND generated "${cpp}")
endforeach()
# Runtime functions from the standard JSON parser and its dependencies.
foreach(module IN ITEMS json json_boost strings_boost utf8_utils)
  set(script "${DAS_SDK_ROOT}/daslib/${module}.das")
  set(cpp "${CMAKE_CURRENT_BINARY_DIR}/generated/daslib_${module}.cpp")
  add_custom_command(OUTPUT "${cpp}"
    COMMAND $<TARGET_FILE:DAS::daslang> -aotlib "${script}" "${cpp}"
    DEPENDS "${script}" VERBATIM)
  list(APPEND generated "${cpp}")
endforeach()
add_executable(derive_aot main.cpp ${generated})
target_link_libraries(derive_aot PRIVATE DAS::libDaScriptDyn)
target_compile_definitions(derive_aot PRIVATE DAS_MOD_EXPORTS)
target_compile_features(derive_aot PRIVATE cxx_std_17)
if(MSVC)
  target_compile_options(derive_aot PRIVATE /bigobj /wd4005 "/FI${CMAKE_CURRENT_SOURCE_DIR}/recover_064.h")
else()
  target_compile_options(derive_aot PRIVATE -include "${CMAKE_CURRENT_SOURCE_DIR}/recover_064.h")
endif()
add_custom_command(TARGET derive_aot POST_BUILD
  COMMAND ${CMAKE_COMMAND} -E copy_if_different "${DAS_SDK_ROOT}/bin/libDaScriptDyn.dll" "$<TARGET_FILE_DIR:derive_aot>"
  COMMAND ${CMAKE_COMMAND} -E copy_if_different "${DAS_SDK_ROOT}/bin/libDaScriptDyn_runtime.dll" "$<TARGET_FILE_DIR:derive_aot>")
