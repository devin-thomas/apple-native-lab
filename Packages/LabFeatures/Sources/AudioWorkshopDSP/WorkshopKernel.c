// LAB-029 Audio Workshop: the realtime kernel. See AudioWorkshopDSP.h for the threading contract.

#include "AudioWorkshopDSP.h"

#include <math.h>
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>

// With a compiler that knows `nonblocking`, a render path that could allocate, free, lock, or call
// an unverified function is a build error, not a warning.
#if defined(__has_attribute)
#if __has_attribute(nonblocking)
#pragma clang diagnostic error "-Wfunction-effects"
#endif
#endif

#define AWK_TWO_PI 6.283185307179586
#define AWK_LOOP_SECONDS 2.0
#define AWK_STEP_SECONDS 0.25
#define AWK_NOISE_SEED 0x2F6B4E1Du
#define AWK_UNINITIALIZED (-10867) // kAudioUnitErr_Uninitialized

struct AWKKernel {
    // Written by any thread, read by the render thread. Floats are stored as their bits.
    _Atomic uint32_t parameters[AWKParameterCount];

    // Owned by the render thread; prepare writes them only while no render runs.
    bool prepared;
    double sampleRate;
    uint32_t channels;
    float level, mute, bypassMix, filterMix;
    float levelCoefficient, muteDownCoefficient, muteUpCoefficient, mixCoefficient;
    float cutoff, resonance;
    float b0, b1, b2, a1, a2;
    float state[AWK_MAX_CHANNELS][2];
    uint64_t loopFrame, loopLength;
    uint32_t noise;
    float *scratch[AWK_MAX_CHANNELS];

    // Counters the render thread writes and any thread reads.
    _Atomic uint64_t callbacks, frames, oversizedCalls, clippedSamples, nonFiniteSamples;
    _Atomic uint32_t lastPeakBits, maximumPeakBits, levelBits, generation;
    _Atomic uint64_t sampleRateBits;
    _Atomic uint32_t preparedChannels;
};

// MARK: Small helpers, all realtime

static inline uint32_t bitsOf(float value) AWK_REALTIME {
    uint32_t bits;
    memcpy(&bits, &value, sizeof bits);
    return bits;
}

static inline float floatOf(uint32_t bits) AWK_REALTIME {
    float value;
    memcpy(&value, &bits, sizeof value);
    return value;
}

static inline float clampf(float value, float low, float high) AWK_REALTIME {
    return value < low ? low : (value > high ? high : value);
}

static inline float load(const AWKKernel *kernel, AWKParameter parameter) AWK_REALTIME {
    return floatOf(atomic_load_explicit(&kernel->parameters[parameter], memory_order_relaxed));
}

/// The value a parameter keeps after clamping, or NAN when the value is refused.
static float sanitized(AWKParameter parameter, float value) AWK_REALTIME {
    if (!isfinite(value)) return NAN;
    switch (parameter) {
    case AWKParameterGainDecibels: return clampf(value, -60.0f, 6.0f);
    case AWKParameterCutoffHertz: return clampf(value, 20.0f, 20000.0f);
    case AWKParameterResonance: return clampf(value, 0.5f, 8.0f);
    case AWKParameterFilterEnabled:
    case AWKParameterBypass:
    case AWKParameterMute: return value >= 0.5f ? 1.0f : 0.0f;
    case AWKParameterLoop: return clampf(roundf(value), 0.0f, 2.0f);
    case AWKParameterCount: return NAN;
    }
    return NAN;
}

static inline float smoothingCoefficient(double seconds, double sampleRate) AWK_REALTIME {
    return (float)(1.0 - exp(-1.0 / (seconds * sampleRate)));
}

/// RBJ low-pass biquad coefficients for the current cutoff and resonance.
static void updateFilter(AWKKernel *kernel) AWK_REALTIME {
    float nyquistLimit = (float)(kernel->sampleRate * 0.45);
    float cutoff = clampf(kernel->cutoff, 20.0f, nyquistLimit);
    float w0 = (float)(AWK_TWO_PI * cutoff / kernel->sampleRate);
    float cosine = cosf(w0);
    float alpha = sinf(w0) / (2.0f * kernel->resonance);
    float a0 = 1.0f + alpha;
    kernel->b0 = (1.0f - cosine) * 0.5f / a0;
    kernel->b1 = (1.0f - cosine) / a0;
    kernel->b2 = kernel->b0;
    kernel->a1 = -2.0f * cosine / a0;
    kernel->a2 = (1.0f - alpha) / a0;
}

/// Moves the cutoff toward its target once per call, in the log domain, so a MIDI sweep or a
/// slider drag glides instead of stepping. Coefficients are recomputed only when something moved.
static void glideFilter(AWKKernel *kernel, uint32_t frameCount) AWK_REALTIME {
    float targetCutoff = load(kernel, AWKParameterCutoffHertz);
    float targetResonance = load(kernel, AWKParameterResonance);
    float before = kernel->cutoff;
    float amount = 1.0f - expf(-(float)frameCount / (float)(0.03 * kernel->sampleRate));
    float next = before * powf(targetCutoff / before, amount);
    if (fabsf(next - targetCutoff) < 0.01f) next = targetCutoff;
    if (next != before || targetResonance != kernel->resonance) {
        kernel->cutoff = next;
        kernel->resonance = targetResonance;
        updateFilter(kernel);
    }
}

// MARK: The original loops

static inline float envelope(double t, double attack, double decay) AWK_REALTIME {
    double rise = t < attack ? t / attack : 1.0;
    return (float)(rise * exp(-t / decay));
}

static inline float sine(double hertz, double t) AWK_REALTIME {
    return sinf((float)(AWK_TWO_PI * hertz * t));
}

static const double pulseNotes[8] = {220.0, 277.18, 329.63, 440.0, 329.63, 277.18, 220.0, 164.81};
static const double chordNotes[4][3] = {
    {220.0, 261.63, 329.63}, {174.61, 220.0, 261.63}, {261.63, 329.63, 392.0}, {196.0, 246.94, 293.66},
};

/// One sample of the selected loop. Deterministic: it depends only on the sample rate, the loop,
/// and how many samples were rendered since the last rewind. Peak level stays near -6 dBFS.
static float loopSample(AWKKernel *kernel, int loop) AWK_REALTIME {
    double t = (double)kernel->loopFrame / kernel->sampleRate;
    int step = (int)(t / AWK_STEP_SECONDS);
    if (step > 7) step = 7;
    double inStep = t - step * AWK_STEP_SECONDS;

    // The noise generator advances every sample, whichever loop plays, so switching loops never
    // changes what the noise loop sounds like afterwards.
    uint32_t x = kernel->noise;
    x ^= x << 13;
    x ^= x >> 17;
    x ^= x << 5;
    kernel->noise = x;
    float white = (float)(int32_t)x / 2147483648.0f;

    float sample = 0.0f;
    switch (loop) {
    case 1: {
        int chord = (int)(t / 0.5);
        if (chord > 3) chord = 3;
        double inChord = t - chord * 0.5;
        double fadeIn = inChord < 0.01 ? inChord / 0.01 : 1.0;
        double fadeOut = (0.5 - inChord) < 0.02 ? (0.5 - inChord) / 0.02 : 1.0;
        float gate = (float)(fadeIn < fadeOut ? fadeIn : fadeOut);
        if (gate < 0.0f) gate = 0.0f;
        for (int voice = 0; voice < 3; voice++) sample += 0.1f * gate * sine(chordNotes[chord][voice], inChord);
        break;
    }
    case 2: {
        float accent = (step % 2 == 0) ? 0.18f : 0.09f;
        sample = accent * envelope(inStep, 0.001, 0.025) * white;
        if (step % 2 == 0) sample += 0.35f * envelope(inStep, 0.002, 0.12) * sine(55.0, inStep);
        break;
    }
    default:
        sample = 0.3f * envelope(inStep, 0.003, 0.09) * sine(pulseNotes[step], inStep);
        break;
    }

    kernel->loopFrame += 1;
    if (kernel->loopFrame >= kernel->loopLength) {
        kernel->loopFrame = 0;
        kernel->noise = AWK_NOISE_SEED;
    }
    return sample;
}

// MARK: Buffers

typedef struct AWKChannel {
    float *samples;
    uint32_t stride;
} AWKChannel;

/// The samples of one channel in a buffer list, interleaved or not, or NULL samples when the list
/// has no such channel.
static AWKChannel channelAt(const AudioBufferList *list, uint32_t channel) AWK_REALTIME {
    AWKChannel found = {NULL, 1};
    if (list == NULL) return found;
    uint32_t first = 0;
    for (uint32_t index = 0; index < list->mNumberBuffers; index++) {
        const AudioBuffer *buffer = &list->mBuffers[index];
        uint32_t count = buffer->mNumberChannels == 0 ? 1 : buffer->mNumberChannels;
        if (channel < first + count) {
            found.samples = buffer->mData == NULL ? NULL : (float *)buffer->mData + (channel - first);
            found.stride = count;
            return found;
        }
        first += count;
    }
    return found;
}

static uint32_t channelCount(const AudioBufferList *list) AWK_REALTIME {
    uint32_t total = 0;
    for (uint32_t index = 0; index < list->mNumberBuffers; index++) {
        uint32_t count = list->mBuffers[index].mNumberChannels;
        total += count == 0 ? 1 : count;
    }
    return total;
}

/// Points buffers without memory at the kernel's own, and sets every buffer's byte size.
static void claimOutput(AWKKernel *kernel, AudioBufferList *output, uint32_t frameCount) AWK_REALTIME {
    for (uint32_t index = 0; index < output->mNumberBuffers; index++) {
        AudioBuffer *buffer = &output->mBuffers[index];
        uint32_t count = buffer->mNumberChannels == 0 ? 1 : buffer->mNumberChannels;
        if (buffer->mData == NULL && index < AWK_MAX_CHANNELS) buffer->mData = kernel->scratch[index];
        if (buffer->mData != NULL) buffer->mDataByteSize = frameCount * count * (uint32_t)sizeof(float);
    }
}

static void silence(AudioBufferList *output, uint32_t frameCount) AWK_REALTIME {
    uint32_t channels = channelCount(output);
    for (uint32_t channel = 0; channel < channels; channel++) {
        AWKChannel out = channelAt(output, channel);
        if (out.samples == NULL) continue;
        for (uint32_t frame = 0; frame < frameCount; frame++) out.samples[frame * out.stride] = 0.0f;
    }
}

// MARK: The graph: source or input, low-pass filter, gain, bypass, panic mute, safety limit

static OSStatus render(AWKKernel *kernel, uint32_t frameCount, const AudioBufferList *input, AudioBufferList *output) AWK_REALTIME {
    if (output == NULL) return AWK_UNINITIALIZED;
    atomic_fetch_add_explicit(&kernel->callbacks, 1, memory_order_relaxed);
    if (frameCount > AWK_MAX_FRAMES) {
        atomic_fetch_add_explicit(&kernel->oversizedCalls, 1, memory_order_relaxed);
        uint32_t allowed = AWK_MAX_FRAMES;
        claimOutput(kernel, output, allowed);
        silence(output, allowed);
        return AWKStatusTooManyFrames;
    }
    claimOutput(kernel, output, frameCount);
    if (!kernel->prepared) {
        silence(output, frameCount);
        return AWK_UNINITIALIZED;
    }

    glideFilter(kernel, frameCount);
    float gainDecibels = load(kernel, AWKParameterGainDecibels);
    float levelTarget = powf(10.0f, gainDecibels / 20.0f);
    float muteTarget = load(kernel, AWKParameterMute) >= 0.5f ? 0.0f : 1.0f;
    float bypassTarget = load(kernel, AWKParameterBypass);
    float filterTarget = load(kernel, AWKParameterFilterEnabled);
    int loop = (int)load(kernel, AWKParameterLoop);

    uint32_t outputChannels = channelCount(output);
    uint32_t active = outputChannels < kernel->channels ? outputChannels : kernel->channels;
    uint32_t inputChannels = input == NULL ? 0 : channelCount(input);
    AWKChannel outs[AWK_MAX_CHANNELS];
    AWKChannel ins[AWK_MAX_CHANNELS];
    for (uint32_t channel = 0; channel < active; channel++) {
        outs[channel] = channelAt(output, channel);
        uint32_t source = inputChannels == 0 ? 0 : (channel < inputChannels ? channel : inputChannels - 1);
        ins[channel] = channelAt(input, source);
    }

    float peak = 0.0f;
    uint64_t clipped = 0, nonFinite = 0;
    for (uint32_t frame = 0; frame < frameCount; frame++) {
        kernel->level += (levelTarget - kernel->level) * kernel->levelCoefficient;
        float muteCoefficient = muteTarget < kernel->mute ? kernel->muteDownCoefficient : kernel->muteUpCoefficient;
        kernel->mute += (muteTarget - kernel->mute) * muteCoefficient;
        if (muteTarget == 0.0f && kernel->mute < 1.0e-6f) kernel->mute = 0.0f;
        kernel->bypassMix += (bypassTarget - kernel->bypassMix) * kernel->mixCoefficient;
        kernel->filterMix += (filterTarget - kernel->filterMix) * kernel->mixCoefficient;

        // Read every input sample of this frame before writing, so processing in place is safe
        // even when one input channel feeds two outputs.
        float dry[AWK_MAX_CHANNELS];
        float generated = input == NULL ? loopSample(kernel, loop) : 0.0f;
        for (uint32_t channel = 0; channel < active; channel++) {
            AWKChannel in = ins[channel];
            dry[channel] = input == NULL ? generated : (in.samples == NULL ? 0.0f : in.samples[frame * in.stride]);
        }

        for (uint32_t channel = 0; channel < active; channel++) {
            float x = dry[channel];
            float *z = kernel->state[channel];
            float filtered = kernel->b0 * x + z[0];
            z[0] = kernel->b1 * x - kernel->a1 * filtered + z[1];
            z[1] = kernel->b2 * x - kernel->a2 * filtered;
            float wet = (x + kernel->filterMix * (filtered - x)) * kernel->level;
            float y = (wet + kernel->bypassMix * (x - wet)) * kernel->mute;
            if (!isfinite(y)) {
                y = 0.0f;
                z[0] = 0.0f;
                z[1] = 0.0f;
                nonFinite += 1;
            } else if (y > 1.0f || y < -1.0f) {
                y = y > 0.0f ? 1.0f : -1.0f;
                clipped += 1;
            }
            float magnitude = fabsf(y);
            if (magnitude > peak) peak = magnitude;
            AWKChannel out = outs[channel];
            if (out.samples != NULL) out.samples[frame * out.stride] = y;
        }
    }

    // Channels the kernel was not prepared for are silent, never stale memory.
    for (uint32_t channel = active; channel < outputChannels; channel++) {
        AWKChannel out = channelAt(output, channel);
        if (out.samples == NULL) continue;
        for (uint32_t frame = 0; frame < frameCount; frame++) out.samples[frame * out.stride] = 0.0f;
    }

    atomic_fetch_add_explicit(&kernel->frames, frameCount, memory_order_relaxed);
    if (clipped) atomic_fetch_add_explicit(&kernel->clippedSamples, clipped, memory_order_relaxed);
    if (nonFinite) atomic_fetch_add_explicit(&kernel->nonFiniteSamples, nonFinite, memory_order_relaxed);
    atomic_store_explicit(&kernel->lastPeakBits, bitsOf(peak), memory_order_relaxed);
    if (peak > floatOf(atomic_load_explicit(&kernel->maximumPeakBits, memory_order_relaxed))) {
        atomic_store_explicit(&kernel->maximumPeakBits, bitsOf(peak), memory_order_relaxed);
    }
    atomic_store_explicit(&kernel->levelBits, bitsOf(kernel->level * kernel->mute), memory_order_relaxed);
    return AWKStatusOK;
}

OSStatus AWKKernelRenderLoop(AWKKernel *kernel, uint32_t frameCount, AudioBufferList *output) AWK_REALTIME {
    return render(kernel, frameCount, NULL, output);
}

// An effect with no input still processes silence, so its ramps and counters keep moving.
static const AudioBufferList noInput = {0};

OSStatus AWKKernelProcess(AWKKernel *kernel, uint32_t frameCount, const AudioBufferList *input, AudioBufferList *output) AWK_REALTIME {
    return render(kernel, frameCount, input == NULL ? &noInput : input, output);
}

// MARK: Parameters and counters

void AWKKernelSetParameter(AWKKernel *kernel, AWKParameter parameter, float value) AWK_REALTIME {
    if ((int)parameter < 0 || parameter >= AWKParameterCount) return;
    float kept = sanitized(parameter, value);
    if (isnan(kept)) return;
    atomic_store_explicit(&kernel->parameters[parameter], bitsOf(kept), memory_order_relaxed);
}

float AWKKernelParameter(const AWKKernel *kernel, AWKParameter parameter) AWK_REALTIME {
    if ((int)parameter < 0 || parameter >= AWKParameterCount) return NAN;
    return load(kernel, parameter);
}

void AWKKernelReadStats(const AWKKernel *kernel, AWKStats *stats) AWK_REALTIME {
    stats->callbacks = atomic_load_explicit(&kernel->callbacks, memory_order_relaxed);
    stats->frames = atomic_load_explicit(&kernel->frames, memory_order_relaxed);
    stats->oversizedCalls = atomic_load_explicit(&kernel->oversizedCalls, memory_order_relaxed);
    stats->clippedSamples = atomic_load_explicit(&kernel->clippedSamples, memory_order_relaxed);
    stats->nonFiniteSamples = atomic_load_explicit(&kernel->nonFiniteSamples, memory_order_relaxed);
    stats->lastPeak = floatOf(atomic_load_explicit(&kernel->lastPeakBits, memory_order_relaxed));
    stats->maximumPeak = floatOf(atomic_load_explicit(&kernel->maximumPeakBits, memory_order_relaxed));
    uint64_t rateBits = atomic_load_explicit(&kernel->sampleRateBits, memory_order_relaxed);
    double rate;
    memcpy(&rate, &rateBits, sizeof rate);
    stats->sampleRate = rate;
    stats->channels = atomic_load_explicit(&kernel->preparedChannels, memory_order_relaxed);
    stats->generation = atomic_load_explicit(&kernel->generation, memory_order_relaxed);
    stats->currentLevel = floatOf(atomic_load_explicit(&kernel->levelBits, memory_order_relaxed));
}

// MARK: Lifecycle, never on the render thread

AWKKernel *AWKKernelCreate(void) {
    AWKKernel *kernel = calloc(1, sizeof(AWKKernel));
    if (kernel == NULL) return NULL;
    for (int index = 0; index < AWK_MAX_CHANNELS; index++) {
        kernel->scratch[index] = calloc((size_t)AWK_MAX_FRAMES * AWK_MAX_CHANNELS, sizeof(float));
        if (kernel->scratch[index] == NULL) {
            AWKKernelDestroy(kernel);
            return NULL;
        }
    }
    static const float defaults[AWKParameterCount] = {-6.0f, 2400.0f, 0.9f, 1.0f, 0.0f, 0.0f, 0.0f};
    for (int index = 0; index < AWKParameterCount; index++) {
        atomic_init(&kernel->parameters[index], bitsOf(defaults[index]));
    }
    kernel->noise = AWK_NOISE_SEED;
    kernel->resonance = 0.9f;
    kernel->cutoff = 2400.0f;
    return kernel;
}

void AWKKernelDestroy(AWKKernel *kernel) {
    if (kernel == NULL) return;
    for (int index = 0; index < AWK_MAX_CHANNELS; index++) free(kernel->scratch[index]);
    free(kernel);
}

void AWKKernelRewind(AWKKernel *kernel) {
    kernel->loopFrame = 0;
    kernel->noise = AWK_NOISE_SEED;
}

bool AWKKernelPrepare(AWKKernel *kernel, double sampleRate, uint32_t channels) {
    if (!(sampleRate >= 8000.0 && sampleRate <= 384000.0)) return false;
    if (channels < 1 || channels > AWK_MAX_CHANNELS) return false;
    kernel->sampleRate = sampleRate;
    kernel->channels = channels;
    kernel->levelCoefficient = smoothingCoefficient(0.02, sampleRate);
    kernel->muteDownCoefficient = smoothingCoefficient(0.003, sampleRate);
    kernel->muteUpCoefficient = smoothingCoefficient(0.03, sampleRate);
    kernel->mixCoefficient = smoothingCoefficient(0.01, sampleRate);
    // Every start and every recovery fades in from silence: a route or rate change never jumps.
    kernel->level = 0.0f;
    kernel->mute = load(kernel, AWKParameterMute) >= 0.5f ? 0.0f : 1.0f;
    kernel->bypassMix = load(kernel, AWKParameterBypass);
    kernel->filterMix = load(kernel, AWKParameterFilterEnabled);
    kernel->cutoff = load(kernel, AWKParameterCutoffHertz);
    kernel->resonance = load(kernel, AWKParameterResonance);
    updateFilter(kernel);
    memset(kernel->state, 0, sizeof kernel->state);
    kernel->loopLength = (uint64_t)llround(AWK_LOOP_SECONDS * sampleRate);
    AWKKernelRewind(kernel);

    atomic_store(&kernel->callbacks, 0);
    atomic_store(&kernel->frames, 0);
    atomic_store(&kernel->oversizedCalls, 0);
    atomic_store(&kernel->clippedSamples, 0);
    atomic_store(&kernel->nonFiniteSamples, 0);
    atomic_store(&kernel->lastPeakBits, 0);
    atomic_store(&kernel->maximumPeakBits, 0);
    atomic_store(&kernel->levelBits, 0);
    uint64_t rateBits;
    memcpy(&rateBits, &sampleRate, sizeof rateBits);
    atomic_store(&kernel->sampleRateBits, rateBits);
    atomic_store(&kernel->preparedChannels, channels);
    atomic_fetch_add(&kernel->generation, 1);
    kernel->prepared = true;
    return true;
}
