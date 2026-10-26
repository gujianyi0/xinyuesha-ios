cmake_minimum_required(VERSION 3.21)
project(QtPickerHarness LANGUAGES CXX OBJCXX)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_AUTOMOC ON)
find_package(Qt6 6.8 REQUIRED COMPONENTS Quick QuickControls2)
qt_add_executable(QtPickerHarness MANUAL_FINALIZATION
  main.mm bridge.h ../../src/platform/iosbackgroundpicker.mm)
qt_add_qml_module(QtPickerHarness URI PickerHarness VERSION 1.0 QML_FILES Main.qml)
target_link_libraries(QtPickerHarness PRIVATE Qt6::Quick Qt6::QuickControls2
  "-framework PhotosUI" "-framework UIKit" "-framework ImageIO" "-framework CoreGraphics")
target_compile_options(QtPickerHarness PRIVATE "$<$<COMPILE_LANGUAGE:OBJCXX>:-fobjc-arc>")
set_target_properties(QtPickerHarness PROPERTIES
  MACOSX_BUNDLE TRUE
  MACOSX_BUNDLE_GUI_IDENTIFIER com.cui.freekill.tests.qtpicker
  MACOSX_BUNDLE_INFO_PLIST "${CMAKE_CURRENT_SOURCE_DIR}/Info.plist"
  XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED NO)
qt_finalize_executable(QtPickerHarness)
