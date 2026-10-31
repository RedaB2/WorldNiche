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
- (void)synthesizeEvent:(id)event completion:(void (^)(BOOL, NSError *))completion;
@end

@implementation GlobeTestGestures
+ (NSString *)moveFirst:(CGPoint)first second:(CGPoint)second
                 toFirst:(CGPoint)firstEnd toSecond:(CGPoint)secondEnd
                duration:(NSTimeInterval)duration {
    Class pathClass = NSClassFromString(@"XCPointerEventPath");
    if (![pathClass instancesRespondToSelector:@selector(initForTouchAtPoint:offset:)]) {
        return @"This Xcode version does not expose touch paths.";
    }
    NSMutableArray *paths = [NSMutableArray array];
    CGPoint starts[] = {first, second};
    CGPoint ends[] = {firstEnd, secondEnd};
    for (int finger = 0; finger < 2; finger++) {
        id path = [[pathClass alloc] initForTouchAtPoint:starts[finger] offset:0];
        for (int step = 1; step <= 30; step++) {
            double fraction = step / 30.0;
            CGPoint point = CGPointMake(starts[finger].x + (ends[finger].x - starts[finger].x) * fraction,
                                        starts[finger].y + (ends[finger].y - starts[finger].y) * fraction);
            [path moveToPoint:point atOffset:0.1 + duration * fraction];
        }
        [path liftUpAtOffset:duration + 0.2];
        [paths addObject:path];
    }
    return [self deliverPaths:paths duration:duration];
}

+ (NSString *)transitionFirst:(CGPoint)first second:(CGPoint)second
                  translation:(CGPoint)translation finalPoint:(CGPoint)finalPoint {
    Class pathClass = NSClassFromString(@"XCPointerEventPath");
    if (![pathClass instancesRespondToSelector:@selector(initForTouchAtPoint:offset:)]) {
        return @"This Xcode version does not expose touch paths.";
    }
    id one = [[pathClass alloc] initForTouchAtPoint:first offset:0];
    CGPoint turnEnd = CGPointMake(first.x - 25, first.y - 15);
    for (int step = 1; step <= 30; step++) {
        double t = step / 30.0;
        [one moveToPoint:CGPointMake(first.x - 25 * t, first.y - 15 * t) atOffset:0.1 + 0.5 * t];
    }
    [one moveToPoint:turnEnd atOffset:1];
    CGPoint secondStart = CGPointMake(second.x - 25, second.y - 15);
    id two = [[pathClass alloc] initForTouchAtPoint:secondStart offset:0.8];
    [two moveToPoint:secondStart atOffset:1];
    CGPoint moved = CGPointMake(turnEnd.x + translation.x, turnEnd.y + translation.y);
    for (int step = 1; step <= 30; step++) {
        double t = step / 30.0;
        [one moveToPoint:CGPointMake(turnEnd.x + translation.x * t, turnEnd.y + translation.y * t) atOffset:1 + 0.6 * t];
        [two moveToPoint:CGPointMake(secondStart.x + translation.x * t, secondStart.y + translation.y * t) atOffset:1 + 0.6 * t];
    }
    [one moveToPoint:moved atOffset:2];
    [two liftUpAtOffset:1.8];
    for (int step = 1; step <= 30; step++) {
        double t = step / 30.0;
        [one moveToPoint:CGPointMake(moved.x + (finalPoint.x - moved.x) * t, moved.y + (finalPoint.y - moved.y) * t) atOffset:2 + 0.8 * t];
    }
    [one liftUpAtOffset:3];
    return [self deliverPaths:@[one, two] duration:3];
}

+ (NSString *)deliverPaths:(NSArray *)paths duration:(NSTimeInterval)duration {
    Class pathClass = NSClassFromString(@"XCPointerEventPath");
    Class recordClass = NSClassFromString(@"XCSynthesizedEventRecord");
    if (![pathClass instancesRespondToSelector:@selector(initForTouchAtPoint:offset:)] ||
        ![recordClass instancesRespondToSelector:@selector(initWithName:displayID:interfaceOrientation:)] ||
        ![XCUIDevice.sharedDevice respondsToSelector:@selector(eventSynthesizer)]) {
        return @"This Xcode version does not expose multi-touch event synthesis.";
    }
    id session = [XCUIDevice.sharedDevice eventSynthesizer];
    if (![session respondsToSelector:@selector(synthesizeEvent:completion:)]) {
        return @"This Xcode version does not expose the event synthesis session.";
    }
    NSString *display = NSProcessInfo.processInfo.environment[@"WORLDNICHE_UI_TEST_DISPLAY_ID"];
    id record = [[recordClass alloc] initWithName:@"Two-finger globe movement"
                                      displayID:display ? display.longLongValue : 1
                           interfaceOrientation:UIInterfaceOrientationPortrait];
    XCUIApplication *app = [[XCUIApplication alloc] init];
    [record setTargetProcessID:[app processID]];
    for (id path in paths) { [record addPointerEventPath:path]; }
    XCTestExpectation *finished = [[XCTestExpectation alloc] initWithDescription:@"Multi-touch delivered"];
    __block NSError *failure;
    [session synthesizeEvent:record completion:^(BOOL result, NSError *error) {
        failure = error;
        [finished fulfill];
    }];
    if ([XCTWaiter waitForExpectations:@[finished] timeout:duration + 10] != XCTWaiterResultCompleted) {
        return @"Timed out delivering the two-finger gesture.";
    }
    return failure.localizedDescription;
}
@end
