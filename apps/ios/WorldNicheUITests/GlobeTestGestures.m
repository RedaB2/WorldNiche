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
        [record addPointerEventPath:path];
    }
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
