// SPDX-License-Identifier: GPL-3.0-or-later
#import <ScreenCaptureKit/ScreenCaptureKit.h>
#import <AppKit/AppKit.h>
#include <QEventLoop>
#include <QImage>
#include <QPoint>
#include <QString>

// The picker authorizes only the display the user selects for this capture.
@interface TodoDisplayPicker : NSObject <SCContentSharingPickerObserver, SCStreamOutput, SCStreamDelegate>
@property(strong) SCStream *captureStream;
@property CGFloat scale;
@property CGPoint origin;
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
    config.pixelFormat = kCVPixelFormatType_32BGRA;
    config.capturesAudio = NO;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!self.finish || self.captureStream) return;
        self.scale = scale;
        self.origin = origin;
        SCStream *capture = [[SCStream alloc] initWithFilter:filter configuration:config delegate:self];
        self.captureStream = capture;
        NSError *failure = nil;
        if (![capture addStreamOutput:self type:SCStreamOutputTypeScreen sampleHandlerQueue:dispatch_get_main_queue() error:&failure]) {
            [self contentSharingPickerStartDidFailWithError:failure];
            return;
        }
        [capture startCaptureWithCompletionHandler:^(NSError *err) {
            if (err) [self contentSharingPickerStartDidFailWithError:err];
        }];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 8 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            if (self.finish && self.captureStream == capture)
                self.finish({}, {}, QStringLiteral("The selected display did not return a frame."));
        });
    });
}

- (void)stream:(SCStream *)stream didStopWithError:(NSError *)error {
    [self contentSharingPickerStartDidFailWithError:error];
}

- (void)stream:(SCStream *)stream didOutputSampleBuffer:(CMSampleBufferRef)sample ofType:(SCStreamOutputType)type {
    if (!self.finish || type != SCStreamOutputTypeScreen || !CMSampleBufferIsValid(sample)) return;
    NSArray *attachments = (__bridge NSArray *)CMSampleBufferGetSampleAttachmentsArray(sample, false);
    NSNumber *status = attachments.firstObject[SCStreamFrameInfoStatus];
    if (!status || status.integerValue != SCFrameStatusComplete) return;
    CVPixelBufferRef buffer = CMSampleBufferGetImageBuffer(sample);
    if (!buffer || CVPixelBufferGetPixelFormatType(buffer) != kCVPixelFormatType_32BGRA ||
        CVPixelBufferLockBaseAddress(buffer, kCVPixelBufferLock_ReadOnly) != kCVReturnSuccess) return;
    QImage frame(static_cast<const uchar *>(CVPixelBufferGetBaseAddress(buffer)),
        CVPixelBufferGetWidth(buffer), CVPixelBufferGetHeight(buffer),
        CVPixelBufferGetBytesPerRow(buffer), QImage::Format_ARGB32_Premultiplied);
    QImage copy = frame.copy();
    CVPixelBufferUnlockBaseAddress(buffer, kCVPixelBufferLock_ReadOnly);
    copy.setDevicePixelRatio(self.scale);
    self.finish(copy, QPoint(qRound(self.origin.x), qRound(self.origin.y)), {});
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
    if (observer.captureStream) {
        [observer.captureStream stopCaptureWithCompletionHandler:^(NSError *) {}];
        observer.captureStream = nil;
    }
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
