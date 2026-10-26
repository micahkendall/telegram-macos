#pragma once
#import <GLKit/GLKit.h>

#import <CoreImage/CoreImage.h>
FOUNDATION_EXPORT void TGMacGLUploadCIImage(CIContext *context, CIImage *image, GLuint texture);
