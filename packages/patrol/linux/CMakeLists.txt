cmake_minimum_required(VERSION 3.10)

set(PROJECT_NAME "patrol")
project(${PROJECT_NAME} LANGUAGES CXX)

set(PLUGIN_NAME "${PROJECT_NAME}_plugin")

add_library(${PLUGIN_NAME} SHARED
  "patrol_plugin.cc"
)

apply_standard_settings(${PLUGIN_NAME})

set_target_properties(${PLUGIN_NAME} PROPERTIES
  CXX_VISIBILITY_PRESET hidden
)

target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)

target_include_directories(${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include"
)

target_link_libraries(${PLUGIN_NAME} PRIVATE flutter)
target_link_libraries(${PLUGIN_NAME} PRIVATE PkgConfig::GTK)

# AT-SPI2 for accessibility-based native automation
pkg_check_modules(ATSPI REQUIRED atspi-2)
target_include_directories(${PLUGIN_NAME} PRIVATE ${ATSPI_INCLUDE_DIRS})
target_link_libraries(${PLUGIN_NAME} PRIVATE ${ATSPI_LIBRARIES})
