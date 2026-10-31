#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN
// XCTest has a public pinch API but no public two-finger drag API.
// This helper is compiled only into the UI test runner, never the app.
@interface GlobeTestGestures : NSObject
+ (nullable NSString *)moveFirst:(CGPoint)first second:(CGPoint)second
                         toFirst:(CGPoint)firstEnd toSecond:(CGPoint)secondEnd
                        duration:(NSTimeInterval)duration;
@end
NS_ASSUME_NONNULL_END
