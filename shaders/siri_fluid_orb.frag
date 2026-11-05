// shaders/siri_fluid_orb.frag
#version 460 core
#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
uniform float uTime;
uniform float uAmplitude; // [0.0, 1.0] directly from C++ Oboe RMS
uniform float uState;     // 0.0=Idle, 1.0=Listening, 2.0=Thinking, 3.0=Speaking

out vec4 fragColor;

// Branchless palette interpolation using step/mix for Impeller GPU efficiency
void resolvePalette(float state, out vec3 colA, out vec3 colB, out vec3 colC) {
    // Idle: Purple (#7C3AED) -> Saffron (#F5820A)
    vec3 idleA = vec3(0.486, 0.227, 0.929);
    vec3 idleB = vec3(0.961, 0.510, 0.039);
    vec3 idleC = vec3(0.753, 0.518, 0.988);

    // Listening: Cobalt (#2563EB) -> Cyan (#06B6D4)
    vec3 listA = vec3(0.145, 0.388, 0.922);
    vec3 listB = vec3(0.024, 0.714, 0.831);
    vec3 listC = vec3(0.220, 0.741, 0.973);

    // Thinking: Deep Violet (#4C1D95) -> Amber (#F59E0B)
    vec3 thnkA = vec3(0.298, 0.114, 0.584);
    vec3 thnkB = vec3(0.961, 0.620, 0.043);
    vec3 thnkC = vec3(0.659, 0.333, 0.969);

    // Speaking: Emerald (#059669) -> Mint (#10B981)
    vec3 spkA  = vec3(0.020, 0.588, 0.412);
    vec3 spkB  = vec3(0.063, 0.725, 0.506);
    vec3 spkC  = vec3(0.204, 0.827, 0.600);

    float w1 = clamp(1.0 - abs(state - 0.0), 0.0, 1.0);
    float w2 = clamp(1.0 - abs(state - 1.0), 0.0, 1.0);
    float w3 = clamp(1.0 - abs(state - 2.0), 0.0, 1.0);
    float w4 = clamp(1.0 - abs(state - 3.0), 0.0, 1.0);

    colA = idleA * w1 + listA * w2 + thnkA * w3 + spkA * w4;
    colB = idleB * w1 + listB * w2 + thnkB * w3 + spkB * w4;
    colC = idleC * w1 + listC * w2 + thnkC * w3 + spkC * w4;
}

void main() {
    vec2 fragCoord = FlutterFragCoord().xy;
    vec2 uv = (fragCoord - 0.5 * uSize) / min(uSize.x, uSize.y);
    float r = length(uv);
    float theta = atan(uv.y, uv.x);

    vec3 colA, colB, colC;
    resolvePalette(uState, colA, colB, colC);

    // Harmonic liquid distortion driven by real-time mic/TTS RMS amplitude
    float dynamicAmp = 0.035 + (uAmplitude * 0.145);
    float wave1 = sin(theta * 3.0 + uTime * 2.4) * cos(theta * 2.0 - uTime * 1.7);
    float wave2 = sin(theta * 5.0 - uTime * 3.1) * 0.65;
    float wave3 = cos(theta * 4.0 + uTime * 4.0) * 0.45;

    float radius1 = 0.31 + wave1 * dynamicAmp;
    float radius2 = 0.28 + wave2 * (dynamicAmp * 1.15);
    float radius3 = 0.25 + wave3 * (dynamicAmp * 0.85);

    // Smooth anti-aliased signed distance masks (zero branching)
    float layer1 = 1.0 - smoothstep(radius1 - 0.04, radius1 + 0.04, r);
    float layer2 = 1.0 - smoothstep(radius2 - 0.03, radius2 + 0.03, r);
    float layer3 = 1.0 - smoothstep(radius3 - 0.02, radius3 + 0.02, r);

    // Outer ambient bloom
    float bloom = exp(-r * (4.8 - uAmplitude * 1.6)) * (0.65 + uAmplitude * 0.45);

    // Specular 3D glassmorphic core highlight
    vec2 highlightOffset = uv - vec2(-0.08, -0.08);
    float specular = exp(- dot(highlightOffset, highlightOffset) * 28.0) * 0.55;

    vec3 color = colA * bloom;
    color = mix(color, colB, layer1 * 0.65);
    color = mix(color, colC, layer2 * 0.75);
    color = mix(color, mix(colA, colB, 0.5 + 0.5 * sin(uTime + theta)), layer3);
    color += vec3(1.0) * specular * layer1;

    float alpha = clamp(bloom + layer1 + layer2 + layer3, 0.0, 1.0);
    fragColor = vec4(color * alpha, alpha);
}
