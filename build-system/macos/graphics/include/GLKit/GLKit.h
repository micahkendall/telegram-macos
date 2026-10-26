#pragma once
#import <UIKit/UIKit.h>
#import <OpenGLES/EAGL.h>
#define GLKView TGCatalystGLKView
#define GLKViewDelegate TGCatalystGLKViewDelegate
@class GLKView;
@protocol GLKViewDelegate <NSObject>
- (void)glkView:(GLKView *)view drawInRect:(CGRect)rect;
@end
typedef NS_ENUM(NSInteger, GLKViewDrawableDepthFormat) { GLKViewDrawableDepthFormatNone, GLKViewDrawableDepthFormat16, GLKViewDrawableDepthFormat24 };
typedef NS_ENUM(NSInteger, GLKViewDrawableMultisample) { GLKViewDrawableMultisampleNone, GLKViewDrawableMultisample4X };
@interface GLKView : UIView
- (instancetype)initWithFrame:(CGRect)frame context:(EAGLContext *)context;
@property(nonatomic, strong) EAGLContext *context;
@property(nonatomic, weak) id<GLKViewDelegate> delegate;
@property(nonatomic) GLKViewDrawableDepthFormat drawableDepthFormat;
@property(nonatomic) GLKViewDrawableMultisample drawableMultisample;
@property(nonatomic) BOOL enableSetNeedsDisplay;
@property(nonatomic, readonly) UIImage *snapshot;
- (void)display;
- (void)deleteDrawable;
@end
