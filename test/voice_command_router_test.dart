// test/voice_command_router_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:kelasagaara/services/voice/fast_local_command_router.dart';

void main() {
  group('FastLocalCommandRouter — Core Trade Voice Commands', () {
    test('routes "nearby painter" to searchWorkersNearby with skillId painter', () {
      final res = FastLocalCommandRouter.tryRoute(utterance: 'nearby painter');
      expect(res.isHandled, isTrue);
      expect(res.toolName, 'searchWorkersNearby');
      expect(res.arguments['skillId'], 'painter');
    });

    test('routes "ನನ್ನ ಹತ್ತಿರ ಪೇಂಟರ್ ಬೇಕು" to searchWorkersNearby with skillId painter', () {
      final res = FastLocalCommandRouter.tryRoute(utterance: 'ನನ್ನ ಹತ್ತಿರ ಪೇಂಟರ್ ಬೇಕು');
      expect(res.isHandled, isTrue);
      expect(res.toolName, 'searchWorkersNearby');
      expect(res.arguments['skillId'], 'painter');
    });

    test('routes "plumber near me" to searchWorkersNearby with skillId plumber', () {
      final res = FastLocalCommandRouter.tryRoute(utterance: 'plumber near me');
      expect(res.isHandled, isTrue);
      expect(res.toolName, 'searchWorkersNearby');
      expect(res.arguments['skillId'], 'plumber');
    });

    test('routes "electrician beku" to searchWorkersNearby with skillId electrician', () {
      final res = FastLocalCommandRouter.tryRoute(utterance: 'electrician beku');
      expect(res.isHandled, isTrue);
      expect(res.toolName, 'searchWorkersNearby');
      expect(res.arguments['skillId'], 'electrician');
    });

    test('routes "ನನ್ನ ಅರ್ಜಿಗಳು" to listMyApplications', () {
      final res = FastLocalCommandRouter.tryRoute(utterance: 'ನನ್ನ ಅರ್ಜಿಗಳು');
      expect(res.isHandled, isTrue);
      expect(res.toolName, 'listMyApplications');
      expect(res.directAction, 'SHOW_APPLICATIONS');
    });

    test('routes "my applications" to listMyApplications', () {
      final res = FastLocalCommandRouter.tryRoute(utterance: 'my applications');
      expect(res.isHandled, isTrue);
      expect(res.toolName, 'listMyApplications');
      expect(res.directAction, 'SHOW_APPLICATIONS');
    });

    test('routes "show my work" to listMyApplications', () {
      final res = FastLocalCommandRouter.tryRoute(utterance: 'show my work');
      expect(res.isHandled, isTrue);
      expect(res.toolName, 'listMyApplications');
      expect(res.directAction, 'SHOW_APPLICATIONS');
    });
  });
}
