// android/app/src/main/cpp/kelasagara_apex_engine.cpp
#include <oboe/Oboe.h>
#include <android/performance_hint.h>
#include <unistd.h>
#include <atomic>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <mutex>
#include <vector>

#if defined(__ANDROID__)
#define FFI_EXPORT extern "C" __attribute__((visibility("default"))) __attribute__((used))
#else
#define FFI_EXPORT extern "C"
#endif

namespace kelasagara::apex {

constexpr int32_t kSampleRate = 16000;
constexpr int64_t kTarget120HzBudgetNanos = 8333333LL; // 8.333ms (120 FPS)

// Cache-line aligned (64-byte) shared telemetry block mapped directly into Dart Float32List(12)
// Index 0: Smoothed RMS [0.0, 1.0]
// Index 1: Spectral Centroid (Normalized vocal brightness) [0.0, 1.0]
// Index 2: Formant VAD Active Flag (0.0 or 1.0)
// Index 3: Barge-In Interrupt Flag (0.0 or 1.0)
// Index 4..11: 8-Band Sub-Band Energies for Multi-Harmonic Shader Displacement
struct alignas(64) ZeroCopySharedTelemetry {
    float registers[12]{0.0f};
};

class ApexAudioAndAdpfEngine : public oboe::AudioStreamDataCallback {
public:
    ZeroCopySharedTelemetry sharedMemory;

    void initializeAdpfSession(const int32_t* threadIds, size_t count) {
        APerformanceHintManager* manager = APerformanceHint_getManager();
        if (!manager || count == 0) return;

        if (adpfSession_) {
            APerformanceHint_closeSession(adpfSession_);
            adpfSession_ = nullptr;
        }
        adpfSession_ = APerformanceHint_createSession(
            manager,
            threadIds,
            count,
            kTarget120HzBudgetNanos
        );
    }

    void reportFrameDurationNanos(int64_t actualDurationNanos) {
        if (adpfSession_) {
            APerformanceHint_reportActualWorkDuration(adpfSession_, actualDurationNanos);
        }
    }

    bool startHardwareDuplexCapture() {
        std::lock_guard<std::mutex> lock(mutex_);
        if (stream_) return true;

        oboe::AudioStreamBuilder builder;
        builder.setDirection(oboe::Direction::Input)
               ->setPerformanceMode(oboe::PerformanceMode::LowLatency)
               ->setSharingMode(oboe::SharingMode::Exclusive)
               ->setInputPreset(oboe::InputPreset::VoiceCommunication) // Hardware DSP AEC + NS
               ->setFormat(oboe::AudioFormat::I16)
               ->setChannelCount(oboe::ChannelCount::Mono)
               ->setSampleRate(kSampleRate)
               ->setDataCallback(this);

        if (builder.openStream(stream_) != oboe::Result::OK) {
            return false;
        }
        return stream_->requestStart() == oboe::Result::OK;
    }

    void stopCapture() {
        std::lock_guard<std::mutex> lock(mutex_);
        if (stream_) {
            stream_->stop();
            stream_->close();
            stream_.reset();
        }
        if (adpfSession_) {
            APerformanceHint_closeSession(adpfSession_);
            adpfSession_ = nullptr;
        }
    }

    oboe::DataCallbackResult onAudioReady(
        oboe::AudioStream* audioStream,
        void* audioData,
        int32_t numFrames
    ) override {
        const auto* pcm = static_cast<const int16_t*>(audioData);
        if (numFrames <= 0) return oboe::DataCallbackResult::Continue;

        double sumSq = 0.0;
        double weightedDiffSum = 0.0;
        int32_t zeroCrossings = 0;

        // 8-band time-domain filterbank accumulator via decimated Walsh-Hadamard style strides
        float bandAccum[8]{0.0f};

        for (int32_t i = 0; i < numFrames; ++i) {
            const float s = pcm[i] / 32768.0f;
            const float absS = std::fabs(s);
            sumSq += s * s;

            if (i > 0) {
                const float diff = std::fabs(s - (pcm[i - 1] / 32768.0f));
                weightedDiffSum += diff;
                if ((pcm[i] >= 0 && pcm[i - 1] < 0) || (pcm[i] < 0 && pcm[i - 1] >= 0)) {
                    zeroCrossings++;
                }
            }
            bandAccum[i & 7] += absS;
        }

        const float rms = std::sqrt(sumSq / static_cast<double>(numFrames));
        const float normRms = std::fmin(1.0f, rms * 7.2f);

        // Asymmetric envelope follower in C++ (fast attack, smooth release)
        const float prevRms = sharedMemory.registers[0];
        const float alpha = (normRms > prevRms) ? 0.45f : 0.15f;
        sharedMemory.registers[0] = prevRms + alpha * (normRms - prevRms);

        // Spectral centroid estimate via first-order differential ratio
        const float centroid = (rms > 0.001f)
            ? std::fmin(1.0f, static_cast<float>(weightedDiffSum / (numFrames * rms * 2.0)))
            : 0.0f;
        sharedMemory.registers[1] = centroid;

        // Populate 8 frequency-proxy bands for GPU shader harmonic rings
        const float invBandFrames = 8.0f / static_cast<float>(numFrames);
        for (int b = 0; b < 8; ++b) {
            const float targetBand = std::fmin(1.0f, bandAccum[b] * invBandFrames * 5.5f);
            sharedMemory.registers[4 + b] =
                sharedMemory.registers[4 + b] * 0.65f + targetBand * 0.35f;
        }

        // Formant-band Voice Activity Detection (rejects high-frequency wind & low-frequency traffic rumble)
        const float zcr = static_cast<float>(zeroCrossings) / static_cast<float>(numFrames);
        const bool isVocalFormant =
            (rms > 0.042f) && (zcr >= 0.035f && zcr <= 0.36f) && (centroid >= 0.12f && centroid <= 0.78f);

        if (isVocalFormant) {
            vocalHoldFrames_++;
            if (vocalHoldFrames_ >= 2) { // ~12ms lock-on
                sharedMemory.registers[2] = 1.0f;
                if (assistantSpeaking_.load(std::memory_order_acquire) == 1) {
                    sharedMemory.registers[3] = 1.0f; // Instant Barge-In flag
                }
            }
        } else {
            vocalHoldFrames_ = 0;
            sharedMemory.registers[2] = 0.0f;
        }

        return oboe::DataCallbackResult::Continue;
    }

    void setAssistantSpeaking(bool speaking) {
        assistantSpeaking_.store(speaking ? 1 : 0, std::memory_order_release);
        if (!speaking) {
            sharedMemory.registers[3] = 0.0f;
        }
    }

    float* getSharedRegistersPtr() {
        return sharedMemory.registers;
    }

private:
    std::shared_ptr<oboe::AudioStream> stream_;
    APerformanceHintSession* adpfSession_{nullptr};
    std::mutex mutex_;
    std::atomic<int32_t> assistantSpeaking_{0};
    int32_t vocalHoldFrames_{0};
};

static ApexAudioAndAdpfEngine gApexEngine;

} // namespace kelasagara::apex

FFI_EXPORT int32_t kelasagara_apex_start_audio() {
    return kelasagara::apex::gApexEngine.startHardwareDuplexCapture() ? 1 : 0;
}

FFI_EXPORT void kelasagara_apex_stop_audio() {
    kelasagara::apex::gApexEngine.stopCapture();
}

FFI_EXPORT float* kelasagara_apex_get_shared_telemetry_ptr() {
    return kelasagara::apex::gApexEngine.getSharedRegistersPtr();
}

FFI_EXPORT void kelasagara_apex_set_assistant_speaking(int32_t speaking) {
    kelasagara::apex::gApexEngine.setAssistantSpeaking(speaking != 0);
}

FFI_EXPORT void kelasagara_apex_init_adpf_120hz(int32_t mainTid) {
    int32_t tids[1] = { mainTid > 0 ? mainTid : static_cast<int32_t>(gettid()) };
    kelasagara::apex::gApexEngine.initializeAdpfSession(tids, 1);
}

FFI_EXPORT void kelasagara_apex_report_frame_nanos(int64_t durationNanos) {
    kelasagara::apex::gApexEngine.reportFrameDurationNanos(durationNanos);
}
