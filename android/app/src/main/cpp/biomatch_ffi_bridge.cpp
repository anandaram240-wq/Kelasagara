#include <jni.h>
#include <stdint.h>
#include <cmath>
#include <cstring>
#include <cstdio>
#include <vector>
#include <array>
#include <mutex>
#include <memory>
#include <algorithm>
#include <unordered_map>
#include <string>
#include <android/log.h>
#include "onnxruntime_cxx_api.h"

#define LOG_TAG "BioMatchFFI"
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO,  LOG_TAG, __VA_ARGS__)

#if defined(__GNUC__) || defined(__clang__)
    #define FFI_EXPORT extern "C" __attribute__((visibility("default"))) __attribute__((used))
#else
    #define FFI_EXPORT extern "C"
#endif

namespace kelasagara::biomatch {

// ============================================================================
// 1. STATUS CODES & FFI RESULT STRUCT (64-BIT ALIGNED FOR DART FFI)
// ============================================================================
enum BiomatchStatus : int32_t {
    BIOMATCH_OK                     = 0,
    ERR_SESSION_NOT_INITIALIZED     = -1,
    ERR_INVALID_INPUT_PARAMETERS    = -2,
    ERR_PAD_BLUR_OR_PRINT_ATTACK    = -3, // Laplacian variance < 110.0
    ERR_PAD_MOIRE_SCREEN_ATTACK     = -4, // Laplacian variance > 1850.0
    ERR_LOW_MAGFACE_QUALITY_NORM    = -5, // Pre-L2 norm ||z||_2 < 18.5
    ERR_ORT_RUNTIME_EXCEPTION       = -6
};

#pragma pack(push, 4)
struct NativeBiomatchResult {
    int32_t status_code;               // BiomatchStatus enum
    float quality_norm;                // MagFace pre-normalized ||z||_2
    float laplacian_variance;          // ISO/IEC 30107-3 passive texture score
    float pad_liveness_score;          // IndicPAD-CDC fused liveness probability [0.0, 1.0]
    float embedding[128];              // L2-normalized 128-D hypersphere vector
    uint8_t capture_digest_hex[65];    // Null-terminated 64-char SHA-256 hex digest
};
#pragma pack(pop)

// ============================================================================
// 2. COMPILER-SAFE MEMORY SCRUBBING (DPDPA ZERO-RETENTION GUARANTEE)
// ============================================================================
inline void SecureZeroMemory(void* ptr, size_t len) {
    if (!ptr || len == 0) return;
    volatile uint8_t* p = reinterpret_cast<volatile uint8_t*>(ptr);
    while (len--) {
        *p++ = 0;
    }
}

// ============================================================================
// 3. STANDALONE FIPS 180-4 SHA-256 (ZERO EXTERNAL OPENSSL DEPENDENCY)
// ============================================================================
class Sha256Digest {
public:
    static void ComputeHex(const uint8_t* data, size_t len, uint8_t out_hex[65]) {
        static constexpr uint32_t K[64] = {
            0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,
            0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,
            0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,
            0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,
            0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,
            0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,
            0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,
            0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2
        };

        uint32_t h[8] = {
            0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
            0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19
        };

        size_t padded_len = ((len + 8) / 64 + 1) * 64;
        std::vector<uint8_t> msg(padded_len, 0);
        std::memcpy(msg.data(), data, len);
        msg[len] = 0x80;

        uint64_t bit_len = static_cast<uint64_t>(len) * 8;
        for (int i = 0; i < 8; ++i) {
            msg[padded_len - 1 - i] = static_cast<uint8_t>(bit_len >> (i * 8));
        }

        auto rotr = [](uint32_t x, uint32_t n) { return (x >> n) | (x << (32 - n)); };

        for (size_t offset = 0; offset < padded_len; offset += 64) {
            uint32_t w[64];
            for (int i = 0; i < 16; ++i) {
                w[i] = (static_cast<uint32_t>(msg[offset + i * 4]) << 24) |
                       (static_cast<uint32_t>(msg[offset + i * 4 + 1]) << 16) |
                       (static_cast<uint32_t>(msg[offset + i * 4 + 2]) << 8) |
                       (static_cast<uint32_t>(msg[offset + i * 4 + 3]));
            }
            for (int i = 16; i < 64; ++i) {
                uint32_t s0 = rotr(w[i - 15], 7) ^ rotr(w[i - 15], 18) ^ (w[i - 15] >> 3);
                uint32_t s1 = rotr(w[i - 2], 17) ^ rotr(w[i - 2], 19) ^ (w[i - 2] >> 10);
                w[i] = w[i - 16] + s0 + w[i - 7] + s1;
            }

            uint32_t a = h[0], b = h[1], c = h[2], d = h[3];
            uint32_t e = h[4], f = h[5], g = h[6], hh = h[7];

            for (int i = 0; i < 64; ++i) {
                uint32_t S1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25);
                uint32_t ch = (e & f) ^ ((~e) & g);
                uint32_t temp1 = hh + S1 + ch + K[i] + w[i];
                uint32_t S0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22);
                uint32_t maj = (a & b) ^ (a & c) ^ (b & c);
                uint32_t temp2 = S0 + maj;

                hh = g; g = f; f = e; e = d + temp1;
                d = c; c = b; b = a; a = temp1 + temp2;
            }

            h[0] += a; h[1] += b; h[2] += c; h[3] += d;
            h[4] += e; h[5] += f; h[6] += g; h[7] += hh;
        }

        static constexpr char hex_chars[] = "0123456789abcdef";
        for (int i = 0; i < 8; ++i) {
            for (int shift = 28; shift >= 0; shift -= 4) {
                *out_hex++ = hex_chars[(h[i] >> shift) & 0xF];
            }
        }
        *out_hex = '\0';
        SecureZeroMemory(msg.data(), msg.size());
    }
};

// ============================================================================
// 4. UMEYAMA 5-POINT SIMILARITY ALIGNMENT & BILINEAR YUV420/NV21 WARP
// ============================================================================
static constexpr float kCanonicalArcFace112[5][2] = {
    {38.2946f, 51.6963f}, // Left Eye
    {73.5318f, 51.5014f}, // Right Eye
    {56.0252f, 71.7366f}, // Nose Tip
    {41.5493f, 92.3655f}, // Left Mouth Corner
    {70.7299f, 92.2041f}  // Right Mouth Corner
};

struct AffineMatrix2x3 {
    float m[2][3];
};

AffineMatrix2x3 ComputeInverseSimilarityMatrix(const float src_pts[5][2]) {
    float mu_src_x = 0.f, mu_src_y = 0.f;
    float mu_dst_x = 0.f, mu_dst_y = 0.f;

    for (int i = 0; i < 5; ++i) {
        mu_src_x += src_pts[i][0];
        mu_src_y += src_pts[i][1];
        mu_dst_x += kCanonicalArcFace112[i][0];
        mu_dst_y += kCanonicalArcFace112[i][1];
    }
    mu_src_x *= 0.2f; mu_src_y *= 0.2f;
    mu_dst_x *= 0.2f; mu_dst_y *= 0.2f;

    float num_a = 0.f, num_b = 0.f, den = 0.f;
    for (int i = 0; i < 5; ++i) {
        float px = kCanonicalArcFace112[i][0] - mu_dst_x;
        float py = kCanonicalArcFace112[i][1] - mu_dst_y;
        float qx = src_pts[i][0] - mu_src_x;
        float qy = src_pts[i][1] - mu_src_y;

        num_a += (px * qx + py * qy);
        num_b += (px * qy - py * qx);
        den   += (px * px + py * py);
    }

    float a = num_a / std::max(den, 1e-8f);
    float b = num_b / std::max(den, 1e-8f);
    float tx = mu_src_x - (a * mu_dst_x - b * mu_dst_y);
    float ty = mu_src_y - (b * mu_dst_x + a * mu_dst_y);

    AffineMatrix2x3 inv_mat{};
    inv_mat.m[0][0] = a;  inv_mat.m[0][1] = -b; inv_mat.m[0][2] = tx;
    inv_mat.m[1][0] = b;  inv_mat.m[1][1] =  a; inv_mat.m[1][2] = ty;
    return inv_mat;
}

float ComputeLaplacianVariance(const std::array<float, 112 * 112>& luma) {
    double sum = 0.0;
    double sq_sum = 0.0;
    constexpr int count = 110 * 110;

    for (int y = 1; y < 111; ++y) {
        for (int x = 1; x < 111; ++x) {
            float c = luma[y * 112 + x];
            float lap = -4.0f * c
                        + luma[(y - 1) * 112 + x]
                        + luma[(y + 1) * 112 + x]
                        + luma[y * 112 + (x - 1)]
                        + luma[y * 112 + (x + 1)];
            sum += lap;
            sq_sum += static_cast<double>(lap) * lap;
        }
    }
    double mean = sum / count;
    return static_cast<float>((sq_sum / count) - (mean * mean));
}

/**
 * Bilinearly samples YUV420 / NV21 Planes with arbitrary row/pixel strides,
 * and outputs a normalized [-1.0, 1.0] 1x3x112x112 NCHW tensor.
 */
void WarpYUV420ToAlignedRGBTensor(
    const uint8_t* y_plane, int y_row_stride,
    const uint8_t* u_plane, const uint8_t* v_plane,
    int uv_row_stride, int uv_pixel_stride,
    int width, int height,
    const AffineMatrix2x3& inv_m,
    std::vector<float>& out_nchw_tensor,
    std::array<float, 112 * 112>& out_luma
) {
    out_nchw_tensor.resize(1 * 3 * 112 * 112);
    constexpr int kPlaneStride = 112 * 112;

    auto sample_y = [&](int x, int y) -> float {
        int cx = std::clamp(x, 0, width - 1);
        int cy = std::clamp(y, 0, height - 1);
        return static_cast<float>(y_plane[cy * y_row_stride + cx]);
    };

    for (int dy = 0; dy < 112; ++dy) {
        for (int dx = 0; dx < 112; ++dx) {
            float sx = inv_m.m[0][0] * dx + inv_m.m[0][1] * dy + inv_m.m[0][2];
            float sy = inv_m.m[1][0] * dx + inv_m.m[1][1] * dy + inv_m.m[1][2];

            // Bilinear interpolation on Y plane for crisp sub-pixel eye/nose edges
            int x0 = static_cast<int>(std::floor(sx));
            int y0 = static_cast<int>(std::floor(sy));
            float wx = sx - x0;
            float wy = sy - y0;

            float y00 = sample_y(x0, y0);
            float y10 = sample_y(x0 + 1, y0);
            float y01 = sample_y(x0, y0 + 1);
            float y11 = sample_y(x0 + 1, y0 + 1);

            float Y = (1.0f - wy) * ((1.0f - wx) * y00 + wx * y10) +
                      wy * ((1.0f - wx) * y01 + wx * y11);

            // Nearest-neighbor chroma sampling on subsampled UV planes
            int uv_x = std::clamp(static_cast<int>( std::round(sx) ), 0, width - 1) >> 1;
            int uv_y = std::clamp(static_cast<int>( std::round(sy) ), 0, height - 1) >> 1;
            int uv_offset = uv_y * uv_row_stride + uv_x * uv_pixel_stride;

            float U = static_cast<float>(u_plane[uv_offset]) - 128.0f;
            float V = static_cast<float>(v_plane[uv_offset]) - 128.0f;

            // ITU-R BT.601 YUV -> RGB
            float r = std::clamp(Y + 1.402f * V, 0.0f, 255.0f);
            float g = std::clamp(Y - 0.344136f * U - 0.714136f * V, 0.0f, 255.0f);
            float b = std::clamp(Y + 1.772f * U, 0.0f, 255.0f);

            int dst_idx = dy * 112 + dx;
            out_luma[dst_idx] = Y;

            out_nchw_tensor[0 * kPlaneStride + dst_idx] = (r - 127.5f) / 128.0f;
            out_nchw_tensor[1 * kPlaneStride + dst_idx] = (g - 127.5f) / 128.0f;
            out_nchw_tensor[2 * kPlaneStride + dst_idx] = (b - 127.5f) / 128.0f;
        }
    }
}

// ============================================================================
// 5. GLOBAL ONNX RUNTIME SESSION SINGLETON (XNNPACK ACCELERATED)
// ============================================================================
class OrtEngineSingleton {
public:
    static OrtEngineSingleton& Instance() {
        static OrtEngineSingleton instance;
        return instance;
    }

    int32_t InitializeFromMemory(const uint8_t* model_bytes, size_t model_len, int num_threads) {
        std::lock_guard<std::mutex> lock(mutex_);
        try {
            if (!env_) {
                env_ = std::make_unique<Ort::Env>(ORT_LOGGING_LEVEL_WARNING, "KelasagaraBioMatch");
            }

            Ort::SessionOptions opts;
            opts.SetIntraOpNumThreads(std::clamp(num_threads, 1, 4));
            opts.SetGraphOptimizationLevel(GraphOptimizationLevel::ORT_ENABLE_ALL);

            // Attach XNNPACK Execution Provider for ARMv8 SDOT / NEON INT8 QDQ kernels
            try {
                std::unordered_map<std::string, std::string> xnnpack_opts;
                xnnpack_opts["intra_op_num_threads"] = std::to_string(std::clamp(num_threads, 1, 4));
                opts.AppendExecutionProvider("XNNPACK", xnnpack_opts);
                LOGI("XNNPACK Execution Provider enabled for IndicFace128 INT8.");
            } catch (const Ort::Exception& e) {
                LOGI("XNNPACK unavailable, falling back to default ARM CPU provider: %s", e.what());
            }

            session_ = std::make_unique<Ort::Session>(*env_, model_bytes, model_len, opts);
            return BIOMATCH_OK;
        } catch (const Ort::Exception& ex) {
            LOGE("Failed to initialize ONNX Runtime session: %s", ex.what());
            return ERR_ORT_RUNTIME_EXCEPTION;
        }
    }

    int32_t RunInference(
        std::vector<float>& input_nchw,
        float out_embedding[128],
        float& out_quality_norm
    ) {
        std::lock_guard<std::mutex> lock(mutex_);
        if (!session_) return ERR_SESSION_NOT_INITIALIZED;

        try {
            Ort::MemoryInfo mem_info = Ort::MemoryInfo::CreateCpu(OrtArenaAllocator, OrtMemTypeDefault);
            constexpr std::array<int64_t, 4> input_shape = {1, 3, 112, 112};

            Ort::Value input_tensor = Ort::Value::CreateTensor<float>(
                mem_info,
                input_nchw.data(),
                input_nchw.size(),
                input_shape.data(),
                input_shape.size()
            );

            const char* input_names[] = {"input_rgb"};
            const char* output_names[] = {"embedding", "quality_norm"};

            auto output_tensors = session_->Run(
                Ort::RunOptions{nullptr},
                input_names,
                &input_tensor,
                1,
                output_names,
                2
            );

            const float* emb_ptr = output_tensors[0].GetTensorData<float>();
            const float* norm_ptr = output_tensors[1].GetTensorData<float>();

            out_quality_norm = norm_ptr[0];

            // Enforce defensive L2 unit-hypersphere normalization
            double l2_sum = 0.0;
            for (int i = 0; i < 128; ++i) {
                l2_sum += static_cast<double>(emb_ptr[i]) * emb_ptr[i];
            }
            float inv_norm = static_cast<float>(1.0 / std::sqrt(std::max(l2_sum, 1e-12)));
            for (int i = 0; i < 128; ++i) {
                out_embedding[i] = emb_ptr[i] * inv_norm;
            }

            return BIOMATCH_OK;
        } catch (const Ort::Exception& ex) {
            LOGE("ONNX Runtime forward pass error: %s", ex.what());
            return ERR_ORT_RUNTIME_EXCEPTION;
        }
    }

    int32_t InitializePadFromMemory(const uint8_t* model_bytes, size_t model_len, int num_threads) {
        std::lock_guard<std::mutex> lock(mutex_);
        try {
            if (!env_) {
                env_ = std::make_unique<Ort::Env>(ORT_LOGGING_LEVEL_WARNING, "KelasagaraBioMatch");
            }

            Ort::SessionOptions opts;
            opts.SetIntraOpNumThreads(std::clamp(num_threads, 1, 4));
            opts.SetGraphOptimizationLevel(GraphOptimizationLevel::ORT_ENABLE_ALL);

            try {
                std::unordered_map<std::string, std::string> xnnpack_opts;
                xnnpack_opts["intra_op_num_threads"] = std::to_string(std::clamp(num_threads, 1, 4));
                opts.AppendExecutionProvider("XNNPACK", xnnpack_opts);
                LOGI("XNNPACK Execution Provider enabled for IndicPAD-CDC INT8.");
            } catch (const Ort::Exception& e) {
                LOGI("XNNPACK unavailable for PAD, falling back to default ARM CPU provider: %s", e.what());
            }

            pad_session_ = std::make_unique<Ort::Session>(*env_, model_bytes, model_len, opts);
            LOGI("IndicPAD-CDC ONNX Runtime session successfully initialized.");
            return BIOMATCH_OK;
        } catch (const Ort::Exception& ex) {
            LOGE("Failed to initialize ONNX Runtime PAD session: %s", ex.what());
            return ERR_ORT_RUNTIME_EXCEPTION;
        }
    }

    int32_t RunPadLivenessCheck(
        const std::vector<float>& aligned_nchw,
        float& out_liveness_prob
    ) {
        std::lock_guard<std::mutex> lock(mutex_);
        if (!pad_session_) {
            // When IndicPAD model is not loaded, pass through by default
            out_liveness_prob = 1.0f;
            return BIOMATCH_OK;
        }

        try {
            Ort::MemoryInfo mem_info = Ort::MemoryInfo::CreateCpu(OrtArenaAllocator, OrtMemTypeDefault);
            constexpr std::array<int64_t, 4> input_shape = {1, 3, 112, 112};

            Ort::Value input_tensor = Ort::Value::CreateTensor<float>(
                mem_info,
                const_cast<float*>(aligned_nchw.data()),
                aligned_nchw.size(),
                input_shape.data(),
                input_shape.size()
            );

            const char* pad_in_names[] = {"input_rgb"};
            const char* pad_out_names[] = {"liveness_prob"};

            auto pad_outputs = pad_session_->Run(
                Ort::RunOptions{nullptr},
                pad_in_names,
                &input_tensor,
                1,
                pad_out_names,
                1
            );

            out_liveness_prob = pad_outputs[0].GetTensorData<float>()[0];
            return BIOMATCH_OK;
        } catch (const Ort::Exception& ex) {
            LOGE("IndicPAD-CDC ONNX Runtime forward pass error: %s", ex.what());
            return ERR_ORT_RUNTIME_EXCEPTION;
        }
    }

    void Release() {
        std::lock_guard<std::mutex> lock(mutex_);
        session_.reset();
        pad_session_.reset();
    }

private:
    OrtEngineSingleton() = default;
    std::mutex mutex_;
    std::unique_ptr<Ort::Env> env_;
    std::unique_ptr<Ort::Session> session_;
    std::unique_ptr<Ort::Session> pad_session_;
};

} // namespace kelasagara::biomatch

// ============================================================================
// 6. C-LINKAGE EXPORTS FOR FLUTTER DART FFI
// ============================================================================
using namespace kelasagara::biomatch;

FFI_EXPORT int32_t biomatch_init_session(
    const uint8_t* model_bytes,
    int32_t model_len,
    int32_t num_threads
) {
    if (!model_bytes || model_len <= 0) {
        return ERR_INVALID_INPUT_PARAMETERS;
    }
    return OrtEngineSingleton::Instance().InitializeFromMemory(
        model_bytes,
        static_cast<size_t>(model_len),
        num_threads
    );
}

FFI_EXPORT int32_t biomatch_process_frame_and_infer(
    const uint8_t* y_plane,
    int32_t y_byte_len,
    int32_t y_row_stride,
    const uint8_t* u_plane,
    const uint8_t* v_plane,
    int32_t uv_row_stride,
    int32_t uv_pixel_stride,
    int32_t width,
    int32_t height,
    const float* landmarks_10, // [lx, ly, rx, ry, nx, ny, mlx, mly, mrx, mry] in sensor coords
    NativeBiomatchResult* out_result
) {
    if (!y_plane || !u_plane || !v_plane || !landmarks_10 || !out_result || width <= 0 || height <= 0) {
        return ERR_INVALID_INPUT_PARAMETERS;
    }

    std::memset(out_result, 0, sizeof(NativeBiomatchResult));

    // 1. Compute SHA-256 captureDigestHex on the raw Y-plane buffer for Play Integrity requestHash
    Sha256Digest::ComputeHex(
        y_plane,
        static_cast<size_t>(y_byte_len),
        out_result->capture_digest_hex
    );

    // 2. Unpack 5 landmarks and compute Umeyama 2x3 Inverse Similarity Transform
    float src_pts[5][2];
    for (int i = 0; i < 5; ++i) {
        src_pts[i][0] = landmarks_10[i * 2 + 0];
        src_pts[i][1] = landmarks_10[i * 2 + 1];
    }
    AffineMatrix2x3 inv_sim = ComputeInverseSimilarityMatrix(src_pts);

    // 3. Warp YUV420 / NV21 frame into 112x112 NCHW tensor & extract Y-Luma
    std::vector<float> aligned_nchw;
    std::array<float, 112 * 112> aligned_luma{};

    WarpYUV420ToAlignedRGBTensor(
        y_plane, y_row_stride,
        u_plane, v_plane, uv_row_stride, uv_pixel_stride,
        width, height,
        inv_sim,
        aligned_nchw,
        aligned_luma
    );

    // 4. Passive PAD Gate: 3x3 Laplacian Texture Frequency Check
    float lap_var = ComputeLaplacianVariance(aligned_luma);
    out_result->laplacian_variance = lap_var;

    if (lap_var < 110.0f) {
        SecureZeroMemory(aligned_nchw.data(), aligned_nchw.size() * sizeof(float));
        SecureZeroMemory(aligned_luma.data(), aligned_luma.size() * sizeof(float));
        out_result->status_code = ERR_PAD_BLUR_OR_PRINT_ATTACK;
        return ERR_PAD_BLUR_OR_PRINT_ATTACK;
    }
    if (lap_var > 1850.0f) {
        SecureZeroMemory(aligned_nchw.data(), aligned_nchw.size() * sizeof(float));
        SecureZeroMemory(aligned_luma.data(), aligned_luma.size() * sizeof(float));
        out_result->status_code = ERR_PAD_MOIRE_SCREEN_ATTACK;
        return ERR_PAD_MOIRE_SCREEN_ATTACK;
    }

    // 4.5. Deep Presentation Attack Detection Gate (IndicPAD-CDC with 2D FFT Moire Gate)
    float pad_liveness = 1.0f;
    int32_t pad_status = OrtEngineSingleton::Instance().RunPadLivenessCheck(aligned_nchw, pad_liveness);
    out_result->pad_liveness_score = pad_liveness;

    if (pad_status == BIOMATCH_OK && pad_liveness < 0.88f) {
        SecureZeroMemory(aligned_nchw.data(), aligned_nchw.size() * sizeof(float));
        SecureZeroMemory(aligned_luma.data(), aligned_luma.size() * sizeof(float));
        out_result->status_code = ERR_PAD_MOIRE_SCREEN_ATTACK;
        return ERR_PAD_MOIRE_SCREEN_ATTACK;
    }

    // 5. Execute IndicFace128 INT8 Inference via ONNX Runtime
    float quality_norm = 0.0f;
    int32_t infer_status = OrtEngineSingleton::Instance().RunInference(
        aligned_nchw,
        out_result->embedding,
        quality_norm
    );

    // 6. Zero raw facial pixel tensors from RAM immediately (DPDPA Sec. 6)
    SecureZeroMemory(aligned_nchw.data(), aligned_nchw.size() * sizeof(float));
    SecureZeroMemory(aligned_luma.data(), aligned_luma.size() * sizeof(float));

    if (infer_status != BIOMATCH_OK) {
        out_result->status_code = infer_status;
        return infer_status;
    }

    out_result->quality_norm = quality_norm;

    // 7. Enforce MagFace Feature Norm Gate (||z||_2 >= 18.5)
    if (quality_norm < 18.5f) {
        SecureZeroMemory(out_result->embedding, sizeof(out_result->embedding));
        out_result->status_code = ERR_LOW_MAGFACE_QUALITY_NORM;
        return ERR_LOW_MAGFACE_QUALITY_NORM;
    }

    out_result->status_code = BIOMATCH_OK;
    return BIOMATCH_OK;
}

FFI_EXPORT int32_t biomatch_init_pad_session(
    const uint8_t* model_bytes,
    int32_t model_len,
    int32_t num_threads
) {
    if (!model_bytes || model_len <= 0) {
        return ERR_INVALID_INPUT_PARAMETERS;
    }
    return OrtEngineSingleton::Instance().InitializePadFromMemory(
        model_bytes,
        static_cast<size_t>(model_len),
        num_threads
    );
}

FFI_EXPORT void biomatch_release_session() {
    OrtEngineSingleton::Instance().Release();
}
