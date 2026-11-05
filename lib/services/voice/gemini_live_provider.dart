// lib/services/voice/gemini_live_provider.dart
// Gemini Conversational AI Provider with Strict Tool Calling & Multilingual Kannada/English Support

import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'voice_api_config.dart';

class GeminiFunctionCall {
  final String name;
  final Map<String, dynamic> arguments;

  GeminiFunctionCall({required this.name, required this.arguments});
}

class GeminiConversationResponse {
  final String? textResponse;
  final GeminiFunctionCall? functionCall;

  GeminiConversationResponse({this.textResponse, this.functionCall});
}

class GeminiLiveProvider {
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 15),
  ));

  static const String _systemInstruction = '''
You are the Kelasagara Voice Assistant, an AI companion for Hirers in Karnataka, India.
You understand Kannada, Indian English, and Code-Mixed Kannada-English.
You assist Hirers with searching workers, checking availability, checking worker verification, tracking active workers, and booking workers.

ABSOLUTE SECURITY RULES:
1. NEVER disclose, display, or speculate on passwords. If asked "What is my password?", you MUST respond:
   "For security, I can't display your password. You can reset it from Account Security." (or in Kannada: "ಭದ್ರತೆಯ ಕಾರಣದಿಂದ, ನಾನು ನಿಮ್ಮ ಪಾಸ್‌ವರ್ಡ್ ಅನ್ನು ಪ್ರದರ್ಶಿಸಲು ಸಾಧ್ಯವಿಲ್ಲ. ನೀವು ಖಾತೆ ಭದ್ರತೆಯಿಂದ ಅದನ್ನು ಮರುಹೊಂದಿಸಬಹುದು.")
2. Do NOT invent fake workers, fake IDs, or fake ratings. Always use function calls to retrieve real data.
3. Keep spoken responses concise: 1 to 2 natural sentences. Speak in the user's language (Kannada, English, or mixed).
''';

  /// All 16 Tool Declarations for Gemini Function Calling
  static final List<Map<String, dynamic>> toolDeclarations = [
    {
      'name': 'searchWorkersNearby',
      'description': 'Search available workers near the hirer by skill and radius.',
      'parameters': {
        'type': 'OBJECT',
        'properties': {
          'skillId': {'type': 'STRING', 'description': 'The required skill, e.g. painter, plumber, electrician, carpenter, mason, driver, cook'},
          'radiusMeters': {'type': 'NUMBER', 'description': 'Optional search radius in meters (e.g. 2000, 5000)'},
          'requestedDate': {'type': 'STRING', 'description': 'Optional requested date or tomorrow'},
          'requiredVerificationLevel': {'type': 'STRING', 'description': 'Optional minimum verification level: basicAssessed, practicalVerified, experienced, advanced'},
        },
        'required': ['skillId'],
      },
    },
    {
      'name': 'getWorkerDetails',
      'description': 'Get detailed profile information about a specific worker.',
      'parameters': {
        'type': 'OBJECT',
        'properties': {
          'workerId': {'type': 'STRING', 'description': 'The unique worker UID'},
        },
        'required': ['workerId'],
      },
    },
    {
      'name': 'getWorkerAvailability',
      'description': 'Check real-time availability of a worker for a specific date or time.',
      'parameters': {
        'type': 'OBJECT',
        'properties': {
          'workerId': {'type': 'STRING', 'description': 'The worker UID'},
          'date': {'type': 'STRING', 'description': 'Requested date e.g. today, tomorrow'},
        },
        'required': ['workerId'],
      },
    },
    {
      'name': 'getWorkerDistance',
      'description': 'Calculate exact distance from user to a worker.',
      'parameters': {
        'type': 'OBJECT',
        'properties': {
          'workerId': {'type': 'STRING', 'description': 'The worker UID'},
        },
        'required': ['workerId'],
      },
    },
    {
      'name': 'getWorkerCompletedJobs',
      'description': 'Get count and details of verified jobs completed by a worker.',
      'parameters': {
        'type': 'OBJECT',
        'properties': {
          'workerId': {'type': 'STRING', 'description': 'The worker UID'},
        },
        'required': ['workerId'],
      },
    },
    {
      'name': 'getWorkerVerification',
      'description': 'Get formal skill verification level and passport badges for a worker.',
      'parameters': {
        'type': 'OBJECT',
        'properties': {
          'workerId': {'type': 'STRING', 'description': 'The worker UID'},
        },
        'required': ['workerId'],
      },
    },
    {
      'name': 'createBooking',
      'description': 'Create an actual verified booking for a worker.',
      'parameters': {
        'type': 'OBJECT',
        'properties': {
          'workerId': {'type': 'STRING', 'description': 'The worker UID to book'},
          'skillId': {'type': 'STRING', 'description': 'Skill type for the booking'},
          'date': {'type': 'STRING', 'description': 'Date of work'},
          'time': {'type': 'STRING', 'description': 'Time of work'},
        },
        'required': ['workerId', 'skillId'],
      },
    },
    {
      'name': 'cancelBooking',
      'description': 'Cancel an existing booking.',
      'parameters': {
        'type': 'OBJECT',
        'properties': {
          'bookingId': {'type': 'STRING', 'description': 'The booking document ID'},
          'reason': {'type': 'STRING', 'description': 'Reason for cancellation'},
        },
        'required': ['bookingId'],
      },
    },
    {
      'name': 'getActiveBookings',
      'description': 'List active ongoing or confirmed bookings for the current hirer.',
      'parameters': {
        'type': 'OBJECT',
        'properties': {},
      },
    },
    {
      'name': 'getBookingDetails',
      'description': 'Get full details of a specific booking.',
      'parameters': {
        'type': 'OBJECT',
        'properties': {
          'bookingId': {'type': 'STRING', 'description': 'The booking ID'},
        },
        'required': ['bookingId'],
      },
    },
    {
      'name': 'getWorkerLiveLocation',
      'description': 'Track current live GPS location of the assigned worker for an active booking.',
      'parameters': {
        'type': 'OBJECT',
        'properties': {
          'bookingId': {'type': 'STRING', 'description': 'The active booking ID'},
        },
        'required': ['bookingId'],
      },
    },
    {
      'name': 'navigateToScreen',
      'description': 'Navigate to a specific application screen (e.g. jobs, applicants, bookings, profile, tracking).',
      'parameters': {
        'type': 'OBJECT',
        'properties': {
          'screenName': {'type': 'STRING', 'description': 'Name of the screen'},
        },
        'required': ['screenName'],
      },
    },
    {
      'name': 'getCurrentLocation',
      'description': 'Fetch current verified GPS location of the user device.',
      'parameters': {
        'type': 'OBJECT',
        'properties': {},
      },
    },
    {
      'name': 'getCurrentUser',
      'description': 'Get profile of the currently logged-in Hirer.',
      'parameters': {
        'type': 'OBJECT',
        'properties': {},
      },
    },
    {
      'name': 'confirmAction',
      'description': 'Confirm a pending high-risk action such as booking confirmation.',
      'parameters': {
        'type': 'OBJECT',
        'properties': {
          'actionId': {'type': 'STRING', 'description': 'Identifier of the pending action'},
        },
        'required': ['actionId'],
      },
    },
    {
      'name': 'cancelAction',
      'description': 'Decline or cancel a pending action.',
      'parameters': {
        'type': 'OBJECT',
        'properties': {
          'actionId': {'type': 'STRING', 'description': 'Identifier of the pending action'},
        },
        'required': ['actionId'],
      },
    },
    {
      'name': 'listMyApplications',
      'description': 'Retrieve list of job applications or works for the current user.',
      'parameters': {
        'type': 'OBJECT',
        'properties': {},
      },
    },
  ];

  /// Process User Utterance through Gemini Conversational Engine
  Future<GeminiConversationResponse> processUtterance({
    required String prompt,
    List<Map<String, dynamic>>? history,
  }) async {
    final apiKey = VoiceApiConfig.geminiApiKey;
    final url = 'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=$apiKey';

    final contents = <Map<String, dynamic>>[];
    if (history != null) {
      contents.addAll(history);
    }
    contents.add({
      'role': 'user',
      'parts': [{'text': prompt}],
    });

    final payload = {
      'system_instruction': {
        'parts': [{'text': _systemInstruction}],
      },
      'contents': contents,
      'tools': [
        {'function_declarations': toolDeclarations},
      ],
    };

    try {
      final response = await _dio.post(
        url,
        data: payload,
        options: Options(headers: {'Content-Type': 'application/json'}),
      );

      if (response.statusCode == 200 && response.data != null) {
        final candidates = response.data['candidates'] as List?;
        if (candidates != null && candidates.isNotEmpty) {
          final content = candidates.first['content'] as Map<String, dynamic>?;
          final parts = content?['parts'] as List?;
          if (parts != null && parts.isNotEmpty) {
            for (final part in parts) {
              if (part.containsKey('functionCall')) {
                final fc = part['functionCall'] as Map<String, dynamic>;
                return GeminiConversationResponse(
                  functionCall: GeminiFunctionCall(
                    name: fc['name'] as String? ?? '',
                    arguments: Map<String, dynamic>.from(fc['args'] ?? {}),
                  ),
                );
              }
              if (part.containsKey('text')) {
                return GeminiConversationResponse(
                  textResponse: part['text'] as String?,
                );
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[GeminiLiveProvider] Error processing utterance: $e');
    }

    return GeminiConversationResponse(
      textResponse: 'ಕ್ಷಮಿಸಿ, ಸಂಪರ್ಕಿಸಲು ಸಾಧ್ಯವಾಗುತ್ತಿಲ್ಲ. ದಯವಿಟ್ಟು ಮತ್ತೆ ಪ್ರಯತ್ನಿಸಿ.',
    );
  }

  /// Generate Spoken Summary of Tool Result
  Future<String> summarizeToolResult({
    required String toolName,
    required Map<String, dynamic> toolResult,
    required String userLanguage,
  }) async {
    final apiKey = VoiceApiConfig.geminiApiKey;
    final url = 'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=$apiKey';

    final prompt = 'Tool "$toolName" executed with result: ${jsonEncode(toolResult)}. '
        'Summarize this result for the user in 1-2 spoken sentences. '
        'Language: $userLanguage. '
        'Be clear, polite, and helpful.';

    try {
      final response = await _dio.post(
        url,
        data: {
          'system_instruction': {'parts': [{'text': _systemInstruction}]},
          'contents': [{'parts': [{'text': prompt}]}],
        },
        options: Options(headers: {'Content-Type': 'application/json'}),
      );
      if (response.statusCode == 200 && response.data != null) {
        final candidates = response.data['candidates'] as List?;
        if (candidates != null && candidates.isNotEmpty) {
          final parts = candidates.first['content']?['parts'] as List?;
          if (parts != null && parts.isNotEmpty) {
            return parts.first['text'] as String? ?? '';
          }
        }
      }
    } catch (e) {
      debugPrint('[GeminiLiveProvider] Summarize error: $e');
    }

    // Deterministic fallback summary
    if (toolName == 'searchWorkersNearby') {
      final count = toolResult['candidateCount'] ?? 0;
      if (count == 0) {
        return userLanguage.contains('en')
            ? 'No available workers found nearby.'
            : 'ನಿಮ್ಮ ಹತ್ತಿರ ಯಾವುದೇ ಕೆಲಸಗಾರರು ಲಭ್ಯವಿಲ್ಲ.';
      }
      final top = toolResult['candidates']?[0];
      final name = top?['name'] ?? 'Worker';
      final dist = top?['distanceDisplay'] ?? '';
      return userLanguage.contains('en')
          ? 'Found $count available workers. $name is closest at $dist.'
          : '$count ಕೆಲಸಗಾರರು ಲಭ್ಯವಿದ್ದಾರೆ. $name $dist ದೂರದಲ್ಲಿದ್ದಾರೆ.';
    } else if (toolName == 'createBooking') {
      final status = toolResult['status'];
      if (status == 'confirmed') {
        return userLanguage.contains('en')
            ? 'Booking confirmed successfully.'
            : 'ಬುಕಿಂಗ್ ಯಶಸ್ವಿಯಾಗಿ ಖಚಿತಪಟ್ಟಿದೆ.';
      }
    }
    return userLanguage.contains('en') ? 'Action completed.' : 'ಕಾರ್ಯ ಪೂರ್ಣಗೊಂಡಿದೆ.';
  }
}
