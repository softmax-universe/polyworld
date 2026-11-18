#import <AVFAudio/AVFAudio.h>
#import <CoreAudio/CoreAudio.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// Reads a copied device string without opening an input or output stream.
static NSString *deviceString(AudioObjectID device,
    AudioObjectPropertySelector selector) {
  AudioObjectPropertyAddress address = {
    selector, kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain
  };
  CFStringRef value = NULL;
  UInt32 size = sizeof(value);
  if (AudioObjectGetPropertyData(device, &address, 0, NULL,
      &size, &value) != noErr || value == NULL) return @"";
  return [(NSString *)value autorelease];
}

// Counts channels on one device direction without changing its configuration.
static UInt32 deviceChannels(AudioObjectID device, bool input) {
  AudioObjectPropertyAddress address = {
    kAudioDevicePropertyStreamConfiguration,
    input ? kAudioDevicePropertyScopeInput : kAudioDevicePropertyScopeOutput,
    kAudioObjectPropertyElementMain
  };
  UInt32 size = 0;
  if (AudioObjectGetPropertyDataSize(device, &address, 0, NULL, &size) != noErr ||
      size < sizeof(AudioBufferList)) return 0;
  AudioBufferList *buffers = malloc(size);
  if (buffers == NULL) return 0;
  UInt32 count = 0;
  if (AudioObjectGetPropertyData(device, &address, 0, NULL,
      &size, buffers) == noErr) {
    for (UInt32 i = 0; i < buffers->mNumberBuffers; ++i) {
      count += buffers->mBuffers[i].mNumberChannels;
    }
  }
  free(buffers);
  return count;
}

// Reads the currently selected system default without changing it.
static AudioObjectID defaultDevice(bool input) {
  AudioObjectPropertyAddress address = {
    input ? kAudioHardwarePropertyDefaultInputDevice :
      kAudioHardwarePropertyDefaultOutputDevice,
    kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain
  };
  AudioObjectID device = kAudioObjectUnknown;
  UInt32 size = sizeof(device);
  AudioObjectGetPropertyData(kAudioObjectSystemObject, &address,
    0, NULL, &size, &device);
  return device;
}

// Excludes private processing aggregates and devices that have disappeared.
static bool deviceVisible(AudioObjectID device) {
  AudioObjectPropertyAddress address = {
    kAudioDevicePropertyDeviceIsAlive,
    kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain
  };
  UInt32 value = 1, size = sizeof(value);
  if (AudioObjectGetPropertyData(device, &address, 0, NULL,
      &size, &value) == noErr && value == 0) return false;
  address.mSelector = kAudioDevicePropertyIsHidden;
  value = 0;
  size = sizeof(value);
  if (AudioObjectHasProperty(device, &address) &&
      AudioObjectGetPropertyData(device, &address, 0, NULL,
        &size, &value) == noErr && value != 0) return false;
  return true;
}

// Returns an owned JSON device snapshot; no audio device is opened.
char *voiceAudioDevices(bool input) {
  @autoreleasepool {
    NSMutableArray *devices = [NSMutableArray array];
    NSString *failure = @"";
    AudioObjectPropertyAddress address = {
      kAudioHardwarePropertyDevices,
      kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain
    };
    UInt32 size = 0;
    OSStatus status = AudioObjectGetPropertyDataSize(kAudioObjectSystemObject,
      &address, 0, NULL, &size);
    AudioObjectID *ids = size > 0 ? malloc(size) : NULL;
    if (status == noErr && size > 0 && ids == NULL) {
      failure = @"Could not allocate the audio device list.";
    } else if (status == noErr && ids != NULL) {
      status = AudioObjectGetPropertyData(kAudioObjectSystemObject,
        &address, 0, NULL, &size, ids);
      if (status == noErr) {
        for (UInt32 i = 0; i < size / sizeof(*ids); ++i) {
          AudioObjectID device = ids[i];
          if (!deviceVisible(device) || deviceChannels(device, input) == 0) {
            continue;
          }
          NSString *uid = deviceString(device, kAudioDevicePropertyDeviceUID);
          NSString *name = deviceString(device, kAudioObjectPropertyName);
          if (uid.length == 0 || name.length == 0) continue;
          [devices addObject:@{@"id": @(device), @"uid": uid, @"name": name}];
        }
      }
    }
    free(ids);
    if (status != noErr) {
      failure = [NSString stringWithFormat:
        @"Could not list audio devices (CoreAudio %d).", (int)status];
    }
    [devices sortUsingComparator:^NSComparisonResult(id a, id b) {
      return [a[@"name"] localizedCaseInsensitiveCompare:b[@"name"]];
    }];
    NSData *json = [NSJSONSerialization dataWithJSONObject:@{
      @"devices": devices, @"default": @(defaultDevice(input)),
      @"error": failure
    } options:0 error:NULL];
    if (json == nil) return NULL;
    char *result = malloc(json.length + 1);
    if (result != NULL) {
      memcpy(result, json.bytes, json.length);
      result[json.length] = 0;
    }
    return result;
  }
}

// Releases the owned snapshot returned by voiceAudioDevices.
void voiceAudioDevicesFree(char *snapshot) {
  free(snapshot);
}

// Resolves a stable selection each start so stale numeric IDs are never reused.
uint32_t voiceAudioDeviceId(const char *uid, bool input,
    char *error, int capacity) {
  @autoreleasepool {
    AudioObjectID device = kAudioObjectUnknown;
    if (uid == NULL || uid[0] == 0) {
      device = defaultDevice(input);
    } else {
      NSString *identifier = [NSString stringWithUTF8String:uid];
      CFStringRef value = (CFStringRef)identifier;
      AudioObjectPropertyAddress address = {
        kAudioHardwarePropertyTranslateUIDToDevice,
        kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain
      };
      UInt32 size = sizeof(device);
      AudioObjectGetPropertyData(kAudioObjectSystemObject, &address,
        sizeof(value), &value, &size, &device);
    }
    if (device == kAudioObjectUnknown || !deviceVisible(device) ||
        deviceChannels(device, input) == 0) {
      snprintf(error, capacity, "The selected %s is unavailable. Choose a device.",
        input ? "microphone" : "speaker");
      return kAudioObjectUnknown;
    }
    if (capacity > 0) error[0] = 0;
    return device;
  }
}

// Selects one stopped engine's device without changing the system default.
bool voiceAudioSelectDevice(void *handle, bool input, const char *uid,
    char *error, int capacity) {
  @autoreleasepool {
    @try {
      AVAudioEngine *engine = (AVAudioEngine *)handle;
      if (engine == nil || engine.running) {
        snprintf(error, capacity, "Stop conversation before changing audio devices.");
        return false;
      }
      // An empty UID keeps AVAudioEngine's normal system-default behavior.
      if (uid == NULL || uid[0] == 0) return true;
      AudioObjectID device = voiceAudioDeviceId(uid, input, error, capacity);
      if (device == kAudioObjectUnknown) return false;
      // Preserve AVAudioEngine's combined route for the current defaults.
      // Its shared HAL unit cannot be rebound to an input-only device safely.
      if (device == defaultDevice(input)) return true;
      AVAudioIONode *node = input ? (AVAudioIONode *)engine.inputNode :
        (AVAudioIONode *)engine.outputNode;
      AudioUnit unit = node.audioUnit;
      if (unit == NULL || node.voiceProcessingEnabled) {
        snprintf(error, capacity,
          "Select audio devices before enabling echo cancellation.");
        return false;
      }
      OSStatus status = AudioUnitSetProperty(unit,
        kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
        &device, sizeof(device));
      AudioObjectID selected = kAudioObjectUnknown;
      UInt32 size = sizeof(selected);
      if (status == noErr) {
        status = AudioUnitGetProperty(unit, kAudioOutputUnitProperty_CurrentDevice,
          kAudioUnitScope_Global, 0, &selected, &size);
      }
      if (status != noErr || selected != device) {
        snprintf(error, capacity, "Could not select the %s (CoreAudio %d).",
          input ? "microphone" : "speaker", (int)status);
        return false;
      }
      if (capacity > 0) error[0] = 0;
      return true;
    } @catch (NSException *exception) {
      snprintf(error, capacity, "Could not select audio device: %s",
        exception.reason.UTF8String);
      return false;
    }
  }
}
