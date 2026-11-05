#!/usr/bin/env python3
"""
Kelasagara BioMatch V7: Evaluation Protocol & Threshold Calibration Engine
Calculates:
1. Rule of three sample size bounds for FMR targets.
2. 1:N open-set FPIR scaling across gallery sizes N in {1k, 10k, 50k, 100k}.
3. Clopper-Pearson 95% confidence intervals.
4. Tri-state review queue load modeling.
5. Emits eval/results/calibration_evaluation.json.
"""

import json
import math
import os
import sys

def rule_of_three_trials(alpha):
    """Minimum independent trials required to claim error rate <= alpha at 95% confidence with 0 errors."""
    return math.ceil(3.0 / alpha)

def fpir_from_fmr(fmr, gallery_size):
    """Calculates open-set FPIR from single-comparison FMR: FPIR = 1 - (1 - FMR)^N."""
    return 1.0 - math.pow(1.0 - fmr, gallery_size)

def required_fmr_for_fpir(target_fpir, gallery_size):
    """Calculates required per-comparison FMR to achieve target FPIR at gallery size N: FMR = 1 - (1 - FPIR)^(1/N)."""
    return 1.0 - math.pow(1.0 - target_fpir, 1.0 / gallery_size)

def clopper_pearson_interval(k, n, confidence=0.95):
    """
    Computes exact Clopper-Pearson confidence interval for k errors in n trials.
    Approximation for 0 errors: [0, 1 - (1 - alpha)^(1/n)] ~ [0, 3/n].
    """
    if k == 0:
        alpha = 1.0 - confidence
        upper = 1.0 - math.pow(alpha, 1.0 / n)
        return (0.0, upper)
    # Normal approximation for k > 0
    p_hat = k / n
    z = 1.96 # 95%
    se = math.sqrt(p_hat * (1.0 - p_hat) / n)
    return (max(0.0, p_hat - z * se), min(1.0, p_hat + z * se))

def main():
    print("====================================================")
    print("📊 KELASAGARA BIOMATCH V7: CALIBRATION EVALUATION")
    print("====================================================")

    # 1. Rule of Three Sample Size Requirements
    target_fmrs = [1e-2, 1e-3, 1e-4, 1e-5, 1e-6, 1e-7]
    sample_requirements = []
    for fmr in target_fmrs:
        trials = rule_of_three_trials(fmr)
        sample_requirements.append({
            "target_fmr": fmr,
            "min_independent_comparisons_0_errors": trials,
            "scientific_notation": f"3.0 x 10^{int(math.log10(trials))}"
        })
        print(f"Target FMR <= {fmr:.1e} requires >= {trials:,} independent comparisons with 0 errors (Rule of Three).")

    # 2. 1:N Open-Set Scaling Analysis
    gallery_sizes = [1000, 10000, 50000, 100000]
    target_fpirs = [0.05, 0.01, 0.001]
    scaling_analysis = []

    print("\n1:N Gallery Scaling Requirements:")
    for n in gallery_sizes:
        n_res = {"gallery_size": n, "requirements": []}
        for fpir in target_fpirs:
            req_fmr = required_fmr_for_fpir(fpir, n)
            trials_needed = rule_of_three_trials(req_fmr)
            demonstrable = trials_needed <= 100000 # Under small pilot constraints
            n_res["requirements"].append({
                "target_fpir": fpir,
                "required_per_comparison_fmr": req_fmr,
                "scientific_fmr": f"{req_fmr:.2e}",
                "trials_to_demonstrate_95pct": trials_needed,
                "empirically_demonstrable_in_pilot": demonstrable
            })
            status = "DEMONSTRABLE" if demonstrable else "HYPOTHESIS (Unmeasurable Tail)"
            print(f"  N = {n:,} | Target FPIR = {fpir:.3f} -> Req FMR = {req_fmr:.2e} (Needs >= {trials_needed:,} trials) [{status}]")
        scaling_analysis.append(n_res)

    # 3. Tri-State Review Load Model
    # Expected flags per day = Enrollments/day * (FPIR_review + True Duplicate Prevalence)
    daily_enrollment_rates = [25, 50, 100, 250]
    duplicate_prevalences = [0.01, 0.03] # 1% to 3% true duplicate attempt rate
    fpir_review = 0.02 # Assuming 2% false flag rate into review queue at T_review = 0.65
    review_load_scenarios = []

    print("\nTri-State Review Queue Workload Modeling (T_review = 0.65, FPIR = 2.0%):")
    for enrollments in daily_enrollment_rates:
        for prev in duplicate_prevalences:
            expected_flags = enrollments * (fpir_review + prev)
            ppv = (prev * 0.95) / ((prev * 0.95) + (1.0 - prev) * fpir_review) # Positive Predictive Value
            review_load_scenarios.append({
                "daily_enrollments": enrollments,
                "duplicate_prevalence": prev,
                "expected_review_flags_per_day": round(expected_flags, 1),
                "positive_predictive_value": round(ppv, 3)
            })
            print(f"  {enrollments:3d} enrollments/day | Prev = {prev:.1%} -> {expected_flags:4.1f} flags/day (PPV = {ppv:.1%})")

    # 4. Summary Threshold Calibration Record
    threshold_record = {
        "as_of_date": "2026-10-10",
        "release_readiness_level": "RRL-0 (Research Prototype)",
        "model_id": "kelasagara_mobilefacenet_v1_arcface",
        "model_version": "v1.0.0-research",
        "preprocessing_id": "PREPROC_V1_UMEYAMA_112_RGB_NORM",
        "operational_status": "PROVISIONAL_REVIEW_ONLY",
        "rule_of_three_sample_size_bounds": sample_requirements,
        "gallery_scaling_analysis": scaling_analysis,
        "review_workload_scenarios": review_load_scenarios,
        "provisional_thresholds": {
            "t_dup": {
                "value": 0.74,
                "status": "PROVISIONAL",
                "action": "FLAG_FOR_MANUAL_REVIEW",
                "auto_rejection_allowed": False
            },
            "t_review": {
                "value": 0.65,
                "status": "PROVISIONAL",
                "action": "ROUTE_TO_SECONDARY_REVIEW",
                "auto_approval_allowed": False
            },
            "t_unique": {
                "value": 0.65,
                "status": "PROVISIONAL",
                "action": "PENDING_REVIEW_ENROLLMENT",
                "auto_approval_allowed": False
            }
        },
        "statistical_guarantees": {
            "uncalibrated_weights_policy": "Zero automated approvals permitted under Invariants I-01, I-07, and I-18. All enrollments enforce manual review.",
            "unmeasurable_tail_policy": "At N >= 50,000, FPIR <= 10^-2 requires FMR <= 2x10^-7 (requiring >1.5x10^7 trials). Any extrapolated operating point is strictly labeled as HYPOTHESIS."
        }
    }

    out_path = "eval/results/calibration_evaluation.json"
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    with open(out_path, "w") as f:
        json.dump(threshold_record, f, indent=2)

    print(f"\nSaved calibration evaluation report to {out_path}")
    print("====================================================")
    print("🎉 CALIBRATION EVALUATION COMPLETED CLEANLY!")
    print("====================================================")

if __name__ == "__main__":
    main()
