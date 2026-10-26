load("@rules_cc//cc:objc_library.bzl", "objc_library")
objc_library(
    name = "MacOpenGL",
    module_name = "MacOpenGL",
    srcs = ["MacOpenGL.m"],
    hdrs = ["include/MacOpenGL/MacOpenGL.h"],
    textual_hdrs = glob(["include/OpenGLES/**/*.h", "include/GLKit/*.h"]),
    includes = ["include"],
    sdk_frameworks = ["Foundation", "UIKit", "QuartzCore", "OpenGL", "CoreVideo", "CoreGraphics", "CoreImage"],
    defines = ["GL_SILENCE_DEPRECATION=1", "GLES_SILENCE_DEPRECATION=1"],
    visibility = ["//visibility:public"],
)
