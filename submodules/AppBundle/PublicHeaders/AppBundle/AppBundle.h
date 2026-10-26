#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NSBundle * _Nonnull getAppBundle(void);

/// Resolves shared iOS storage or this standalone Catalyst app's private storage.
NSURL * _Nullable getAppGroupContainerURL(NSString * _Nonnull appGroupIdentifier);

@interface UIImage (AppBundle)

- (instancetype _Nullable)initWithBundleImageName:(NSString * _Nonnull)bundleImageName;

@end
