/// Canonical conversation ID resolver.
/// Eliminates divergent IDs between participants by sorting UIDs deterministically
/// and normalizing direct-hire prefixes.
class ConversationResolver {
  /// Resolves the canonical, deterministic conversation ID.
  ///
  /// Guarantees:
  /// 1. Order-independence: resolve(A, B, jobId) == resolve(B, A, jobId)
  /// 2. Direct-hire normalization:
  ///    - 'direct_hire_123', 'direct_456', or null/empty -> 'direct_{min}_{max}'
  /// 3. Backwards compatibility:
  ///    - For real job IDs: '{min}_{max}_{jobId}'
  static String resolve({
    required String uid1,
    required String uid2,
    String? jobId,
  }) {
    final sorted = [uid1.trim(), uid2.trim()]..sort();
    final first = sorted[0];
    final second = sorted[1];

    final cleanedJobId = (jobId ?? '').trim();

    // Check if direct consultation (no job ID, or legacy direct_ / direct_hire_ prefixes)
    if (cleanedJobId.isEmpty ||
        cleanedJobId == 'direct' ||
        cleanedJobId.startsWith('direct_hire_') ||
        cleanedJobId.startsWith('direct_')) {
      return 'direct_${first}_$second';
    }

    // Normal job-scoped conversation (maintains backwards compatibility)
    return '${first}_${second}_$cleanedJobId';
  }

  /// Extracts the other user's UID given the participant list and current user's UID.
  static String getOtherUid(List<String> participants, String myUid) {
    return participants.firstWhere((id) => id != myUid, orElse: () => '');
  }

  /// Determines if a conversation ID corresponds to a direct chat.
  static bool isDirect(String convId) => convId.startsWith('direct_');
}
