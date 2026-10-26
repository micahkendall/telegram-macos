#pragma once
#import <Foundation/Foundation.h>
#import <CoreVideo/CoreVideo.h>
#import <OpenGL/OpenGL.h>
#import <OpenGLES/ES2/gl.h>
#import <OpenGLES/EAGLDrawable.h>
// Prefix runtime classes to avoid the system iOS-support compatibility classes.
#define EAGLContext TGCatalystEAGLContext
#define EAGLSharegroup TGCatalystEAGLSharegroup
typedef NS_ENUM(NSUInteger, EAGLRenderingAPI) { kEAGLRenderingAPIOpenGLES1 = 1, kEAGLRenderingAPIOpenGLES2 = 2, kEAGLRenderingAPIOpenGLES3 = 3 };
@interface EAGLSharegroup : NSObject
@end
@interface EAGLContext : NSObject
- (instancetype)initWithAPI:(EAGLRenderingAPI)api;
- (instancetype)initWithAPI:(EAGLRenderingAPI)api sharegroup:(EAGLSharegroup *)sharegroup;
+ (EAGLContext *)currentContext;
+ (BOOL)setCurrentContext:(EAGLContext *)context;
@property(nonatomic, readonly) EAGLSharegroup *sharegroup;
@property(nonatomic, readonly) EAGLRenderingAPI API;
@property(nonatomic) BOOL multiThreaded;
- (BOOL)renderbufferStorage:(NSUInteger)target fromDrawable:(id<EAGLDrawable>)drawable;
- (BOOL)presentRenderbuffer:(NSUInteger)target;
@end
// The compatibility texture cache owns real desktop GL textures. Flush/finish
// read rendered pixels back into their CoreVideo buffers before consumers read them.
typedef CFTypeRef CVOpenGLESTextureCacheRef;
typedef CFTypeRef CVOpenGLESTextureRef;
#ifdef __cplusplus
extern "C" {
#endif
CVReturn TGMacTextureCacheCreate(CFAllocatorRef allocator, CFDictionaryRef attributes, EAGLContext *context, CFDictionaryRef textureAttributes, CVOpenGLESTextureCacheRef *cache);
CVReturn TGMacTextureCacheCreateTexture(CFAllocatorRef allocator, CVOpenGLESTextureCacheRef cache, CVImageBufferRef image, CFDictionaryRef attributes, GLenum target, GLint internalFormat, GLsizei width, GLsizei height, GLenum format, GLenum type, size_t plane, CVOpenGLESTextureRef *texture);
void TGMacTextureCacheFlush(CVOpenGLESTextureCacheRef cache, CVOptionFlags options);
GLenum TGMacTextureTarget(CVOpenGLESTextureRef texture);
GLuint TGMacTextureName(CVOpenGLESTextureRef texture);
#ifdef __cplusplus
}
#endif
#define CVOpenGLESTextureCacheCreate TGMacTextureCacheCreate
#define CVOpenGLESTextureCacheCreateTextureFromImage TGMacTextureCacheCreateTexture
#define CVOpenGLESTextureCacheFlush TGMacTextureCacheFlush
#define CVOpenGLESTextureGetTarget TGMacTextureTarget
#define CVOpenGLESTextureGetName TGMacTextureName
#define kCVPixelBufferOpenGLESCompatibilityKey CFSTR("OpenGLESCompatibility")
