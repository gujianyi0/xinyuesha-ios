// SPDX-License-Identifier: GPL-3.0-or-later
#include "platform/ioshelper.h"

#import <AVFoundation/AVFoundation.h>
#import <UIKit/UIKit.h>

void fkIosPrepare(void) {
  @autoreleasepool {
    // The game mixes short sound effects through SoLoud/miniaudio and music
    // through Qt Multimedia. A Playback session keeps both audible even when
    // the ring/silent switch is set to silent, which is what players expect.
    AVAudioSession *session = [AVAudioSession sharedInstance];
    NSError *error = nil;
    [session setCategory:AVAudioSessionCategoryPlayback error:&error];
    if (error != nil) {
      NSLog(@"[FreeKill] AVAudioSession category error: %@", error);
      error = nil;
    }
    [session setActive:YES error:&error];
    if (error != nil) {
      NSLog(@"[FreeKill] AVAudioSession activate error: %@", error);
    }

    // Matches Android's behavior: the table stays visible during a match.
    [UIApplication sharedApplication].idleTimerDisabled = YES;
  }
}

void fkIosExcludeFromBackup(const char *path) {
  if (path == nullptr) return;
  @autoreleasepool {
    NSString *value = [NSString stringWithUTF8String:path];
    if (value == nil) return;
    NSURL *url = [NSURL fileURLWithPath:value isDirectory:YES];
    NSError *error = nil;
    if (![url setResourceValue:@YES forKey:NSURLIsExcludedFromBackupKey error:&error]) {
      NSLog(@"[FreeKill] failed to exclude %@ from backup: %@", value, error);
    }
  }
}

int fkIosPlayGameHaptic(int kind) {
  if (kind < 0 || kind > 2 || ![NSThread isMainThread]) return 0;
  @autoreleasepool {
    if ([UIApplication sharedApplication].applicationState != UIApplicationStateActive) return 0;
    const UIImpactFeedbackStyle style = kind == 0 ? UIImpactFeedbackStyleMedium : UIImpactFeedbackStyleLight;
    UIImpactFeedbackGenerator *feedback = [[[UIImpactFeedbackGenerator alloc] initWithStyle:style] autorelease];
    [feedback prepare];
    [feedback impactOccurred];
    return 1;
  }
}
