// LAB-029 Audio Workshop: the realtime kernel.
//
// Everything a render callback runs is here, in C, because the installed 27.0 SDKs mark their own
// realtime-safe render block types "Swift is not supported for use with audio realtime threads".
// Every function a render callback may call carries AWK_REALTIME, which is clang's `nonblocking`
// attribute (the SDK's CA_REALTIME_API expands to the same attribute). WorkshopKernel.c turns
// clang's function-effect diagnostics into errors, so the build fails if one of these functions
// could allocate, free, lock, or call anything clang cannot prove non-blocking.
//
// Threads: create, destroy, and prepare run off the render thread, and prepare only while no
// render callback is running. The setters and readers are atomic and may run on any thread at any
// time, including during a render.

#ifndef AUDIO_WORKSHOP_DSP_H
#define AUDIO_WORKSHOP_DSP_H

#include <CoreAudioTypes/CoreAudioTypes.h>
#include <stdbool.h>
#include <stdint.h>

#if defined(__has_attribute)
#if __has_attribute(nonblocking)
#define AWK_REALTIME __attribute__((nonblocking))
#endif
#endif
#ifndef AWK_REALTIME
// A compiler without the attribute (the 26-family toolchain) builds the same code unchecked.
#define AWK_REALTIME
#endif

/// The most channels and frames one render call processes. A larger request renders silence and
/// returns AWKStatusTooManyFrames, the value of kAudioUnitErr_TooManyFramesToProcess.
#define AWK_MAX_CHANNELS 2
#define AWK_MAX_FRAMES 4096

#define AWKStatusOK 0
#define AWKStatusTooManyFrames (-10874)

typedef struct AWKKernel AWKKernel;

/// Parameters, each stored as a float. Values outside a parameter's range are clamped on write.
typedef enum AWKParameter {
    /// Output level in decibels, -60 to +6. Changes are ramped, never jumped.
    AWKParameterGainDecibels = 0,
    /// Low-pass cutoff in hertz, 20 to 20 000, and below 45% of the sample rate when rendered.
    AWKParameterCutoffHertz = 1,
    /// Low-pass resonance as a filter Q, 0.5 to 8.
    AWKParameterResonance = 2,
    /// 1 runs the low-pass filter, 0 crossfades it out.
    AWKParameterFilterEnabled = 3,
    /// 1 crossfades to the unprocessed signal. Panic mute still silences it.
    AWKParameterBypass = 4,
    /// 1 fades the output to silence within a few milliseconds. Only a person clears it.
    AWKParameterMute = 5,
    /// Which original loop the source renders: 0 pulse, 1 chords, 2 noise and thump.
    AWKParameterLoop = 6,
    AWKParameterCount = 7
} AWKParameter;

/// What the render callbacks have done since the last prepare. Counters only; no audio.
typedef struct AWKStats {
    uint64_t callbacks;
    uint64_t frames;
    /// Render calls refused because they asked for more than AWK_MAX_FRAMES.
    uint64_t oversizedCalls;
    /// Output samples limited to full scale.
    uint64_t clippedSamples;
    /// Non-finite samples replaced by silence (the filter state is cleared when one appears).
    uint64_t nonFiniteSamples;
    /// The largest absolute output sample of the most recent call, and since prepare.
    float lastPeak;
    float maximumPeak;
    /// The rate and channel count of the latest prepare, and how many prepares there have been.
    double sampleRate;
    uint32_t channels;
    uint32_t generation;
    /// The ramped gain factor the next sample will use, 0 when fully muted.
    float currentLevel;
} AWKStats;

/// Allocates a kernel with every buffer it will ever use. Not realtime; returns NULL on failure.
AWKKernel *AWKKernelCreate(void);
void AWKKernelDestroy(AWKKernel *kernel);

/// Resets every filter and ramp for a new rate and channel count, starts the output ramp from
/// silence, rewinds the loop, and clears the counters. Never call it while a render may run.
/// Returns false, changing nothing, for a rate outside 8 000 to 384 000 Hz or a channel count
/// outside 1 to AWK_MAX_CHANNELS.
bool AWKKernelPrepare(AWKKernel *kernel, double sampleRate, uint32_t channels);

/// Rewinds the original loop to its first sample. Not realtime.
void AWKKernelRewind(AWKKernel *kernel);

void AWKKernelSetParameter(AWKKernel *kernel, AWKParameter parameter, float value) AWK_REALTIME;
float AWKKernelParameter(const AWKKernel *kernel, AWKParameter parameter) AWK_REALTIME;
void AWKKernelReadStats(const AWKKernel *kernel, AWKStats *stats) AWK_REALTIME;

/// Renders `frameCount` frames of the original loop through the graph into `output`.
/// A buffer whose mData is NULL is pointed at the kernel's own memory, as an AU render block may.
OSStatus AWKKernelRenderLoop(AWKKernel *kernel, uint32_t frameCount, AudioBufferList *output) AWK_REALTIME;

/// Processes `input` through the graph into `output`. The two may be the same list. Channels
/// beyond the prepared count are written as silence.
OSStatus AWKKernelProcess(AWKKernel *kernel, uint32_t frameCount, const AudioBufferList *input,
                          AudioBufferList *output) AWK_REALTIME;

#endif
