#include <jni.h>
#include <cmath>
#include <cstring>
#include <vector>
#include <array>
#include <algorithm>
#include <onnxruntime_cxx_api.h>

namespace kelasagara::biomatch {

// Canonical 112x112 ArcFace 5-point landmarks:
// [Left Eye, Right Eye, Nose Tip, Left Mouth, Right Mouth]
static constexpr float kCanonicalLandmarks[5][2] = {
    {38.2946f, 51.6963f},
    {73.5318f, 51.5014f},
    {56.0252f, 71.7366f},
    {41.5493f, 92.3655f},
    {70.7299f, 92.2041f}
};

struct AffineMatrix2x3 {
    float m[2][3];
};

// Secure memory zeroing that the compiler cannot optimize away
inline void SecureZeroMemory(void* ptr, size_t len) {
    volatile uint8_t* p = reinterpret_cast<volatile uint8_t*>(ptr);
    while (len--) {
        *p++ = 0;
    }
}

/**
 * Closed-form 2D Similarity Transform (Umeyama SVD for 2x2)
 * Computes the inverse warp matrix (Target 112x112 -> Source NV21 Frame)
 * for direct bilinear sampling.
 */
AffineMatrix2x3 ComputeInverseSimilarityMatrix(const float src_pts[5][2]) {
    float mu_src_x = 0.f, mu_src_y = 0.f;
    float mu_dst_x = 0.f, mu_dst_y = 0.f;

    for (int i = 0; i < 5; ++i) {
        mu_src_x += src_pts[i][0];
        mu_src_y += src_pts[i][1];
        mu_dst_x += kCanonicalLandmarks[i][0];
        mu_dst_y += kCanonicalLandmarks[i][1];
    }
    mu_src_x *= 0.2f; mu_src_y *= 0.2f;
    mu_dst_x *= 0.2f; mu_dst_y *= 0.2f;

    // In 2D similarity without reflection:
    // q_x' = a * p_x' - b * p_y'
    // q_y' = b * p_x' + a * p_y'
    float num_a = 0.f, num_b = 0.f, den = 0.f;
    for (int i = 0; i < 5; ++i) {
        float px = kCanonicalLandmarks[i][0] - mu_dst_x;
        float py = kCanonicalLandmarks[i][1] - mu_dst_y;
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

/**
 * Passive PAD: Computes 3x3 Laplacian Variance on the 112x112 Y-luma plane
 * Rejects blurry 2D paper prints (< 110.0) and high-frequency Moire screens (> 1850.0)
 */
float ComputeLaplacianVariance(const std::array<float, 112 * 112>& luma) {
    double sum = 0.0;
    double sq_sum = 0.0;
    int count = 0;

    for (int y = 1; y < 111; ++y) {
        for (int x = 1; x < 111; ++x) {
            float center = luma[y * 112 + x];
            float lap = -4.0f * center
                        + luma[(y - 1) * 112 + x]
                        + luma[(y + 1) * 112 + x]
                        + luma[y * 112 + (x - 1)]
                        + luma[y * 112 + (x + 1)];
            sum += lap;
            sq_sum += (lap * lap);
            count++;
        }
    }
    double mean = sum / count;
    return static_cast<float>((sq_sum / count) - (mean * mean));
}

/**
 * Fused NV21 -> Aligned 112x112 RGB NCHW Tensor Extraction
 */
void WarpNV21ToAlignedRGBTensor(
    const uint8_t* nv21_buf,
    int width,
    int height,
    const AffineMatrix2x3& inv_m,
    std::vector<float>& out_nchw_tensor,
    std::array<float, 112 * 112>& out_luma
) {
    out_nchw_tensor.resize(1 * 3 * 112 * 112);
    const int frame_size = width * height;
    const int plane_stride = 112 * 112;

    for (int dy = 0; dy < 112; ++dy) {
        for (int dx = 0; dx < 112; ++dx) {
            float sx = inv_m.m[0][0] * dx + inv_m.m[0][1] * dy + inv_m.m[0][2];
            float sy = inv_m.m[1][0] * dx + inv_m.m[1][1] * dy + inv_m.m[1][2];

            int ix = std::clamp(static_cast<int>( std::round(sx) ), 0, width - 1);
            int iy = std::clamp(static_cast<int>( std::round(sy) ), 0, height - 1);

            uint8_t Y = nv21_buf[iy * width + ix];
            int uv_index = frame_size + (iy >> 1) * width + (ix & ~1);
            int V = static_cast<int>(nv21_buf[uv_index]) - 128;
            int U = static_cast<int>(nv21_buf[uv_index + 1]) - 128;

            // ITU-R BT.601 conversion
            float r = std::clamp(Y + 1.402f * V, 0.0f, 255.0f);
            float g = std::clamp(Y - 0.344136f * U - 0.714136f * V, 0.0f, 255.0f);
            float b = std::clamp(Y + 1.772f * U, 0.0f, 255.0f);

            int dst_idx = dy * 112 + dx;
            out_luma[dst_idx] = static_cast<float>(Y);

            // Normalize to [-1.0, 1.0] in NCHW layout
            out_nchw_tensor[0 * plane_stride + dst_idx] = (r - 127.5f) / 128.0f;
            out_nchw_tensor[1 * plane_stride + dst_idx] = (g - 127.5f) / 128.0f;
            out_nchw_tensor[2 * plane_stride + dst_idx] = (b - 127.5f) / 128.0f;
        }
    }
}

/**
 * Configures ONNX Runtime SessionOptions with XNNPACK execution provider
 * for in-process ARMv8 SDOT / NEON acceleration without NNAPI IPC jitter.
 */
inline Ort::SessionOptions CreateOptimizedSessionOptions() {
    Ort::SessionOptions session_options;
    session_options.SetIntraOpNumThreads(2);
    session_options.SetGraphOptimizationLevel(GraphOptimizationLevel::ORT_ENABLE_ALL);
    session_options.AppendExecutionProvider("XNNPACK", {{"intra_op_num_threads", "2"}});
    return session_options;
}

} // namespace kelasagara::biomatch

extern "C" {

JNIEXPORT jfloatArray JNICALL
Java_com_kelasagaara_kelasagaara_BiomatchNative_processAndAlignFrame(
    JNIEnv* env,
    jobject /* thiz */,
    jbyteArray nv21_data,
    jint width,
    jint height,
    jfloatArray five_landmarks_flat
) {
    jsize landmark_len = env->GetArrayLength(five_landmarks_flat);
    if (landmark_len != 10) {
        return nullptr;
    }

    jfloat* lmk_ptr = env->GetFloatArrayElements(five_landmarks_flat, nullptr);
    float src_pts[5][2];
    for (int i = 0; i < 5; ++i) {
        src_pts[i][0] = lmk_ptr[i * 2 + 0];
        src_pts[i][1] = lmk_ptr[i * 2 + 1];
    }
    env->ReleaseFloatArrayElements(five_landmarks_flat, lmk_ptr, JNI_ABORT);

    // Compute Umeyama inverse similarity
    auto inv_m = kelasagara::biomatch::ComputeInverseSimilarityMatrix(src_pts);

    jbyte* nv21_bytes = env->GetByteArrayElements(nv21_data, nullptr);
    std::vector<float> aligned_tensor;
    std::array<float, 112 * 112> luma_plane{};

    kelasagara::biomatch::WarpNV21ToAlignedRGBTensor(
        reinterpret_cast<const uint8_t*>(nv21_bytes),
        width,
        height,
        inv_m,
        aligned_tensor,
        luma_plane
    );

    float lap_var = kelasagara::biomatch::ComputeLaplacianVariance(luma_plane);
    env->ReleaseByteArrayElements(nv21_data, nv21_bytes, JNI_ABORT);

    // Output package: [0] = laplacian_variance, [1..N] = aligned tensor NCHW
    const size_t total_out_size = 1 + aligned_tensor.size();
    jfloatArray result = env->NewFloatArray(static_cast<jsize>(total_out_size));
    if (result != nullptr) {
        std::vector<float> package(total_out_size);
        package[0] = lap_var;
        std::copy(aligned_tensor.begin(), aligned_tensor.end(), package.begin() + 1);
        env->SetFloatArrayRegion(result, 0, static_cast<jsize>(total_out_size), package.data());
        
        // Zero-out sensitive biometric tensor from heap
        kelasagara::biomatch::SecureZeroMemory(package.data(), package.size() * sizeof(float));
    }

    kelasagara::biomatch::SecureZeroMemory(aligned_tensor.data(), aligned_tensor.size() * sizeof(float));
    return result;
}

} // extern "C"

