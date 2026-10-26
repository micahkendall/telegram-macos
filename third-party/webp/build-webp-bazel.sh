#! /bin/sh

set -ex

set -e

ARCH="$1"

SOURCE_DIR="$2"
BUILD_DIR=$(echo "$(cd "$(dirname "$3")"; pwd -P)/$(basename "$3")")

COMMON_ARGS="-DWEBP_LINK_STATIC=1 -DWEBP_BUILD_CWEBP=0 -DWEBP_BUILD_DWEBP=0 -DWEBP_BUILD_IMG2WEBP=0 -DWEBP_BUILD_ANIM_UTILS=0 -DWEBP_BUILD_GIF2WEBP=0 -DWEBP_BUILD_VWEBP=0 -DWEBP_BUILD_WEBPINFO=0 -DWEBP_BUILD_LIBWEBPMUX=0 -DWEBP_BUILD_WEBPMUX=0 -DWEBP_BUILD_EXTRAS=0"

if [ "${TELEGRAM_CATALYST:-0}" = "1" ] && [ "$ARCH" = "arm64" ]; then
  MACOS_SYSROOT="$(xcrun --sdk macosx --show-sdk-path)"
  export CFLAGS="-Wall --target=arm64-apple-ios15.0-macabi -funwind-tables"
  mkdir -p "$BUILD_DIR/build"
  cd "$BUILD_DIR/build"
  cmake -G "Unix Makefiles" -DCMAKE_SYSTEM_NAME=Darwin \
    -DCMAKE_SYSTEM_PROCESSOR=aarch64 -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_C_COMPILER="$(xcrun --find clang)" -DCMAKE_OSX_SYSROOT="$MACOS_SYSROOT" \
    $COMMON_ARGS ../libwebp
  make -j8
elif [ "$ARCH" = "arm64" ]; then
  IOS_PLATFORMDIR="$(xcode-select -p)/Platforms/iPhoneOS.platform"
  IOS_SYSROOT=($IOS_PLATFORMDIR/Developer/SDKs/iPhoneOS*.sdk)
  export CFLAGS="-Wall -arch arm64 -miphoneos-version-min=13.0 -funwind-tables"

  cd "$BUILD_DIR"
  mkdir build
  cd build

  touch toolchain.cmake
  echo "set(CMAKE_SYSTEM_NAME Darwin)" >> toolchain.cmake
  echo "set(CMAKE_SYSTEM_PROCESSOR aarch64)" >> toolchain.cmake
  echo "set(CMAKE_C_COMPILER $(xcode-select -p)/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang)" >> toolchain.cmake

  cmake -G"Unix Makefiles" -DCMAKE_TOOLCHAIN_FILE=toolchain.cmake -DCMAKE_OSX_SYSROOT=${IOS_SYSROOT[0]} $COMMON_ARGS ../libwebp
  make
elif [ "$ARCH" = "sim_arm64" ]; then
  IOS_PLATFORMDIR="$(xcode-select -p)/Platforms/iPhoneSimulator.platform"
  IOS_SYSROOT=($IOS_PLATFORMDIR/Developer/SDKs/iPhoneSimulator*.sdk)
  export CFLAGS="-Wall -arch arm64 --target=arm64-apple-ios13.0-simulator -miphonesimulator-version-min=13.0 -funwind-tables"

  cd "$BUILD_DIR"
  mkdir build
  cd build

  touch toolchain.cmake
  echo "set(CMAKE_SYSTEM_NAME Darwin)" >> toolchain.cmake
  echo "set(CMAKE_SYSTEM_PROCESSOR aarch64)" >> toolchain.cmake
  echo "set(CMAKE_C_COMPILER $(xcode-select -p)/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang)" >> toolchain.cmake

  cmake -G"Unix Makefiles" -DCMAKE_TOOLCHAIN_FILE=toolchain.cmake -DCMAKE_OSX_SYSROOT=${IOS_SYSROOT[0]} $COMMON_ARGS ../libwebp
  make
elif [ "$ARCH" = "macos_arm64" ]; then
  IOS_PLATFORMDIR="$(xcode-select -p)/Platforms/MacOSX.platform"
  IOS_SYSROOT=($IOS_PLATFORMDIR/Developer/SDKs/MacOSX*.sdk)
  export CFLAGS="-Wall -arch arm64 --target=arm64-apple-macosx14.0 -mmacosx-version-min=14.0 -funwind-tables"

  cd "$BUILD_DIR"
  mkdir build
  cd build

  touch toolchain.cmake
  echo "set(CMAKE_SYSTEM_NAME Darwin)" >> toolchain.cmake
  echo "set(CMAKE_SYSTEM_PROCESSOR aarch64)" >> toolchain.cmake
  echo "set(CMAKE_C_COMPILER $(xcode-select -p)/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang)" >> toolchain.cmake

  cmake -G"Unix Makefiles" -DCMAKE_TOOLCHAIN_FILE=toolchain.cmake -DCMAKE_OSX_SYSROOT=${IOS_SYSROOT[0]} $COMMON_ARGS ../libwebp
  make
elif [ "$ARCH" = "x86_64" ]; then
  IOS_PLATFORMDIR="$(xcode-select -p)/Platforms/iPhoneSimulator.platform"
  IOS_SYSROOT=($IOS_PLATFORMDIR/Developer/SDKs/iPhoneSimulator*.sdk)
  export CFLAGS="-Wall -arch x86_64 -miphoneos-version-min=13.0 -funwind-tables"

  cd "$BUILD_DIR"
  mkdir build
  cd build

  touch toolchain.cmake
  echo "set(CMAKE_SYSTEM_NAME Darwin)" >> toolchain.cmake
  echo "set(CMAKE_SYSTEM_PROCESSOR AMD64)" >> toolchain.cmake
  echo "set(CMAKE_C_COMPILER $(xcode-select -p)/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang)" >> toolchain.cmake

  cmake -G"Unix Makefiles" -DCMAKE_TOOLCHAIN_FILE=toolchain.cmake -DCMAKE_OSX_SYSROOT=${IOS_SYSROOT[0]} $COMMON_ARGS ../libwebp
  make
else
  echo "Unsupported architecture $ARCH"
  exit 1
fi
