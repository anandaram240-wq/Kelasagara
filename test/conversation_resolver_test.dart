import 'package:flutter_test/flutter_test.dart';
import 'package:kelasagaara/services/messaging/conversation_resolver.dart';

void main() {
  test('ConversationResolver symmetry: order of UIDs does not change result', () {
    final id1 = ConversationResolver.resolve(uid1: 'userA', uid2: 'userB', jobId: 'job123');
    final id2 = ConversationResolver.resolve(uid1: 'userB', uid2: 'userA', jobId: 'job123');
    expect(id1, equals('userA_userB_job123'));
    expect(id1, equals(id2));
  });

  test('ConversationResolver normalizes direct_hire and direct_ to identical canonical ID', () {
    // Hirer clicks chat from hirer_dashboard (passed 'direct_hire_worker1')
    final hirerConv = ConversationResolver.resolve(
      uid1: 'hirer1',
      uid2: 'worker1',
      jobId: 'direct_hire_worker1',
    );

    // Worker clicks chat from hirer_profile_sheet (passed 'direct_hirer1')
    final workerConv = ConversationResolver.resolve(
      uid1: 'worker1',
      uid2: 'hirer1',
      jobId: 'direct_hirer1',
    );

    // Hirer clicks from worker_card (passed 'direct_worker1')
    final cardConv = ConversationResolver.resolve(
      uid1: 'hirer1',
      uid2: 'worker1',
      jobId: 'direct_worker1',
    );

    expect(hirerConv, equals('direct_hirer1_worker1'));
    expect(workerConv, equals('direct_hirer1_worker1'));
    expect(cardConv, equals('direct_hirer1_worker1'));
  });

  test('ConversationResolver preserves real job IDs backwards compatibility', () {
    final conv = ConversationResolver.resolve(
      uid1: 'hirer99',
      uid2: 'worker42',
      jobId: 'booking_aug_15',
    );
    expect(conv, equals('hirer99_worker42_booking_aug_15'));
  });
}
