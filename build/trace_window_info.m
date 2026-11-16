#import <AppKit/AppKit.h>
#import <CoreGraphics/CoreGraphics.h>
#include <stdio.h>
const char *traceServerBounds(int number) {
  static char output[512];
  snprintf(output, sizeof(output), "missing(%d)", number);
  CFArrayRef info = CGWindowListCopyWindowInfo(kCGWindowListOptionIncludingWindow,
    (CGWindowID)number);
  if (!info) return output;
  for (NSDictionary *entry in (__bridge NSArray *)info) {
    if ([entry[(__bridge NSString *)kCGWindowNumber] intValue] != number) continue;
    CGRect rect = CGRectZero;
    CGRectMakeWithDictionaryRepresentation((__bridge CFDictionaryRef)entry[
      (__bridge NSString *)kCGWindowBounds], &rect);
    snprintf(output, sizeof(output), "(%g,%g,%g,%g) onscreen=%d layer=%d",
      rect.origin.x, rect.origin.y, rect.size.width, rect.size.height,
      [entry[(__bridge NSString *)kCGWindowIsOnscreen] boolValue],
      [entry[(__bridge NSString *)kCGWindowLayer] intValue]);
  }
  CFRelease(info);
  return output;
}
