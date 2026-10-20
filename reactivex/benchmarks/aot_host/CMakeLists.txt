cmake_minimum_required(VERSION 3.20)
project(rx_extended_benchmarks LANGUAGES CXX)
find_package(DAS REQUIRED)
if(NOT RX_ROOT)
  message(FATAL_ERROR "Pass -DRX_ROOT=<ReactiveX directory or baseline snapshot>")
endif()
get_filename_component(sdk "${DAS_DIR}/../../.." ABSOLUTE)
get_filename_component(host "${CMAKE_CURRENT_SOURCE_DIR}/../../../computation_expressions/aot_host" ABSOLUTE)
set(script "${RX_ROOT}/benchmarks/benchmark_extended.das")
set(dependencies "${script}" "${RX_ROOT}/lib/reactivex.das"
  "${RX_ROOT}/lib/rx_scheduler.das" "${RX_ROOT}/lib/rx_payload_checks.das"
  "${RX_ROOT}/benchmarks/extended_workloads.das")
file(MAKE_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/generated")
set(main_cpp "${CMAKE_CURRENT_BINARY_DIR}/generated/benchmark.cpp")
add_custom_command(OUTPUT "${main_cpp}"
  COMMAND $<TARGET_FILE:DAS::daslang> -aot "${script}" "${main_cpp}"
  DEPENDS ${dependencies} VERBATIM)
set(generated "${main_cpp}")
foreach(module IN ITEMS lib/reactivex lib/rx_scheduler benchmarks/extended_workloads)
  string(REPLACE "/" "_" stem "${module}")
  set(cpp "${CMAKE_CURRENT_BINARY_DIR}/generated/${stem}.cpp")
  add_custom_command(OUTPUT "${cpp}"
    COMMAND $<TARGET_FILE:DAS::daslang> -aotlib "${RX_ROOT}/${module}.das" "${cpp}"
    DEPENDS ${dependencies} VERBATIM)
  list(APPEND generated "${cpp}")
endforeach()
add_executable(rx_extended "${host}/main.cpp" ${generated})
target_link_libraries(rx_extended PRIVATE DAS::libDaScriptDyn)
target_compile_definitions(rx_extended PRIVATE DAS_MOD_EXPORTS)
target_compile_features(rx_extended PRIVATE cxx_std_17)
if(MSVC)
  target_compile_options(rx_extended PRIVATE /bigobj /wd4005 "/FI${host}/recover_064.h")
else()
  target_compile_options(rx_extended PRIVATE -include "${host}/recover_064.h")
endif()
add_custom_command(TARGET rx_extended POST_BUILD
  COMMAND ${CMAKE_COMMAND} -E copy_if_different "${sdk}/bin/libDaScriptDyn.dll" "$<TARGET_FILE_DIR:rx_extended>"
  COMMAND ${CMAKE_COMMAND} -E copy_if_different "${sdk}/bin/libDaScriptDyn_runtime.dll" "$<TARGET_FILE_DIR:rx_extended>")
