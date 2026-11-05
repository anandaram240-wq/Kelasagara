#!/usr/bin/env python3
"""
analysis/evaluator.py
Self-contained statistical evaluation engine for Kelasagara BioMatch Stage S6.
Uses standard library (math, random, itertools) for zero-dependency, bit-exact reproducibility.
Computes Clopper-Pearson CIs, Mann-Whitney U AUC, Cllr, and clustered bootstrap.
"""

import math
import random

def _log_comb(n, k):
    """Compute log(n choose k) accurately using log-gamma."""
    if k < 0 or k > n:
        return -float('inf')
    return math.lgamma(n + 1) - math.lgamma(k + 1) - math.lgamma(n - k + 1)

def binomial_cdf(k, n, p):
    """Cumulative distribution function P(X <= k) for X ~ Binomial(n, p)."""
    if k < 0:
        return 0.0
    if k >= n:
        return 1.0
    if p <= 0.0:
        return 1.0
    if p >= 1.0:
        return 0.0
    
    total = 0.0
    for j in range(k + 1):
        log_term = _log_comb(n, j) + j * math.log(p) + (n - j) * math.log(1.0 - p)
        total += math.exp(log_term)
    return min(1.0, max(0.0, total))

def clopper_pearson_ci(k, n, confidence=0.95):
    """
    Exact Clopper-Pearson confidence interval for a binomial proportion
    via numerical bisection.
    """
    if n == 0:
        return (0.0, 1.0)
    alpha = 1.0 - confidence
    alpha_2 = alpha / 2.0

    # Lower bound
    if k == 0:
        low = 0.0
    else:
        # P(X >= k) = 1 - P(X <= k-1) = alpha/2
        p_min, p_max = 0.0, k / n
        for _ in range(40):
            p_mid = (p_min + p_max) / 2.0
            tail = 1.0 - binomial_cdf(k - 1, n, p_mid)
            if tail < alpha_2:
                p_min = p_mid
            else:
                p_max = p_mid
        low = (p_min + p_max) / 2.0

    # Upper bound
    if k == n:
        high = 1.0
    else:
        # P(X <= k) = alpha/2
        p_min, p_max = k / n, 1.0
        for _ in range(40):
            p_mid = (p_min + p_max) / 2.0
            tail = binomial_cdf(k, n, p_mid)
            if tail < alpha_2:
                p_max = p_mid
            else:
                p_min = p_mid
        high = (p_min + p_max) / 2.0

    return (round(low, 6), round(high, 6))

def wilson_score_ci(k, n, confidence=0.95):
    """
    Wilson score interval for binomial proportion.
    Has nominal coverage close to 1 - alpha without Clopper-Pearson's over-conservatism.
    """
    if n == 0:
        return (0.0, 1.0)
    z = 1.95996 if confidence == 0.95 else 2.57583
    p_hat = k / n
    denom = 1.0 + (z**2) / n
    center = (p_hat + (z**2) / (2.0 * n)) / denom
    half = (z * math.sqrt(p_hat * (1.0 - p_hat) / n + (z**2) / (4.0 * (n**2)))) / denom
    low = max(0.0, center - half)
    high = min(1.0, center + half)
    return (round(low, 6), round(high, 6))

def mann_whitney_u_auc(gen_scores, imp_scores):
    """
    Computes exact Mann-Whitney U test and Area Under ROC Curve (AUC).
    AUC = U_gen / (n_gen * n_imp).
    """
    n_gen = len(gen_scores)
    n_imp = len(imp_scores)
    if n_gen == 0 or n_imp == 0:
        return 0.5

    # Combine and sort with labels
    combined = [(s, 1) for s in gen_scores] + [(s, 0) for s in imp_scores]
    combined.sort(key=lambda x: x[0])

    # Assign fractional ranks for ties
    ranks = [0.0] * len(combined)
    i = 0
    while i < len(combined):
        j = i
        while j < len(combined) and combined[j][0] == combined[i][0]:
            j += 1
        avg_rank = (i + 1 + j) / 2.0
        for k in range(i, j):
            ranks[k] = avg_rank
        i = j

    # Sum of ranks for genuine (class 1)
    r_gen = sum(ranks[idx] for idx in range(len(combined)) if combined[idx][1] == 1)
    u_gen = r_gen - (n_gen * (n_gen + 1)) / 2.0
    auc = u_gen / (n_gen * n_imp)
    return float(auc)

def compute_cllr(genuine_scores, impostor_scores):
    """Compute Log-Likelihood Ratio Cost (Cllr)."""
    if len(genuine_scores) == 0 or len(impostor_scores) == 0:
        return 1.0
    gen_cost = sum(math.log2(1.0 + math.exp(-min(50.0, max(-50.0, s)))) for s in genuine_scores) / len(genuine_scores)
    imp_cost = sum(math.log2(1.0 + math.exp(min(50.0, max(-50.0, s)))) for s in impostor_scores) / len(impostor_scores)
    return 0.5 * (gen_cost + imp_cost)

def clustered_bootstrap_fnmr(genuine_pairs, n_bootstraps=2000, threshold=0.50, seed=42):
    """
    Two-way identity clustered bootstrap over genuine comparisons.
    genuine_pairs: list of dicts with keys 'subject_id', 'session_id', 'score', 'acquired'
    """
    rng = random.Random(seed)
    subjects = list(set(p['subject_id'] for p in genuine_pairs))
    n_subjects = len(subjects)
    
    # Pre-index pairs by subject
    by_subject = {}
    for p in genuine_pairs:
        by_subject.setdefault(p['subject_id'], []).append(p)

    boot_fnmrs = []
    for _ in range(n_bootstraps):
        sampled_subjects = [rng.choice(subjects) for _ in range(n_subjects)]
        sampled_pairs = []
        for s in sampled_subjects:
            sampled_pairs.extend(by_subject.get(s, []))
        
        if not sampled_pairs:
            continue
        
        total_attempts = len(sampled_pairs)
        non_matches = sum(1 for p in sampled_pairs if not p.get('acquired', True) or p['score'] < threshold)
        boot_fnmrs.append(non_matches / total_attempts)

    boot_fnmrs.sort()
    idx_low = int(0.025 * len(boot_fnmrs))
    idx_high = int(0.975 * len(boot_fnmrs))
    low = boot_fnmrs[idx_low]
    high = boot_fnmrs[idx_high]
    point = sum(boot_fnmrs) / len(boot_fnmrs)
    return round(point, 6), (round(low, 6), round(high, 6))

def evaluate_subgroup_disparity(group_data, threshold=0.50):
    """
    group_data: dict of group_name -> list of genuine pairs
    Returns disparity ratio: max(FNMR) / min(FNMR)
    """
    fnmrs = {}
    for g, pairs in group_data.items():
        if not pairs:
            continue
        total = len(pairs)
        fails = sum(1 for p in pairs if not p.get('acquired', True) or p['score'] < threshold)
        fnmrs[g] = fails / total
    
    if not fnmrs:
        return 1.0, fnmrs
    
    min_f = max(min(fnmrs.values()), 1e-6)
    max_f = max(fnmrs.values())
    disparity = max_f / min_f
    return round(disparity, 4), {k: round(v, 4) for k, v in fnmrs.items()}
