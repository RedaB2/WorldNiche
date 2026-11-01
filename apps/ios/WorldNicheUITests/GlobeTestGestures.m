#import "GlobeTestGestures.h"
#import <XCTest/XCTest.h>

@interface NSObject (GlobeEventSynthesis)
- (id)eventSynthesizer;
- (id)initForTouchAtPoint:(CGPoint)point offset:(NSTimeInterval)offset;
- (void)moveToPoint:(CGPoint)point atOffset:(NSTimeInterval)offset;
- (void)liftUpAtOffset:(NSTimeInterval)offset;
- (id)initWithName:(NSString *)name displayID:(unsigned long long)displayID interfaceOrientation:(NSInteger)orientation;
- (void)addPointerEventPath:(id)path;
- (void)setTargetProcessID:(int)processID;
- (int)processID;
- (NSInteger)interfaceOrientation;
- (void)setParentWindowSize:(CGSize)size;
- (void)synthesizeEvent:(id)event completion:(void (^)(BOOL, NSError *))completion;
@end

@implementation GlobeTestGestures
+ (CGAffineTransform)displayTransform {
    // Match XCTest's portrait display coordinates, including the unfolded Duo's landscape window.
    XCUIElement *window = [[XCUIApplication alloc] init].windows.firstMatch;
    CGSize size = window.frame.size;
    switch ([window interfaceOrientation]) {
        case UIInterfaceOrientationLandscapeLeft:
            return CGAffineTransformMake(0, -1, 1, 0, 0, size.width);
        case UIInterfaceOrientationLandscapeRight:
            return CGAffineTransformMake(0, 1, -1, 0, size.height, 0);
        case UIInterfaceOrientationPortraitUpsideDown:
            return CGAffineTransformMake(-1, 0, 0, -1, size.width, size.height);
        default: return CGAffineTransformIdentity;
    }
}

+ (NSString *)trace:(NSArray<NSValue *> *)points duration:(NSTimeInterval)duration hold:(NSTimeInterval)hold {
    CGAffineTransform transform = [self displayTransform];
    Class pathClass = NSClassFromString(@"XCPointerEventPath");
    if (points.count == 0 || ![pathClass instancesRespondToSelector:@selector(initForTouchAtPoint:offset:)]) {
        return @"Touch paths are unavailable or empty.";
    }
    id path = [[pathClass alloc] initForTouchAtPoint:CGPointApplyAffineTransform(points.firstObject.CGPointValue, transform) offset:0];
    for (NSUInteger i = 1; i < points.count; i++) {
        [path moveToPoint:CGPointApplyAffineTransform(points[i].CGPointValue, transform) atOffset:0.05 + duration * i / (points.count - 1)];
    }
    // Hold by delaying lift. A duplicate endpoint can alter the synthesized release speed.
    [path liftUpAtOffset:duration + 0.06 + hold];
    return [self deliverPaths:@[path] duration:duration + hold + 0.06];
}

+ (NSString *)resetAt:(CGPoint)resetPoint thenTrace:(NSArray<NSValue *> *)points duration:(NSTimeInterval)duration {
    CGAffineTransform transform = [self displayTransform];
    Class pathClass = NSClassFromString(@"XCPointerEventPath");
    if (points.count < 2 || ![pathClass instancesRespondToSelector:@selector(initForTouchAtPoint:offset:)]) {
        return @"Touch paths are unavailable or empty.";
    }
    id tap = [[pathClass alloc] initForTouchAtPoint:CGPointApplyAffineTransform(resetPoint, transform) offset:0];
    [tap liftUpAtOffset:0.05];
    id drag = [[pathClass alloc] initForTouchAtPoint:CGPointApplyAffineTransform(points.firstObject.CGPointValue, transform) offset:0.15];
    for (NSUInteger i = 1; i < points.count; i++) {
        [drag moveToPoint:CGPointApplyAffineTransform(points[i].CGPointValue, transform) atOffset:0.2 + duration * i / (points.count - 1)];
    }
    [drag liftUpAtOffset:duration + 0.4];
    return [self deliverPaths:@[tap, drag] duration:duration + 0.4];
}

+ (NSString *)moveFirst:(CGPoint)first second:(CGPoint)second
                 toFirst:(CGPoint)firstEnd toSecond:(CGPoint)secondEnd
                duration:(NSTimeInterval)duration {
    CGAffineTransform transform = [self displayTransform];
    Class pathClass = NSClassFromString(@"XCPointerEventPath");
    if (![pathClass instancesRespondToSelector:@selector(initForTouchAtPoint:offset:)]) {
        return @"This Xcode version does not expose touch paths.";
    }
    NSMutableArray *paths = [NSMutableArray array];
    CGPoint starts[] = {first, second};
    CGPoint ends[] = {firstEnd, secondEnd};
    for (int finger = 0; finger < 2; finger++) {
        id path = [[pathClass alloc] initForTouchAtPoint:CGPointApplyAffineTransform(starts[finger], transform) offset:0];
        for (int step = 1; step <= 30; step++) {
            double fraction = step / 30.0;
            CGPoint point = CGPointMake(starts[finger].x + (ends[finger].x - starts[finger].x) * fraction,
                                        starts[finger].y + (ends[finger].y - starts[finger].y) * fraction);
            [path moveToPoint:CGPointApplyAffineTransform(point, transform) atOffset:0.1 + duration * fraction];
        }
        [path liftUpAtOffset:duration + 0.2];
        [paths addObject:path];
    }
    return [self deliverPaths:paths duration:duration + 0.2];
}

+ (NSString *)transitionFirst:(CGPoint)first second:(CGPoint)second
                  translation:(CGPoint)translation finalPoint:(CGPoint)finalPoint {
    CGAffineTransform transform = [self displayTransform];
    Class pathClass = NSClassFromString(@"XCPointerEventPath");
    if (![pathClass instancesRespondToSelector:@selector(initForTouchAtPoint:offset:)]) {
        return @"This Xcode version does not expose touch paths.";
    }
    id one = [[pathClass alloc] initForTouchAtPoint:CGPointApplyAffineTransform(first, transform) offset:0];
    CGPoint turnEnd = CGPointMake(first.x - 25, first.y - 15);
    for (int step = 1; step <= 30; step++) {
        double t = step / 30.0;
        [one moveToPoint:CGPointApplyAffineTransform(CGPointMake(first.x - 25 * t, first.y - 15 * t), transform) atOffset:0.1 + 0.5 * t];
    }
    [one moveToPoint:CGPointApplyAffineTransform(turnEnd, transform) atOffset:1];
    CGPoint secondStart = CGPointMake(second.x - 25, second.y - 15);
    id two = [[pathClass alloc] initForTouchAtPoint:CGPointApplyAffineTransform(secondStart, transform) offset:0.8];
    [two moveToPoint:CGPointApplyAffineTransform(secondStart, transform) atOffset:1];
    CGPoint moved = CGPointMake(turnEnd.x + translation.x, turnEnd.y + translation.y);
    for (int step = 1; step <= 30; step++) {
        double t = step / 30.0;
        [one moveToPoint:CGPointApplyAffineTransform(CGPointMake(turnEnd.x + translation.x * t, turnEnd.y + translation.y * t), transform) atOffset:1 + 0.6 * t];
        [two moveToPoint:CGPointApplyAffineTransform(CGPointMake(secondStart.x + translation.x * t, secondStart.y + translation.y * t), transform) atOffset:1 + 0.6 * t];
    }
    [one moveToPoint:CGPointApplyAffineTransform(moved, transform) atOffset:2];
    [two liftUpAtOffset:1.8];
    for (int step = 1; step <= 30; step++) {
        double t = step / 30.0;
        [one moveToPoint:CGPointApplyAffineTransform(CGPointMake(moved.x + (finalPoint.x - moved.x) * t, moved.y + (finalPoint.y - moved.y) * t), transform) atOffset:2 + 0.8 * t];
    }
    [one liftUpAtOffset:3];
    return [self deliverPaths:@[one, two] duration:3];
}

+ (NSString *)deliverPaths:(NSArray *)paths duration:(NSTimeInterval)duration {
    Class pathClass = NSClassFromString(@"XCPointerEventPath");
    Class recordClass = NSClassFromString(@"XCSynthesizedEventRecord");
    if (![pathClass instancesRespondToSelector:@selector(initForTouchAtPoint:offset:)] ||
        ![recordClass instancesRespondToSelector:@selector(initWithName:displayID:interfaceOrientation:)] ||
        ![recordClass instancesRespondToSelector:@selector(setParentWindowSize:)] ||
        ![XCUIDevice.sharedDevice respondsToSelector:@selector(eventSynthesizer)]) {
        return @"This Xcode version does not expose multi-touch event synthesis.";
    }
    id session = [XCUIDevice.sharedDevice eventSynthesizer];
    if (![session respondsToSelector:@selector(synthesizeEvent:completion:)]) {
        return @"This Xcode version does not expose the event synthesis session.";
    }
    XCUIApplication *app = [[XCUIApplication alloc] init];
    XCUIElement *window = app.windows.firstMatch;
    NSString *display = NSProcessInfo.processInfo.environment[@"WORLDNICHE_UI_TEST_DISPLAY_ID"];
    id record = [[recordClass alloc] initWithName:@"Globe gesture"
                                      displayID:display ? display.longLongValue : 1
                           interfaceOrientation:UIInterfaceOrientationPortrait];
    [record setParentWindowSize:window.frame.size];
    [record setTargetProcessID:[app processID]];
    for (id path in paths) { [record addPointerEventPath:path]; }
    XCTestExpectation *finished = [[XCTestExpectation alloc] initWithDescription:@"Multi-touch delivered"];
    __block NSError *failure;
    __block BOOL delivered = NO;
    NSTimeInterval started = NSProcessInfo.processInfo.systemUptime;
    [session synthesizeEvent:record completion:^(BOOL result, NSError *error) {
        failure = error;
        delivered = result;
        [finished fulfill];
    }];
    if ([XCTWaiter waitForExpectations:@[finished] timeout:duration + 10] != XCTWaiterResultCompleted) {
        return @"Timed out delivering the two-finger gesture.";
    }
    NSTimeInterval elapsed = NSProcessInfo.processInfo.systemUptime - started;
    // Private event synthesis can acknowledge before the last scheduled touch is delivered.
    // Keep the next test action from overlapping the tail of this gesture.
    if (delivered && elapsed < duration + 0.1) { [NSThread sleepForTimeInterval:duration + 0.1 - elapsed]; }
    return failure.localizedDescription ?: (delivered ? nil : @"Touch event synthesis was rejected.");
}
@end
