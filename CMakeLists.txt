# SPDX-License-Identifier: GPL-3.0-or-later
# ------------------------------------------------------------
#  此为新月杀的项目组织文件，采用CMake+QT
# 2022-01-24 新建文件夹 2023-02-21 发布v0.0.1版本
# ------------------------------------------------------------

cmake_minimum_required(VERSION 3.22)

project(FreeKill VERSION 0.5.25)
if (IOS)
  # src/platform/ioshelper.mm is Objective-C++.
  enable_language(OBJCXX)
endif()
add_definitions(-DFK_VERSION=\"${CMAKE_PROJECT_VERSION}\")

set(FK_QT_COMPONENTS Network)

if (NOT DEFINED FK_SERVER_ONLY)
  list(APPEND FK_QT_COMPONENTS
    Gui
    GuiPrivate
    Qml
    Quick
    Widgets
    Multimedia
    QuickControls2
    Concurrent
    ShaderTools
  )
  if (NOT IOS)
    # Translators are build-time host tools; on iOS the .qm files are shipped
    # pre-built in runtime/ instead of invoking lrelease for the target.
    list(APPEND FK_QT_COMPONENTS LinguistTools)
  endif()
else ()
  add_definitions(-DFK_SERVER_ONLY)
endif()

find_package(Qt6 REQUIRED COMPONENTS ${FK_QT_COMPONENTS})

if (DEFINED RPC_DEBUG)
  add_definitions(-DRPC_DEBUG)
endif()

set(CMAKE_COLOR_DIAGNOSTICS ON)

if (NOT IOS)
  find_package(OpenSSL)
  find_package(SQLite3)
endif()

set(CMAKE_AUTOMOC ON)
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED True)
set(REQUIRED_QT_VERSION "6.8")

include_directories(include)
include_directories(include/lua)
include_directories(include/libgit2)
include_directories(src)
if (IOS AND DEFINED FK_IOS_DEPS)
  include_directories(${FK_IOS_DEPS}/include)
  include_directories(${FK_IOS_DEPS}/include/lua)
  set(LUA_INCLUDE_DIR ${FK_IOS_DEPS}/include/lua)
endif()
# 谁加的，把我Github Action搞坏了，如果是MacOS的话麻烦加if吧我现在忙着调CI没空管
include_directories(${LUA_INCLUDE_DIR})
# include_directories(${LIBGIT2_INCLUDE_DIRS})

if (${CMAKE_BUILD_TYPE}0 STREQUAL "Debug0")
  # add_compile_options(-fsanitize=address -fsanitize=undefined)
  # add_link_options(-fsanitize=address -fsanitize=undefined)
endif ()

if (DEFINED FK_USE_JEMALLOC)
  find_package(PkgConfig REQUIRED)
  pkg_check_modules (JEMALLOC jemalloc)

  pkg_search_module(JEMALLOC REQUIRED jemalloc)
  include_directories(${JEMALLOC_INCLUDE_DIRS})
endif ()

qt_add_executable(FreeKill)
link_directories(${LIBGIT2_LIBRARY_DIRS})

if (NOT DEFINED FK_SERVER_ONLY)
  if (NOT IOS)
    qt_add_translations(FreeKill
      TS_FILES lang/zh_CN.ts
      QM_FILES_OUTPUT_VARIABLE zh_CN.qm

      TS_FILES lang/en_US.ts
      QM_FILES_OUTPUT_VARIABLE en_US.qm

      TS_FILES lang/vi_VN.ts
      QM_FILES_OUTPUT_VARIABLE vi_VN.qm
    )
  endif()
endif()

add_custom_command(
  TARGET FreeKill
  POST_BUILD
  COMMENT "Generating version file fk_ver"
  COMMAND echo ${CMAKE_PROJECT_VERSION} > ${PROJECT_SOURCE_DIR}/fk_ver
  COMMAND ${PROJECT_SOURCE_DIR}/genfkver.sh
)

if (NOT DEFINED FK_SERVER_ONLY)
  # 部署 Spine QML 模块到 build/qml/Spine（与 Qt 模块并列，供 IDE 解析 import Spine 1.0）
  # 用 ALL 自定义目标：每次构建都执行，避免 QML 文件修改后因 exe 未重链而不更新
  add_custom_target(deploy_spine_qml ALL
    COMMAND ${CMAKE_COMMAND} -E copy_directory
      "${PROJECT_SOURCE_DIR}/src/ui/spine/Spine"
      "${PROJECT_BINARY_DIR}/qml/Spine"
    COMMENT "Deploying Spine QML module to build/qml/Spine"
  )
endif ()

add_subdirectory(src)

if (IOS)
  # -------------------------------------------------------------------------
  # iOS application bundle
  # -------------------------------------------------------------------------
  set(FK_IOS_BUNDLE_ID "com.cui.freekill.ios" CACHE STRING "iOS bundle identifier")
  set(FK_IOS_DEPLOYMENT_TARGET "16.0" CACHE STRING "Minimum iOS version")

  set_target_properties(FreeKill PROPERTIES
    MACOSX_BUNDLE TRUE
    MACOSX_BUNDLE_INFO_PLIST "${CMAKE_CURRENT_SOURCE_DIR}/ios/Info.plist.in"
    MACOSX_BUNDLE_BUNDLE_NAME "FreeKill"
    MACOSX_BUNDLE_BUNDLE_VERSION "${CMAKE_PROJECT_VERSION}"
    MACOSX_BUNDLE_SHORT_VERSION_STRING "${CMAKE_PROJECT_VERSION}"
    MACOSX_BUNDLE_GUI_IDENTIFIER "${FK_IOS_BUNDLE_ID}"
    XCODE_ATTRIBUTE_PRODUCT_BUNDLE_IDENTIFIER "${FK_IOS_BUNDLE_ID}"
    XCODE_ATTRIBUTE_IPHONEOS_DEPLOYMENT_TARGET "${FK_IOS_DEPLOYMENT_TARGET}"
    XCODE_ATTRIBUTE_TARGETED_DEVICE_FAMILY "1,2"
    XCODE_ATTRIBUTE_SUPPORTED_PLATFORMS "iphoneos"
    XCODE_ATTRIBUTE_ARCHS "arm64"
    XCODE_ATTRIBUTE_ONLY_ACTIVE_ARCH "NO"
    XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED "NO"
    XCODE_ATTRIBUTE_CODE_SIGNING_REQUIRED "NO"
    XCODE_ATTRIBUTE_CODE_SIGN_IDENTITY ""
  )

  # Runtime payload: Fk / LunarLtk / card-counter / packages / lua / fonts ...
  # The app copies this read-only bundle payload into Documents/FreeKill on
  # first launch, so the engine can keep using relative paths.
  add_custom_command(TARGET FreeKill POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_directory
      "${CMAKE_CURRENT_SOURCE_DIR}/runtime"
      "$<TARGET_BUNDLE_DIR:FreeKill>/res"
    COMMAND ${CMAKE_COMMAND} -E copy_directory
      "${CMAKE_CURRENT_SOURCE_DIR}/ios/bundle"
      "$<TARGET_BUNDLE_DIR:FreeKill>"
    COMMAND xcrun --sdk iphoneos ibtool --compile
      --minimum-deployment-target "${FK_IOS_DEPLOYMENT_TARGET}"
      --target-device iphone --target-device ipad
      "$<TARGET_BUNDLE_DIR:FreeKill>/LaunchScreen.storyboardc"
      "${CMAKE_CURRENT_SOURCE_DIR}/ios/LaunchScreen.storyboard"
    COMMENT "Bundling FreeKill runtime, icons and launch screen"
  )

  # A tiny QML module whose only job is to make qmlimportscanner see every
  # Qt module used by the loose QML tree. On a static Qt build this causes
  # qt_import_qml_plugins to link the matching QML plugins.
  qt_add_qml_module(FreeKill
    URI FreeKillIosImports
    VERSION 1.0
    QML_FILES "${CMAKE_CURRENT_SOURCE_DIR}/ios/IosImports.qml"
    NO_PLUGIN
  )
  qt_import_qml_plugins(FreeKill)
endif()

if (DEFINED FK_TESTS)
enable_testing()
add_subdirectory(test)
endif ()
