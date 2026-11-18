#import <AVFoundation/AVFoundation.h>
#include <math.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

bool voiceAudioSelectDevice(void *engine, bool input, const char *uid,
  char *error, int capacity);

enum {
  VoiceRate = 24000,
  CaptureFrames = VoiceRate * 4,
  PlaybackFrames = VoiceRate * 30,
  MaximumInputFrames = 16384
};

typedef struct {
  _Atomic(int16_t) *samples;
  uint64_t capacity;
  atomic_uint_fast64_t read, write, discard;
} VoiceRing;

typedef struct {
  AVAudioEngine *engine;
  AVAudioSourceNode *source;
  AVAudioConverter *converter;
  AVAudioPCMBuffer *converted, *conversionInput;
  VoiceRing input, output;
  atomic_int failure;
  atomic_uint_fast64_t playbackGeneration;
  atomic_uint_fast64_t graphGeneration;
  atomic_bool configurationChanged;
  atomic_uint_fast64_t capturedFrames, convertedFrames;
  atomic_uint tapPeak, pcmPeak;
  pthread_mutex_t captureLock;
  id owner, configurationObserver;
  bool capturing, installedTap, voiceProcessing, captureGraph, playing;
  char *inputDevice, *outputDevice;
  int restartAttempts;
  NSTimeInterval recoveryDeadline;
  char error[512];
  char diagnostics[256];
} VoiceDuplex;

@interface VoiceDuplexOwner : NSObject {
@public
  VoiceDuplex *state;
}
@end

@implementation VoiceDuplexOwner
// Keeps native state alive until any already-running callbacks have returned.
- (void)dealloc {
  pthread_mutex_destroy(&state->captureLock);
  free(state->input.samples);
  free(state->output.samples);
  free(state->inputDevice);
  free(state->outputDevice);
  free(state);
  [super dealloc];
}
@end

// Allocates a fixed-size queue without touching an audio device.
static bool initializeRing(VoiceRing *ring, uint64_t capacity) {
  ring->samples = calloc(capacity, sizeof(*ring->samples));
  ring->capacity = capacity;
  atomic_init(&ring->read, 0);
  atomic_init(&ring->write, 0);
  atomic_init(&ring->discard, 0);
  return ring->samples != NULL;
}

// Includes discarded frames when computing the live queue's read position.
static uint64_t readablePosition(VoiceRing *ring) {
  uint64_t read = atomic_load_explicit(&ring->read, memory_order_acquire);
  uint64_t discard = atomic_load_explicit(&ring->discard, memory_order_acquire);
  return read > discard ? read : discard;
}

// Appends whole samples without allocating or overwriting unread audio.
static bool writeRing(VoiceRing *ring, const int16_t *samples, uint64_t count) {
  uint64_t write = atomic_load_explicit(&ring->write, memory_order_relaxed);
  uint64_t read = readablePosition(ring);
  if (count > ring->capacity - (write - read)) return false;
  for (uint64_t i = 0; i < count; ++i) {
    atomic_store_explicit(&ring->samples[(write + i) % ring->capacity],
      samples[i], memory_order_relaxed);
  }
  atomic_store_explicit(&ring->write, write + count, memory_order_release);
  return true;
}

// Reads available samples on the caller thread with a bounded destination.
static uint64_t readRing(VoiceRing *ring, int16_t *samples, uint64_t capacity) {
  uint64_t read = readablePosition(ring);
  uint64_t write = atomic_load_explicit(&ring->write, memory_order_acquire);
  uint64_t count = write - read;
  if (count > capacity) count = capacity;
  for (uint64_t i = 0; i < count; ++i) {
    samples[i] = atomic_load_explicit(
      &ring->samples[(read + i) % ring->capacity], memory_order_relaxed);
  }
  atomic_store_explicit(&ring->read, read + count, memory_order_release);
  return count;
}

// Discards queued audio without racing the queue's sole consumer.
static void discardRing(VoiceRing *ring) {
  atomic_store_explicit(&ring->discard,
    atomic_load_explicit(&ring->write, memory_order_acquire),
    memory_order_release);
}

// Produces Float32 audio for the engine from the bounded PCM16 queue.
static void renderOutput(VoiceDuplex *voice, float *output, uint32_t frames) {
  uint64_t generation = atomic_load(&voice->playbackGeneration);
  uint64_t read = readablePosition(&voice->output);
  uint64_t write = atomic_load_explicit(&voice->output.write,
    memory_order_acquire);
  uint64_t count = write - read;
  if (count > frames) count = frames;
  for (uint64_t i = 0; i < count; ++i) {
    output[i] = atomic_load_explicit(
      &voice->output.samples[(read + i) % voice->output.capacity],
      memory_order_relaxed) / 32768.0f;
  }
  for (uint64_t i = count; i < frames; ++i) output[i] = 0;
  atomic_store_explicit(&voice->output.read, read + count, memory_order_release);
  if (generation != atomic_load(&voice->playbackGeneration)) {
    memset(output, 0, sizeof(float) * frames);
  }
}

// Records a bounded aggregate peak without retaining the microphone samples.
static void measureInput(VoiceDuplex *voice, AVAudioPCMBuffer *buffer) {
  const AudioBufferList *audio = buffer.audioBufferList;
  double peak = 0;
  for (UInt32 i = 0; i < audio->mNumberBuffers; ++i) {
    const AudioBuffer *part = &audio->mBuffers[i];
    if (part->mData == NULL) continue;
    switch (buffer.format.commonFormat) {
      case AVAudioPCMFormatFloat32:
        for (UInt32 j = 0; j < part->mDataByteSize / sizeof(float); ++j) {
          peak = fmax(peak, fabs(((float *)part->mData)[j]));
        }
        break;
      case AVAudioPCMFormatFloat64:
        for (UInt32 j = 0; j < part->mDataByteSize / sizeof(double); ++j) {
          peak = fmax(peak, fabs(((double *)part->mData)[j]));
        }
        break;
      case AVAudioPCMFormatInt16:
        for (UInt32 j = 0; j < part->mDataByteSize / sizeof(int16_t); ++j) {
          peak = fmax(peak, fabs(((int16_t *)part->mData)[j] / 32768.0));
        }
        break;
      case AVAudioPCMFormatInt32:
        for (UInt32 j = 0; j < part->mDataByteSize / sizeof(int32_t); ++j) {
          peak = fmax(peak, fabs(((int32_t *)part->mData)[j] / 2147483648.0));
        }
        break;
      default: break;
    }
  }
  unsigned value = (unsigned)(fmin(peak, 1.0) * 1000000);
  if (value > atomic_load(&voice->tapPeak)) atomic_store(&voice->tapPeak, value);
  atomic_fetch_add(&voice->capturedFrames, buffer.frameLength);
}

// Converts a hardware-format capture chunk into 24 kHz mono PCM16.
static void convertInput(VoiceDuplex *voice, AVAudioPCMBuffer *buffer) {
  measureInput(voice, buffer);
  if (buffer.frameLength > MaximumInputFrames) {
    atomic_store(&voice->failure, 1);
    return;
  }
  __block AVAudioFrameCount consumed = 0;
  NSError *error = nil;
  voice->converted.frameLength = 0;
  AVAudioConverterOutputStatus status = [voice->converter
    convertToBuffer:voice->converted error:&error
    withInputFromBlock:^AVAudioBuffer *(AVAudioPacketCount count,
      AVAudioConverterInputStatus *inputStatus) {
      if (consumed == buffer.frameLength) {
        *inputStatus = AVAudioConverterInputStatus_NoDataNow;
        return nil;
      }
      AVAudioFrameCount frames = MIN(count, buffer.frameLength - consumed);
      voice->conversionInput.frameLength = frames;
      const AudioBufferList *source = buffer.audioBufferList;
      AudioBufferList *destination = voice->conversionInput.mutableAudioBufferList;
      UInt32 bytesPerFrame = buffer.format.streamDescription->mBytesPerFrame;
      for (UInt32 i = 0; i < source->mNumberBuffers; ++i) {
        memcpy(destination->mBuffers[i].mData,
          (char *)source->mBuffers[i].mData + consumed * bytesPerFrame,
          frames * bytesPerFrame);
      }
      consumed += frames;
      *inputStatus = AVAudioConverterInputStatus_HaveData;
      return voice->conversionInput;
    }];
  if (status == AVAudioConverterOutputStatus_Error || error != nil) {
    atomic_store(&voice->failure, 2);
    return;
  }
  unsigned peak = 0;
  for (AVAudioFrameCount i = 0; i < voice->converted.frameLength; ++i) {
    unsigned sample = abs((int)voice->converted.int16ChannelData[0][i]);
    if (sample > peak) peak = sample;
  }
  if (peak > atomic_load(&voice->pcmPeak)) atomic_store(&voice->pcmPeak, peak);
  atomic_fetch_add(&voice->convertedFrames, voice->converted.frameLength);
  if (!writeRing(&voice->input, voice->converted.int16ChannelData[0],
      voice->converted.frameLength)) {
    atomic_store(&voice->failure, 3);
  }
}

// Stores native setup failures as bounded text for the Nim exception boundary.
static bool reportError(VoiceDuplex *voice, NSString *message) {
  snprintf(voice->error, sizeof(voice->error), "%s",
    message != nil ? [message UTF8String] : "Unknown native audio error.");
  return false;
}

// Identifies the failed setup step and client formats instead of an OS code alone.
static bool reportSetupError(VoiceDuplex *voice, NSString *stage,
    NSString *message) {
  @try {
    AVAudioFormat *input = voice->captureGraph ?
      [voice->engine.inputNode outputFormatForBus:0] : nil;
    AVAudioFormat *output = [voice->engine.outputNode inputFormatForBus:0];
    return reportError(voice, [NSString stringWithFormat:
      @"Could not %@. Input: %.0f Hz/%u ch; output: %.0f Hz/%u ch. %@",
      stage, input.sampleRate, input.channelCount,
      output.sampleRate, output.channelCount, message ?: @"Unknown audio error."]);
  } @catch (NSException *exception) {
    return reportError(voice, [NSString stringWithFormat:@"Could not %@. %@",
      stage, message ?: @"Audio formats are unavailable."]);
  }
}

// Builds resampling state without starting a microphone or playback device.
static bool prepareConverter(VoiceDuplex *voice, AVAudioFormat *input) {
  if (input.sampleRate < 8000 || input.sampleRate > 192000 ||
      input.channelCount == 0 || input.channelCount > 64) {
    return reportError(voice, [NSString stringWithFormat:
      @"The microphone has an unavailable or unsupported format: %.0f Hz, %u channels. "
      "Choose the macOS default microphone and try again.",
      input.sampleRate, input.channelCount]);
  }
  AVAudioFormat *format = [[AVAudioFormat alloc]
    initWithCommonFormat:AVAudioPCMFormatInt16 sampleRate:VoiceRate
    channels:1 interleaved:YES];
  voice->converter = [[AVAudioConverter alloc]
    initFromFormat:input toFormat:format];
  uint32_t capacity = (uint32_t)ceil(MaximumInputFrames *
    (double)VoiceRate / input.sampleRate) + 64;
  voice->converted = [[AVAudioPCMBuffer alloc]
    initWithPCMFormat:format frameCapacity:capacity];
  voice->conversionInput = [[AVAudioPCMBuffer alloc]
    initWithPCMFormat:input frameCapacity:MaximumInputFrames];
  [format release];
  if (voice->converter == nil || voice->converted == nil ||
      voice->conversionInput == nil) {
    return reportError(voice, @"Could not prepare microphone conversion.");
  }
  voice->converter.primeMethod = AVAudioConverterPrimeMethod_None;
  // Select one microphone channel instead of an implicit discrete-layout mix.
  voice->converter.channelMap = @[@0];
  return true;
}

// Removes graph callbacks and objects after hardware rendering has stopped.
static void releaseGraph(VoiceDuplex *voice) {
  if (voice->configurationObserver != nil) {
    [[NSNotificationCenter defaultCenter]
      removeObserver:voice->configurationObserver];
    [voice->configurationObserver release];
    voice->configurationObserver = nil;
  }
  atomic_fetch_add(&voice->graphGeneration, 1);
  [voice->engine stop];
  if (voice->installedTap) {
    [voice->engine.inputNode removeTapOnBus:0];
  }
  voice->installedTap = false;
  pthread_mutex_lock(&voice->captureLock);
  [voice->converter release];
  [voice->converted release];
  [voice->conversionInput release];
  voice->converter = nil;
  voice->converted = nil;
  voice->conversionInput = nil;
  pthread_mutex_unlock(&voice->captureLock);
  [voice->engine release];
  [voice->source release];
  voice->engine = nil;
  voice->source = nil;
  voice->captureGraph = false;
}

// Creates dormant buffers while leaving microphone permission and devices alone.
void *voiceDuplexCreate(void) {
  VoiceDuplex *voice = calloc(1, sizeof(*voice));
  if (voice == NULL) return NULL;
  if (!initializeRing(&voice->input, CaptureFrames) ||
      !initializeRing(&voice->output, PlaybackFrames)) {
    free(voice->input.samples);
    free(voice->output.samples);
    free(voice);
    return NULL;
  }
  atomic_init(&voice->failure, 0);
  atomic_init(&voice->playbackGeneration, 0);
  atomic_init(&voice->graphGeneration, 0);
  atomic_init(&voice->configurationChanged, false);
  atomic_init(&voice->capturedFrames, 0);
  atomic_init(&voice->convertedFrames, 0);
  atomic_init(&voice->tapPeak, 0);
  atomic_init(&voice->pcmPeak, 0);
  if (pthread_mutex_init(&voice->captureLock, NULL) != 0) {
    free(voice->input.samples);
    free(voice->output.samples);
    free(voice);
    return NULL;
  }
  VoiceDuplexOwner *owner = [[VoiceDuplexOwner alloc] init];
  owner->state = voice;
  voice->owner = owner;
  voice->voiceProcessing = true;
  return voice;
}

// Copies route choices while leaving all devices and permission prompts closed.
void *voiceAudioCreate(bool voiceProcessing, const char *inputDevice,
    const char *outputDevice) {
  VoiceDuplex *voice = voiceDuplexCreate();
  if (voice == NULL) return NULL;
  voice->voiceProcessing = voiceProcessing;
  voice->inputDevice = strdup(inputDevice != NULL ? inputDevice : "");
  voice->outputDevice = strdup(outputDevice != NULL ? outputDevice : "");
  if (voice->inputDevice == NULL || voice->outputDevice == NULL) {
    [voice->owner release];
    return NULL;
  }
  return voice;
}

// Reports callback failures without sharing mutable Objective-C error objects.
const char *voiceDuplexError(void *handle) {
  VoiceDuplex *voice = handle;
  switch (atomic_load(&voice->failure)) {
    case 1: return "The microphone supplied an oversized audio chunk.";
    case 2: return "Could not convert microphone audio.";
    case 3: return "The microphone queue filled. Restart Conversation.";
    default: return voice->error;
  }
}

// Reports aggregate levels before and after local resampling for diagnosis.
const char *voiceAudioCaptureDiagnostics(void *handle) {
  VoiceDuplex *voice = handle;
  snprintf(voice->diagnostics, sizeof(voice->diagnostics),
    "Tap: %llu frames, peak %.6f; PCM: %llu frames, peak %.6f.",
    (unsigned long long)atomic_load(&voice->capturedFrames),
    atomic_load(&voice->tapPeak) / 1000000.0,
    (unsigned long long)atomic_load(&voice->convertedFrames),
    atomic_load(&voice->pcmPeak) / 32768.0);
  return voice->diagnostics;
}

// Stops hardware capture; no microphone remains active in Text mode.
void voiceDuplexStop(void *handle) {
  VoiceDuplex *voice = handle;
  if (voice == NULL) return;
  voice->capturing = false;
  voice->playing = false;
  @autoreleasepool {
    releaseGraph(voice);
  }
}

// Starts the chosen output, adding microphone input only on an explicit request.
static bool startAudio(VoiceDuplex *voice, bool capture) {
  @autoreleasepool {
    NSString *stage = @"create the audio engine";
    bool started = false;
    @try {
      voice->error[0] = 0;
      atomic_store(&voice->failure, 0);
      if (capture ? voice->capturing : (voice->capturing || voice->playing)) {
        started = true;
        return true;
      }
      voice->playing = false;
      if (voice->engine != nil && voice->captureGraph != capture) {
        releaseGraph(voice);
      }
      voice->restartAttempts = 0;
      voice->recoveryDeadline = 0;
      if (capture) {
        atomic_store(&voice->capturedFrames, 0);
        atomic_store(&voice->convertedFrames, 0);
        atomic_store(&voice->tapPeak, 0);
        atomic_store(&voice->pcmPeak, 0);
      }
      if (voice->engine == nil) {
        voice->engine = [[AVAudioEngine alloc] init];
        voice->captureGraph = capture;
        stage = @"select the speaker";
        if (!voiceAudioSelectDevice(voice->engine, false, voice->outputDevice,
            voice->error, sizeof(voice->error))) return false;
        if (capture) {
          stage = @"select the microphone";
          if (!voiceAudioSelectDevice(voice->engine, true, voice->inputDevice,
              voice->error, sizeof(voice->error))) return false;
        }
        NSError *error = nil;
        AVAudioInputNode *input = capture ? voice->engine.inputNode : nil;
        if (capture && voice->voiceProcessing) {
          stage = @"enable echo cancellation";
          if (![input setVoiceProcessingEnabled:YES error:&error]) {
            return reportSetupError(voice, stage, error.localizedDescription);
          }
          if (!input.voiceProcessingEnabled ||
              !voice->engine.outputNode.voiceProcessingEnabled) {
            return reportError(voice, @"Echo cancellation could not be enabled.");
          }
        }
        AVAudioFormat *inputFormat = capture ? [input outputFormatForBus:0] : nil;
        if (capture && !prepareConverter(voice, inputFormat)) return false;
        stage = @"connect speaker audio";
        AVAudioFormat *outputFormat = [[AVAudioFormat alloc]
          initStandardFormatWithSampleRate:VoiceRate channels:1];
        VoiceDuplexOwner *owner = voice->owner;
        voice->configurationObserver = [[[NSNotificationCenter defaultCenter]
          addObserverForName:AVAudioEngineConfigurationChangeNotification
          object:voice->engine queue:nil usingBlock:^(NSNotification *note) {
            atomic_store(&owner->state->configurationChanged, true);
          }] retain];
        uint64_t generation = atomic_load(&voice->graphGeneration);
        voice->source = [[AVAudioSourceNode alloc]
          initWithFormat:outputFormat
          renderBlock:^OSStatus(BOOL *silence, const AudioTimeStamp *timestamp,
            AVAudioFrameCount frames, AudioBufferList *output) {
            VoiceDuplex *active = owner->state;
            if (generation != atomic_load(&active->graphGeneration)) {
              memset(output->mBuffers[0].mData, 0, frames * sizeof(float));
              *silence = YES;
              return noErr;
            }
            renderOutput(active, output->mBuffers[0].mData, frames);
            *silence = NO;
            return noErr;
          }];
        [voice->engine attachNode:voice->source];
        [voice->engine connect:voice->source to:voice->engine.mainMixerNode
          format:outputFormat];
        [outputFormat release];
        if (capture && voice->voiceProcessing) {
          // VoiceProcessingIO requires identical input and output client formats.
          // The mixer converts speech to the microphone's processed format.
          [voice->engine connect:voice->engine.mainMixerNode
            to:voice->engine.outputNode format:inputFormat];
          if (![[input outputFormatForBus:0]
              isEqual:[voice->engine.outputNode inputFormatForBus:0]]) {
            return reportSetupError(voice, stage,
              @"Echo cancellation requires matching input and output formats.");
          }
        }
        if (capture) {
          stage = @"install microphone capture";
          [input installTapOnBus:0 bufferSize:1024 format:inputFormat
            block:^(AVAudioPCMBuffer *buffer, AVAudioTime *time) {
              @autoreleasepool {
                VoiceDuplex *active = owner->state;
                pthread_mutex_lock(&active->captureLock);
                if (generation == atomic_load(&active->graphGeneration)) {
                  convertInput(active, buffer);
                }
                pthread_mutex_unlock(&active->captureLock);
              }
            }];
          voice->installedTap = true;
        }
      }
      discardRing(&voice->input);
      pthread_mutex_lock(&voice->captureLock);
      [voice->converter reset];
      pthread_mutex_unlock(&voice->captureLock);
      NSError *error = nil;
      atomic_store(&voice->configurationChanged, false);
      stage = @"prepare audio";
      [voice->engine prepare];
      stage = @"start audio";
      if (![voice->engine startAndReturnError:&error]) {
        return reportSetupError(voice, stage, error.localizedDescription);
      }
      voice->capturing = capture;
      voice->playing = !capture;
      started = true;
      return true;
    } @catch (NSException *exception) {
      [voice->engine stop];
      return reportSetupError(voice, stage, exception.reason);
    } @finally {
      if (!started) {
        voice->capturing = false;
        voice->playing = false;
        releaseGraph(voice);
      }
    }
  }
}

// Starts capture only after the caller checks the user's microphone permission.
bool voiceDuplexStart(void *handle) {
  return startAudio(handle, true);
}

// Recovers Bluetooth profile transitions on the caller thread while listening.
bool voiceDuplexPoll(void *handle) {
  VoiceDuplex *voice = handle;
  if ((!voice->capturing && !voice->playing) ||
      atomic_load(&voice->failure) != 0) return true;
  @autoreleasepool {
    @try {
      bool changed = atomic_exchange(&voice->configurationChanged, false);
      if (voice->engine.running) {
        voice->recoveryDeadline = 0;
        return true;
      }
      NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
      if (voice->recoveryDeadline == 0) voice->recoveryDeadline = now + 2;
      // The engine stops before its configuration notification is delivered.
      if (!changed) {
        if (now < voice->recoveryDeadline) return true;
        return reportError(voice,
          @"The audio device stopped. Start conversation again.");
      }
      if (++voice->restartAttempts > 3) {
        return reportError(voice,
          @"The audio device keeps changing. Start conversation again.");
      }
      if (voice->capturing) {
        AVAudioFormat *input = [voice->engine.inputNode outputFormatForBus:0];
        AVAudioFormat *output = [voice->engine.outputNode inputFormatForBus:0];
        if (![input isEqual:voice->converter.inputFormat] ||
            (voice->voiceProcessing && ![input isEqual:output])) {
          return reportSetupError(voice, @"resume audio",
            @"The device format changed. Enable the microphone again.");
        }
      }
      NSError *error = nil;
      if (![voice->engine startAndReturnError:&error]) {
        return reportSetupError(voice, @"resume conversation audio",
          error.localizedDescription);
      }
      return true;
    } @catch (NSException *exception) {
      return reportSetupError(voice, @"resume conversation audio",
        exception.reason);
    }
  }
}

// Reports processed microphone frames waiting for the caller thread.
int voiceDuplexAvailable(void *handle) {
  VoiceDuplex *voice = handle;
  uint64_t write = atomic_load_explicit(&voice->input.write,
    memory_order_acquire);
  return (int)(write - readablePosition(&voice->input));
}

// Drains a bounded amount of processed microphone audio into caller memory.
int voiceDuplexRead(void *handle, int16_t *samples, int capacity) {
  VoiceDuplex *voice = handle;
  return (int)readRing(&voice->input, samples, (uint64_t)capacity);
}

// Opens output alone for plain playback, or uses the active conversation graph.
bool voiceDuplexQueue(void *handle, const int16_t *samples, int count) {
  VoiceDuplex *voice = handle;
  if (voice->voiceProcessing && !voice->capturing) {
    return reportError(voice, @"Start Conversation before playing its voice.");
  }
  if (!voice->capturing && !voice->playing && !startAudio(voice, false)) {
    return false;
  }
  if (!writeRing(&voice->output, samples, (uint64_t)count)) {
    return reportError(voice, @"Speech playback queue is full.");
  }
  return true;
}

// Discards pending speech without stopping microphone capture.
void voiceDuplexFlush(void *handle) {
  VoiceDuplex *voice = handle;
  if (voice == NULL) return;
  discardRing(&voice->output);
  atomic_fetch_add(&voice->playbackGeneration, 1);
}

// Reports the remaining speech frames without pumping an audio callback.
int voiceDuplexQueued(void *handle) {
  VoiceDuplex *voice = handle;
  uint64_t write = atomic_load_explicit(&voice->output.write,
    memory_order_acquire);
  uint64_t read = readablePosition(&voice->output);
  return (int)(write - read);
}

// Measures frames rendered since the last interruption or fresh utterance.
int voiceDuplexMilliseconds(void *handle) {
  VoiceDuplex *voice = handle;
  uint64_t read = readablePosition(&voice->output);
  uint64_t start = atomic_load_explicit(&voice->output.discard,
    memory_order_acquire);
  return (int)((read - start) * 1000 / VoiceRate);
}

// Releases graph callbacks before their fixed-size buffers and state are freed.
void voiceDuplexClose(void *handle) {
  VoiceDuplex *voice = handle;
  if (voice == NULL) return;
  @autoreleasepool {
    voiceDuplexStop(voice);
    releaseGraph(voice);
  }
  [voice->owner release];
}

// Exercises queues and resampling without constructing an engine or microphone.
bool voiceDuplexTest(void) {
  VoiceDuplex *voice = voiceDuplexCreate();
  if (voice == NULL) return false;
  bool okay = true;
  @autoreleasepool {
    int16_t samples[] = {0, 16384, -16384, -32768};
    float output[8] = {0};
    okay &= writeRing(&voice->output, samples, 4);
    renderOutput(voice, output, 8);
    okay &= output[0] == 0 && output[1] == 0.5f &&
      output[2] == -0.5f && output[3] == -1.0f && output[7] == 0;
    okay &= voiceDuplexQueued(voice) == 0;
    okay &= writeRing(&voice->output, samples, 4);
    voiceDuplexFlush(voice);
    okay &= voiceDuplexQueued(voice) == 0;
    okay &= writeRing(&voice->output, samples + 1, 2);
    renderOutput(voice, output, 2);
    okay &= output[0] == 0.5f && output[1] == -0.5f;
    okay &= !writeRing(&voice->output, samples, PlaybackFrames + 1);
    for (int i = 0; i < 10000; ++i) {
      okay &= writeRing(&voice->input, samples, 4);
      int16_t copy[4];
      okay &= readRing(&voice->input, copy, 4) == 4;
      okay &= memcmp(copy, samples, sizeof(copy)) == 0;
    }
    int rates[] = {16000, 24000, 48000};
    for (int rateIndex = 0; rateIndex < 3; ++rateIndex) {
      int rate = rates[rateIndex];
      VoiceDuplex *converted = voiceDuplexCreate();
      AVAudioFormat *format = [[AVAudioFormat alloc]
        initStandardFormatWithSampleRate:rate channels:1];
      AVAudioPCMBuffer *input = [[AVAudioPCMBuffer alloc]
        initWithPCMFormat:format frameCapacity:rate / 10];
      input.frameLength = rate / 10;
      for (int i = 0; i < rate / 10; ++i) {
        input.floatChannelData[0][i] = 0.5f * sinf(i * 400 * 2 * M_PI / rate);
      }
      bool conversionOkay = prepareConverter(converted, format);
      if (conversionOkay) {
        for (int i = 0; i < 10; ++i) convertInput(converted, input);
        int16_t samples[25000];
        uint64_t count = readRing(&converted->input, samples, 25000);
        double energy = 0;
        for (uint64_t i = 0; i < count; ++i) {
          double value = samples[i] / 32768.0;
          energy += value * value;
        }
        double rms = count > 0 ? sqrt(energy / count) : 0;
        conversionOkay = count >= 23000 && count <= 24000 &&
          rms > 0.33 && rms < 0.37 && atomic_load(&converted->failure) == 0;
        if (!conversionOkay) {
          fprintf(stderr, "Microphone conversion failed: %d Hz, %llu frames, "
            "RMS %.6f\n", rate, (unsigned long long)count, rms);
        }
      }
      okay &= conversionOkay;
      [input release];
      [format release];
      voiceDuplexClose(converted);
    }
    // Built-in voice processing can expose nine discrete channels at 48 kHz.
    // Other channels must not cancel or replace the microphone signal.
    for (int interleaved = 0; interleaved < 2; ++interleaved) {
      VoiceDuplex *converted = voiceDuplexCreate();
      AVAudioChannelLayout *layout = [[AVAudioChannelLayout alloc]
        initWithLayoutTag:kAudioChannelLayoutTag_DiscreteInOrder | 9];
      AVAudioFormat *format = [[AVAudioFormat alloc]
        initWithCommonFormat:AVAudioPCMFormatFloat32 sampleRate:48000
        interleaved:interleaved channelLayout:layout];
      AVAudioPCMBuffer *input = [[AVAudioPCMBuffer alloc]
        initWithPCMFormat:format frameCapacity:4800];
      input.frameLength = 4800;
      bool conversionOkay = prepareConverter(converted, format);
      if (conversionOkay) {
        for (int block = 0; block < 12; ++block) {
          for (int frame = 0; frame < 4800; ++frame) {
            float sample = block < 2 ? 0 :
              0.02f * sinf(frame * 400 * 2 * M_PI / 48000);
            for (int channel = 0; channel < 9; ++channel) {
              float *data = interleaved ? input.floatChannelData[0] + channel :
                input.floatChannelData[channel];
              data[frame * input.stride] = channel == 0 ? sample : -sample;
            }
          }
          convertInput(converted, input);
          int16_t samples[4096];
          uint64_t count = readRing(&converted->input, samples, 4096);
          double energy = 0;
          for (uint64_t frame = 0; frame < count; ++frame) {
            double sample = samples[frame] / 32768.0;
            energy += sample * sample;
          }
          double rms = count > 0 ? sqrt(energy / count) : 0;
          conversionOkay &= count >= 2300 && count <= 2400 &&
            (block < 2 ? rms == 0 : rms > 0.013 && rms < 0.015) &&
            atomic_load(&converted->failure) == 0;
        }
      }
      if (!conversionOkay) {
        fprintf(stderr, "Nine-channel conversion failed: interleaved %d\n",
          interleaved);
      }
      okay &= conversionOkay;
      [input release];
      [format release];
      [layout release];
      voiceDuplexClose(converted);
    }
  }
  voiceDuplexClose(voice);
  return okay;
}
