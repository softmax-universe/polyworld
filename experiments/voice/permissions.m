#import <AVFoundation/AVFoundation.h>
#include <stdatomic.h>

static atomic_bool voicePermissionRequested = false;

// Checks the usage description before calling privacy-sensitive APIs.
static bool voiceMicrophoneConfigured(void) {
  id usage = [[NSBundle mainBundle]
    objectForInfoDictionaryKey:@"NSMicrophoneUsageDescription"];
  return [usage isKindOfClass:[NSString class]] && [usage length] > 0;
}

// Returns -1 when permission cannot safely be requested by this executable.
int voiceMicrophonePermission(void) {
  if (!voiceMicrophoneConfigured()) return -1;
  return (int)[AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeAudio];
}

// Requests authorization once, only when the required metadata is available.
void voiceRequestMicrophonePermission(void) {
  if (!voiceMicrophoneConfigured()) return;
  if (atomic_exchange(&voicePermissionRequested, true)) return;
  [AVCaptureDevice requestAccessForMediaType:AVMediaTypeAudio
    completionHandler:^(BOOL granted) {
      atomic_store(&voicePermissionRequested, false);
    }];
}
