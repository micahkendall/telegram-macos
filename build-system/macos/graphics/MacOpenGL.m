#import <MacOpenGL/MacOpenGL.h>
#import <TargetConditionals.h>
#include <math.h>

#undef glShaderSource
#undef glFlush
#undef glFinish

NSString *const kEAGLDrawablePropertyRetainedBacking = @"RetainedBacking";
NSString *const kEAGLDrawablePropertyColorFormat = @"ColorFormat";
NSString *const kEAGLColorFormatRGBA8 = @"RGBA8";
NSString *const kEAGLColorFormatRGB565 = @"RGB565";


@interface EAGLSharegroup ()
@property(nonatomic) CGLContextObj sharedContext;
@end
@implementation EAGLSharegroup
- (void)dealloc { if (_sharedContext) CGLReleaseContext(_sharedContext); }
@end

@interface EAGLContext () {
    CGLContextObj _nativeContext;
    __weak CAEAGLLayer *_drawable;
    GLsizei _drawableWidth;
    GLsizei _drawableHeight;
}
@end

@implementation EAGLContext
- (instancetype)initWithAPI:(EAGLRenderingAPI)api { return [self initWithAPI:api sharegroup:nil]; }
- (instancetype)initWithAPI:(EAGLRenderingAPI)api sharegroup:(EAGLSharegroup *)sharegroup {
    // Telegram's legacy renderers request the ES2 subset. A compatibility-profile
    // desktop context preserves their client vertex arrays and GLSL 1.20 shaders.
    if (api != kEAGLRenderingAPIOpenGLES2) return nil;
    if ((self = [super init])) {
        CGLPixelFormatAttribute attributes[] = { kCGLPFAAccelerated, kCGLPFAAllowOfflineRenderers, (CGLPixelFormatAttribute)0 };
        CGLPixelFormatObj format = NULL;
        GLint count = 0;
        if (CGLChoosePixelFormat(attributes, &format, &count) != kCGLNoError) return nil;
        _sharegroup = sharegroup ?: [[EAGLSharegroup alloc] init];
        CGLError result = CGLCreateContext(format, _sharegroup.sharedContext, &_nativeContext);
        CGLDestroyPixelFormat(format);
        if (result != kCGLNoError) return nil;
        if (_sharegroup.sharedContext == NULL) _sharegroup.sharedContext = CGLRetainContext(_nativeContext);
        _API = api;
    }
    return self;
}
+ (EAGLContext *)currentContext { return [NSThread currentThread].threadDictionary[@"Telegram.Catalyst.GLContext"]; }
+ (BOOL)setCurrentContext:(EAGLContext *)context {
    if (CGLSetCurrentContext(context ? context->_nativeContext : NULL) != kCGLNoError) return NO;
    if (context) [NSThread currentThread].threadDictionary[@"Telegram.Catalyst.GLContext"] = context;
    else [[NSThread currentThread].threadDictionary removeObjectForKey:@"Telegram.Catalyst.GLContext"];
    return YES;
}
- (BOOL)renderbufferStorage:(NSUInteger)target fromDrawable:(id<EAGLDrawable>)drawable {
    if (![drawable isKindOfClass:[CAEAGLLayer class]]) return NO;
    CAEAGLLayer *layer = (CAEAGLLayer *)drawable;
    _drawable = layer;
    _drawableWidth = MAX(1, (GLsizei)ceil(layer.bounds.size.width * layer.contentsScale));
    _drawableHeight = MAX(1, (GLsizei)ceil(layer.bounds.size.height * layer.contentsScale));
    glRenderbufferStorage((GLenum)target, GL_RGBA8, _drawableWidth, _drawableHeight);
    return glGetError() == GL_NO_ERROR;
}
- (BOOL)presentRenderbuffer:(NSUInteger)target {
    CAEAGLLayer *drawable = _drawable;
    if (!drawable || !_drawableWidth || !_drawableHeight) return NO;
    size_t stride = (size_t)_drawableWidth * 4;
    NSMutableData *pixels = [NSMutableData dataWithLength:stride * _drawableHeight];
    GLint oldFramebuffer = 0, oldRenderbuffer = 0, oldPack = 0;
    glGetIntegerv(GL_FRAMEBUFFER_BINDING, &oldFramebuffer);
    glGetIntegerv(GL_RENDERBUFFER_BINDING, &oldRenderbuffer);
    glGetIntegerv(GL_PACK_ROW_LENGTH, &oldPack);
    GLuint framebuffer;
    glGenFramebuffers(1, &framebuffer);
    glBindFramebuffer(GL_FRAMEBUFFER, framebuffer);
    glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, (GLenum)target, (GLuint)oldRenderbuffer);
    if (glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE) {
        glBindFramebuffer(GL_FRAMEBUFFER, (GLuint)oldFramebuffer);
        glDeleteFramebuffers(1, &framebuffer);
        return NO;
    }
    glPixelStorei(GL_PACK_ROW_LENGTH, 0);
    glReadPixels(0, 0, _drawableWidth, _drawableHeight, GL_RGBA, GL_UNSIGNED_BYTE, pixels.mutableBytes);
    glPixelStorei(GL_PACK_ROW_LENGTH, oldPack);
    glBindFramebuffer(GL_FRAMEBUFFER, (GLuint)oldFramebuffer);
    glDeleteFramebuffers(1, &framebuffer);
    // GL's first row is the bottom row; Core Animation's first row is the top.
    uint8_t *bytes = pixels.mutableBytes;
    NSMutableData *row = [NSMutableData dataWithLength:stride];
    for (GLsizei y = 0; y < _drawableHeight / 2; y++) {
        uint8_t *top = bytes + y * stride;
        uint8_t *bottom = bytes + (_drawableHeight - y - 1) * stride;
        memcpy(row.mutableBytes, top, stride); memcpy(top, bottom, stride); memcpy(bottom, row.bytes, stride);
    }
    CGDataProviderRef provider = CGDataProviderCreateWithCFData((__bridge CFDataRef)pixels);
    CGColorSpaceRef colors = CGColorSpaceCreateDeviceRGB();
    CGImageRef image = CGImageCreate(_drawableWidth, _drawableHeight, 8, 32, stride, colors, kCGBitmapByteOrder32Big | kCGImageAlphaPremultipliedLast, provider, NULL, false, kCGRenderingIntentDefault);
    drawable.contents = (__bridge id)image;
    CGImageRelease(image); CGColorSpaceRelease(colors); CGDataProviderRelease(provider);
    return YES;
}
- (void)dealloc { if (_nativeContext) CGLReleaseContext(_nativeContext); }
@end

// Desktop GLSL accepts the same ES2 operations after removing precision syntax.
// Use a wrapper rather than mutating the application's shader sources.
void TGMacGLShaderSource(GLuint shader, GLsizei count, const GLchar *const *strings, const GLint *lengths) {
    NSMutableString *source = [NSMutableString string];
    for (GLsizei i = 0; i < count; i++) {
        size_t length = lengths && lengths[i] >= 0 ? (size_t)lengths[i] : strlen(strings[i]);
        NSString *part = [[NSString alloc] initWithBytes:strings[i] length:length encoding:NSUTF8StringEncoding];
        if (part) [source appendString:part];
    }
    for (NSString *pattern in @[@"(?m)^\\s*precision\\s+(lowp|mediump|highp)\\s+\\w+\\s*;", @"\\b(lowp|mediump|highp)\\b", @"(?m)^\\s*#version\\s+100\\s*$", @"(?m)^\\s*#extension\\s+GL_OES_standard_derivatives[^\\n]*"]) {
        NSRegularExpression *expression = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:NULL];
        [expression replaceMatchesInString:source options:0 range:NSMakeRange(0, source.length) withTemplate:@""];
    }
    const char *translated = source.UTF8String;
    glShaderSource(shader, 1, &translated, NULL);
}

@interface TGMacTexture : NSObject
@property(nonatomic) GLuint name;
@property(nonatomic) GLenum target;
@property(nonatomic) GLenum format;
@property(nonatomic) GLenum type;
@property(nonatomic) size_t plane;
@property(nonatomic) GLsizei width;
@property(nonatomic) GLsizei height;
@property(nonatomic) CVPixelBufferRef buffer;
@property(nonatomic, strong) EAGLContext *context;
- (void)readBack;
@end

static NSHashTable<TGMacTexture *> *TGMacTextures(void) {
    static NSHashTable *textures;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ textures = [NSHashTable weakObjectsHashTable]; });
    return textures;
}

@implementation TGMacTexture
- (void)readBack {
    if (self.context != [EAGLContext currentContext]) return;
    CVPixelBufferLockBaseAddress(_buffer, 0);
    BOOL planar = CVPixelBufferIsPlanar(_buffer);
    void *base = planar ? CVPixelBufferGetBaseAddressOfPlane(_buffer, _plane) : CVPixelBufferGetBaseAddress(_buffer);
    size_t stride = planar ? CVPixelBufferGetBytesPerRowOfPlane(_buffer, _plane) : CVPixelBufferGetBytesPerRow(_buffer);
    size_t bytesPerPixel = (_format == GL_RGBA || _format == GL_BGRA) ? 4 : ((_format == GL_RG || _format == GL_LUMINANCE_ALPHA) ? 2 : 1);
    GLint binding = 0, rowLength = 0;
    glGetIntegerv(GL_TEXTURE_BINDING_2D, &binding); glGetIntegerv(GL_PACK_ROW_LENGTH, &rowLength);
    glBindTexture(_target, _name);
    glPixelStorei(GL_PACK_ROW_LENGTH, (GLint)(stride / bytesPerPixel));
    glGetTexImage(_target, 0, _format, _type, base);
    glPixelStorei(GL_PACK_ROW_LENGTH, rowLength); glBindTexture(_target, (GLuint)binding);
    CVPixelBufferUnlockBaseAddress(_buffer, 0);
}
- (void)dealloc {
    EAGLContext *old = [EAGLContext currentContext];
    [EAGLContext setCurrentContext:_context];
    if (_name) glDeleteTextures(1, &_name);
    [EAGLContext setCurrentContext:old];
    if (_buffer) CVPixelBufferRelease(_buffer);
}
@end

@interface TGMacTextureCache : NSObject
@property(nonatomic, strong) EAGLContext *context;
@end
@implementation TGMacTextureCache
@end

static void TGMacReadBackTextures(void) {
    NSArray<TGMacTexture *> *textures;
    @synchronized(TGMacTextures()) { textures = TGMacTextures().allObjects; }
    for (TGMacTexture *texture in textures) [texture readBack];
}
void TGMacGLFlush(void) { glFlush(); TGMacReadBackTextures(); }
void TGMacGLFinish(void) { glFinish(); TGMacReadBackTextures(); }
CVReturn TGMacTextureCacheCreate(CFAllocatorRef allocator, CFDictionaryRef attributes, EAGLContext *context, CFDictionaryRef textureAttributes, CVOpenGLESTextureCacheRef *cache) {
    if (!context || !cache) return kCVReturnInvalidArgument;
    TGMacTextureCache *result = [[TGMacTextureCache alloc] init];
    result.context = context;
    *cache = CFBridgingRetain(result);
    return kCVReturnSuccess;
}
CVReturn TGMacTextureCacheCreateTexture(CFAllocatorRef allocator, CVOpenGLESTextureCacheRef cache, CVImageBufferRef image, CFDictionaryRef attributes, GLenum target, GLint internalFormat, GLsizei width, GLsizei height, GLenum format, GLenum type, size_t plane, CVOpenGLESTextureRef *texture) {
    if (!cache || !image || !texture || target != GL_TEXTURE_2D || type != GL_UNSIGNED_BYTE) return kCVReturnInvalidArgument;
    TGMacTextureCache *owner = (__bridge TGMacTextureCache *)cache;
    if (owner.context != [EAGLContext currentContext]) return kCVReturnInvalidArgument;
    BOOL planar = CVPixelBufferIsPlanar(image);
    if (planar && plane >= CVPixelBufferGetPlaneCount(image)) return kCVReturnInvalidArgument;
    size_t bufferWidth = planar ? CVPixelBufferGetWidthOfPlane(image, plane) : CVPixelBufferGetWidth(image);
    size_t bufferHeight = planar ? CVPixelBufferGetHeightOfPlane(image, plane) : CVPixelBufferGetHeight(image);
    if (width <= 0 || height <= 0 || (size_t)width > bufferWidth || (size_t)height > bufferHeight) return kCVReturnInvalidArgument;
    TGMacTexture *result = [[TGMacTexture alloc] init];
    result.context = owner.context; result.target = target; result.format = format; result.type = type;
    result.width = width; result.height = height; result.plane = plane;
    result.buffer = CVPixelBufferRetain(image);
    CVPixelBufferLockBaseAddress(image, kCVPixelBufferLock_ReadOnly);
    void *base = planar ? CVPixelBufferGetBaseAddressOfPlane(image, plane) : CVPixelBufferGetBaseAddress(image);
    size_t stride = planar ? CVPixelBufferGetBytesPerRowOfPlane(image, plane) : CVPixelBufferGetBytesPerRow(image);
    size_t bpp = (format == GL_RGBA || format == GL_BGRA) ? 4 : ((format == GL_RG || format == GL_LUMINANCE_ALPHA) ? 2 : 1);
    GLint binding = 0, rowLength = 0;
    glGetIntegerv(GL_TEXTURE_BINDING_2D, &binding); glGetIntegerv(GL_UNPACK_ROW_LENGTH, &rowLength);
    GLuint name; glGenTextures(1, &name); result.name = name;
    glBindTexture(target, name); glPixelStorei(GL_UNPACK_ROW_LENGTH, (GLint)(stride / bpp));
    glTexImage2D(target, 0, internalFormat, width, height, 0, format, type, base);
    GLenum error = glGetError();
    glPixelStorei(GL_UNPACK_ROW_LENGTH, rowLength); glBindTexture(target, (GLuint)binding);
    CVPixelBufferUnlockBaseAddress(image, kCVPixelBufferLock_ReadOnly);
    if (error != GL_NO_ERROR) return kCVReturnError;
    @synchronized(TGMacTextures()) { [TGMacTextures() addObject:result]; }
    *texture = CFBridgingRetain(result);
    return kCVReturnSuccess;
}
void TGMacTextureCacheFlush(CVOpenGLESTextureCacheRef cache, CVOptionFlags options) { TGMacReadBackTextures(); }
GLenum TGMacTextureTarget(CVOpenGLESTextureRef texture) { return ((__bridge TGMacTexture *)texture).target; }
GLuint TGMacTextureName(CVOpenGLESTextureRef texture) { return ((__bridge TGMacTexture *)texture).name; }

@implementation GLKView {
    GLuint _framebuffer, _renderbuffer, _depthbuffer;
    CGSize _pixelSize;
}
+ (Class)layerClass { return [CAEAGLLayer class]; }
- (instancetype)initWithFrame:(CGRect)frame context:(EAGLContext *)context {
    if ((self = [super initWithFrame:frame])) { self.context = context; self.contentScaleFactor = UIScreen.mainScreen.scale; }
    return self;
}
- (void)display {
    EAGLContext *old = [EAGLContext currentContext];
    if (![EAGLContext setCurrentContext:self.context]) return;
    CGSize size = CGSizeMake(ceil(self.bounds.size.width * self.contentScaleFactor), ceil(self.bounds.size.height * self.contentScaleFactor));
    if (!_framebuffer || !CGSizeEqualToSize(size, _pixelSize)) {
        [self deleteDrawable];
        glGenFramebuffers(1, &_framebuffer); glBindFramebuffer(GL_FRAMEBUFFER, _framebuffer);
        glGenRenderbuffers(1, &_renderbuffer); glBindRenderbuffer(GL_RENDERBUFFER, _renderbuffer);
        [self.context renderbufferStorage:GL_RENDERBUFFER fromDrawable:(CAEAGLLayer *)self.layer];
        glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, _renderbuffer);
        if (self.drawableDepthFormat != GLKViewDrawableDepthFormatNone) {
            glGenRenderbuffers(1, &_depthbuffer); glBindRenderbuffer(GL_RENDERBUFFER, _depthbuffer);
            glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH_COMPONENT24, (GLsizei)size.width, (GLsizei)size.height);
            glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_RENDERBUFFER, _depthbuffer);
        }
        _pixelSize = size;
    }
    glBindFramebuffer(GL_FRAMEBUFFER, _framebuffer); glBindRenderbuffer(GL_RENDERBUFFER, _renderbuffer);
    glViewport(0, 0, (GLsizei)size.width, (GLsizei)size.height);
    [self.delegate glkView:self drawInRect:self.bounds];
    [self.context presentRenderbuffer:GL_RENDERBUFFER];
    [EAGLContext setCurrentContext:old];
}
- (UIImage *)snapshot {
    if (!self.layer.contents) return nil;
    return [UIImage imageWithCGImage:(__bridge CGImageRef)self.layer.contents scale:self.contentScaleFactor orientation:UIImageOrientationUp];
}
- (void)deleteDrawable {
    if (_framebuffer) glDeleteFramebuffers(1, &_framebuffer);
    if (_renderbuffer) glDeleteRenderbuffers(1, &_renderbuffer);
    if (_depthbuffer) glDeleteRenderbuffers(1, &_depthbuffer);
    _framebuffer = _renderbuffer = _depthbuffer = 0;
}
- (void)dealloc {
    EAGLContext *old = [EAGLContext currentContext];
    [EAGLContext setCurrentContext:_context];
    [self deleteDrawable];
    [EAGLContext setCurrentContext:old == _context ? nil : old];
}
@end

void TGMacGLUploadCIImage(CIContext *context, CIImage *image, GLuint texture) {
    GLsizei width = (GLsizei)ceil(image.extent.size.width);
    GLsizei height = (GLsizei)ceil(image.extent.size.height);
    if (width <= 0 || height <= 0) return;
    NSMutableData *pixels = [NSMutableData dataWithLength:(size_t)width * height * 4];
    [context render:image toBitmap:pixels.mutableBytes rowBytes:(size_t)width * 4 bounds:image.extent format:kCIFormatRGBA8 colorSpace:NULL];
    GLint binding = 0, rowLength = 0;
    glGetIntegerv(GL_TEXTURE_BINDING_2D, &binding); glGetIntegerv(GL_UNPACK_ROW_LENGTH, &rowLength);
    glBindTexture(GL_TEXTURE_2D, texture); glPixelStorei(GL_UNPACK_ROW_LENGTH, 0);
    glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, width, height, GL_RGBA, GL_UNSIGNED_BYTE, pixels.bytes);
    glPixelStorei(GL_UNPACK_ROW_LENGTH, rowLength); glBindTexture(GL_TEXTURE_2D, (GLuint)binding);
}
