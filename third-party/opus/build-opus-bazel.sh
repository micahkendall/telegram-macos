#! /bin/sh

set -ex

ARCH="$1"
BUILD_DIR=$(echo "$(cd "$(dirname "$2")"; pwd -P)/$(basename "$2")")
SOURCE_CODE_ARCHIVE="$3"

MINIOSVERSION="13.0"

OPT_CFLAGS="-Os -g"
OPT_LDFLAGS=""
OPT_CONFIG_ARGS=""

OUTPUTDIR="$BUILD_DIR/Public"

# where we will keep our sources and build from.
SRCDIR="${BUILD_DIR}/src"
mkdir -p $SRCDIR
# where we will store intermediary builds
INTERDIR="${BUILD_DIR}/built"
mkdir -p $INTERDIR

########################################

tar zxf "$BUILD_DIR/$SOURCE_CODE_ARCHIVE" -C $SRCDIR
cd "${SRCDIR}/opus-"*

if [ "${ARCH}" = "linux_x86_64" ] || [ "${ARCH}" = "linux_arm64" ]; then
  mkdir -p "${INTERDIR}"

  # Keep it simple and portable for container builds.
  ./configure \
    --disable-shared \
    --enable-static \
    --with-pic \
    --disable-extra-programs \
    --disable-doc \
    --disable-asm \
    --enable-intrinsics \
    ${OPT_CONFIG_ARGS} \
    --prefix="${INTERDIR}" \
    CFLAGS="$CFLAGS ${OPT_CFLAGS} -fPIC" \
    LDFLAGS="$LDFLAGS ${OPT_LDFLAGS}"

  make -j"$(getconf _NPROCESSORS_ONLN || echo 4)"
  make install
  exit 0
elif [ "${ARCH}" == "x86_64" ]; then
  PLATFORM="iphonesimulator"
  EXTRA_CFLAGS="-arch ${ARCH}"
  EXTRA_CONFIG="--host=x86_64-apple-darwin"
elif [ "${ARCH}" == "sim_arm64" ]; then
  PLATFORM="iphonesimulator"
  EXTRA_CFLAGS="-arch arm64 --target=arm64-apple-ios$MINIOSVERSION-simulator"
  EXTRA_CONFIG="--host=arm-apple-darwin20"
elif [ "${TELEGRAM_CATALYST:-0}" = "1" ] && [ "${ARCH}" = "arm64" ]; then
  PLATFORM="macosx"
  EXTRA_CFLAGS="--target=arm64-apple-ios15.0-macabi"
  EXTRA_CONFIG="--host=arm-apple-darwin20"
elif [ "${ARCH}" == "macos_arm64" ]; then
  PLATFORM="macosx"
  EXTRA_CFLAGS="-arch arm64 --target=arm64-apple-macosx14.0"
  EXTRA_CONFIG="--host=arm-apple-darwin20"
else
  PLATFORM="iphoneos"
  EXTRA_CFLAGS="-arch ${ARCH}"
  EXTRA_CONFIG="--host=arm-apple-darwin"
fi

SDK_PATH="$(xcrun --sdk $PLATFORM --show-sdk-path 2>/dev/null)"

mkdir -p "${INTERDIR}"

DEPLOYMENT_FLAGS="-miphoneos-version-min=${MINIOSVERSION}"
if [ "${TELEGRAM_CATALYST:-0}" = "1" ]; then
  DEPLOYMENT_FLAGS="--target=arm64-apple-ios15.0-macabi -isysroot ${SDK_PATH}"
fi

./configure --disable-shared --enable-static --with-pic --disable-extra-programs --disable-doc --disable-asm --enable-intrinsics ${EXTRA_CONFIG} \
  --prefix="${INTERDIR}" \
  LDFLAGS="$LDFLAGS ${OPT_LDFLAGS} -fPIE ${DEPLOYMENT_FLAGS} -L${OUTPUTDIR}/lib" \
  CFLAGS="$CFLAGS ${EXTRA_CFLAGS} ${OPT_CFLAGS} -fPIE ${DEPLOYMENT_FLAGS} -I${OUTPUTDIR}/include -isysroot ${SDK_PATH}" \

make -j
make install
