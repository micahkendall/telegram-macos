#import <Foundation/Foundation.h>

/// The host Mac model, using the native Swift client's naming algorithm.
FOUNDATION_EXPORT NSString * _Nonnull MTMacOSClientDeviceModel(void);
/// The host macOS product version, independent of UIKit's compatibility version.
FOUNDATION_EXPORT NSString * _Nonnull MTMacOSClientSystemVersion(void);
/// Native Mac initConnection parameters, using this build's actual signing data.
FOUNDATION_EXPORT NSData * _Nullable MTMacOSClientAppData(NSBundle * _Nonnull bundle);
