// SPDX-License-Identifier: GPL-3.0-or-later
#import <ScreenCaptureKit/ScreenCaptureKit.h>
#import <AppKit/AppKit.h>
#include <QEventLoop>
#include <QImage>
#include <QPoint>
#include <QString>

// The picker authorizes only the display the user selects for this capture.
@interface TodoDisplayPicker : NSObject <SCContentSharingPickerObserver>
@property(copy) void (^finish)(QImage, QPoint, QString);
@end

@implementation TodoDisplayPicker
- (void)contentSharingPicker:(SCContentSharingPicker *)picker didCancelForStream:(SCStream *)stream {
    dispatch_async(dispatch_get_main_queue(), ^{ if (self.finish) self.finish({}, {}, {}); });
}
- (void)contentSharingPickerStartDidFailWithError:(NSError *)error {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.finish) self.finish({}, {}, QString::fromNSString(error.localizedDescription));
    });
}
- (void)contentSharingPicker:(SCContentSharingPicker *)picker didUpdateWithFilter:(SCContentFilter *)filter forStream:(SCStream *)stream {
    SCStreamConfiguration *config = [SCStreamConfiguration new];
    const CGFloat scale = filter.pointPixelScale;
    config.width = qMax(1, qRound(filter.contentRect.size.width * scale));
    config.height = qMax(1, qRound(filter.contentRect.size.height * scale));
    config.showsCursor = NO;
    CGPoint origin = filter.contentRect.origin;
    if (@available(macOS 15.2, *)) {
        if (filter.includedDisplays.count) origin = CGDisplayBounds(filter.includedDisplays.firstObject.displayID).origin;
    }
    [SCScreenshotManager captureImageWithFilter:filter configuration:config completionHandler:^(CGImageRef cg, NSError *error) {
        QImage image;
        if (cg) {
            image = QImage(CGImageGetWidth(cg), CGImageGetHeight(cg), QImage::Format_ARGB32_Premultiplied);
            CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
            CGContextRef ctx = image.isNull() ? nullptr : CGBitmapContextCreate(image.bits(), image.width(), image.height(), 8, image.bytesPerLine(), space, kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little);
            CGColorSpaceRelease(space);
            if (ctx) {
                CGContextDrawImage(ctx, CGRectMake(0, 0, image.width(), image.height()), cg);
                CGContextRelease(ctx);
                image.setDevicePixelRatio(scale);
            } else image = {};
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self.finish) self.finish(image, QPoint(qRound(origin.x), qRound(origin.y)),
                error ? QString::fromNSString(error.localizedDescription) : QString());
        });
    }];
}
@end

QImage pickFlameshotDisplay(QPoint &origin, QString &error) {
    static bool active = false;
    if (active) return {};
    active = true;
    SCContentSharingPicker *picker = SCContentSharingPicker.sharedPicker;
    TodoDisplayPicker *observer = [TodoDisplayPicker new];
    QEventLoop loop;
    QImage result;
    auto complete = [&](QImage image, QPoint point, QString reason) {
        result = image; origin = point; error = reason; loop.quit();
    };
    observer.finish = ^(QImage image, QPoint point, QString reason) { complete(image, point, reason); };
    SCContentSharingPickerConfiguration *config = [SCContentSharingPickerConfiguration new];
    config.allowedPickerModes = SCContentSharingPickerModeSingleDisplay;
    picker.defaultConfiguration = config;
    [picker addObserver:observer];
    picker.active = YES;
    [picker presentPickerUsingContentStyle:SCShareableContentStyleDisplay];
    loop.exec();
    observer.finish = nil;
    [picker removeObserver:observer];
    picker.active = NO;
    active = false;
    return result;
}

bool stickyTodoHostRunning() {
    NSURL *outer = NSBundle.mainBundle.bundleURL.URLByDeletingLastPathComponent.URLByDeletingLastPathComponent.URLByDeletingLastPathComponent;
    for (NSRunningApplication *app in [NSRunningApplication runningApplicationsWithBundleIdentifier:@"com.todo-sticky.app"]) {
        if ([app.bundleURL.URLByResolvingSymlinksInPath.path isEqualToString:outer.URLByResolvingSymlinksInPath.path]) return true;
    }
    return false;
}
