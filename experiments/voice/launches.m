#import <AppKit/AppKit.h>
#include <stdatomic.h>
#include <stdio.h>
#include <unistd.h>

// Distinguishes the launched app from a terminal's direct child process.
bool voiceLaunchedApplication(const char *identifier) {
  NSBundle *bundle = [NSBundle mainBundle];
  return [[[NSProcessInfo processInfo] environment]
    [@"POLYWORLD_VOICE_APPLICATION"] isEqualToString:@"1"] &&
    [[bundle bundlePath] hasSuffix:@".app"] &&
    [[bundle bundleIdentifier] isEqualToString:
      [NSString stringWithUTF8String:identifier]];
}

// AppKit's Quit menu exits directly instead of returning to the Nim loop.
void voiceObserveTermination(void) {
  [[NSNotificationCenter defaultCenter]
    addObserverForName:NSApplicationWillTerminateNotification
    object:nil queue:nil usingBlock:^(NSNotification *notification) {
      const char *path = getenv("POLYWORLD_VOICE_COMPLETION");
      if (path == NULL) return;
      FILE *file = fopen(path, "w");
      if (file != NULL) {
        fputs("ok", file);
        fclose(file);
      }
    }];
}

// Keeps credentials in memory while LaunchServices establishes app identity.
int voiceLaunchApplication(const char *path, const char *completion) {
  @autoreleasepool {
    NSWorkspaceOpenConfiguration *configuration =
      [NSWorkspaceOpenConfiguration configuration];
    configuration.createsNewApplicationInstance = YES;
    configuration.allowsRunningApplicationSubstitution = NO;
    configuration.addsToRecentItems = NO;
    NSArray *arguments = [[NSProcessInfo processInfo] arguments];
    configuration.arguments = [arguments subarrayWithRange:
      NSMakeRange(1, arguments.count - 1)];
    NSMutableDictionary *environment =
      [[[NSProcessInfo processInfo] environment] mutableCopy];
    environment[@"POLYWORLD_VOICE_APPLICATION"] = @"1";
    environment[@"POLYWORLD_VOICE_COMPLETION"] =
      [NSString stringWithUTF8String:completion];
    environment[@"POLYWORLD_VOICE_DIRECTORY"] =
      [[NSFileManager defaultManager] currentDirectoryPath];
    configuration.environment = environment;
    [environment release];
    __block NSRunningApplication *application = nil;
    __block atomic_bool completed = false;
    [[NSWorkspace sharedWorkspace]
      openApplicationAtURL:[NSURL fileURLWithPath:
        [NSString stringWithUTF8String:path]]
      configuration:configuration
      completionHandler:^(NSRunningApplication *launched, NSError *error) {
        if (error != nil) {
          fprintf(stderr, "Voice app launch failed: %s\n",
            [[error localizedDescription] UTF8String]);
        }
        application = [launched retain];
        atomic_store(&completed, true);
      }];
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:30];
    while (!atomic_load(&completed)) {
      if ([deadline timeIntervalSinceNow] <= 0) {
        fprintf(stderr, "Voice app launch timed out.\n");
        return 1;
      }
      [[NSRunLoop currentRunLoop] runUntilDate:
        [NSDate dateWithTimeIntervalSinceNow:0.05]];
      usleep(10000);
    }
    if (application == nil) return 1;
    while (![application isTerminated]) {
      [[NSRunLoop currentRunLoop] runUntilDate:
        [NSDate dateWithTimeIntervalSinceNow:0.05]];
      usleep(10000);
    }
    [application release];
    return 0;
  }
}
