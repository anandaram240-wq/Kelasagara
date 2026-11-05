// GENERATED from backend/src/biometrics/model_contract.ts. DO NOT EDIT.
#pragma once
namespace biomatch {
constexpr const char* kModelId = "indicface128-int8-v1";
constexpr int kInputSize = 112;
constexpr int kEmbeddingDim = 128;
constexpr bool kBgr = false;
constexpr float kMean = 127.5000f;
constexpr float kStd = 127.5000f;
constexpr float kAlignTemplate112[5][2] = {
    {38.2946f, 51.6963f},
    {73.5318f, 51.5014f},
    {56.0252f, 71.7366f},
    {41.5493f, 92.3655f},
    {70.7299f, 92.2041f},
};
}  // namespace biomatch
