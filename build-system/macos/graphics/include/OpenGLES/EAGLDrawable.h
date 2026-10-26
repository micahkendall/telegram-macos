#pragma once
#import <Foundation/Foundation.h>
FOUNDATION_EXPORT NSString *const kEAGLDrawablePropertyRetainedBacking;
FOUNDATION_EXPORT NSString *const kEAGLDrawablePropertyColorFormat;
FOUNDATION_EXPORT NSString *const kEAGLColorFormatRGBA8;
FOUNDATION_EXPORT NSString *const kEAGLColorFormatRGB565;
#define EAGLDrawable TGCatalystEAGLDrawable
@protocol EAGLDrawable <NSObject>
@property(nonatomic, copy) NSDictionary *drawableProperties;
@end
