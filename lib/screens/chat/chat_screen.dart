import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart' hide AuthProvider;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme/app_colors.dart';
import '../../models/messaging/chat_message.dart';
import '../../providers/auth_provider.dart';
import '../../services/location_service.dart';
import '../../services/messaging/conversation_resolver.dart';
import '../../services/messaging/messaging_connectivity_service.dart';
import '../../services/messaging/messaging_facade.dart';
import '../../services/messaging/messaging_outbox_service.dart';
import '../../services/messaging/presence_service.dart';
import '../../services/voice_service.dart';

/// Fast, responsive WhatsApp-style ChatScreen with optimistic UI,
/// offline outbox, delivery & read receipts, and real-time presence.
class ChatScreen extends StatefulWidget {
  final String workerName;
  final String jobTitle;
  final String otherUserId;
  final String? jobId;

  const ChatScreen({
    super.key,
    required this.workerName,
    required this.jobTitle,
    required this.otherUserId,
    this.jobId,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _msgCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _voice = VoiceService();

  bool _isListening = false;
  bool _sharingLocation = false;
  ChatMessage? _replyingTo;
  StreamSubscription? _msgSub;
  StreamSubscription? _typingSub;
  StreamSubscription? _presenceSub;
  Timer? _bootstrapTimer;
  List<ChatMessage> _messages = [];
  String? _convId;
  String? _myUid;
  bool _connected = false;
  bool _otherTyping = false;
  bool _bootstrapDone = false;
  RemotePresence _remotePresence = RemotePresence.unknown;

  static const _quickReplies = [
    '30 ನಿಮಿಷದಲ್ಲಿ ಬರುತ್ತೇನೆ',
    'ಸ್ಥಳಕ್ಕೆ ಬಂದಿದ್ದೇನೆ',
    'ಕೆಲಸ ಪ್ರಾರಂಭಿಸಿದೆ',
    'ಕೆಲಸ ಮುಗಿಯಿತು',
    '📍 ಸ್ಥಳ ಶೇರ್ ಮಾಡಿ',
    'ಸರಿ, ಒಪ್ಪಿದ್ದೇನೆ',
    'ಹಣ ಕಳಿಸಿ',
  ];

  @override
  void initState() {
    super.initState();
    final auth = context.read<AuthProvider>();
    final myUid = auth.uid;
    if (myUid != null) {
      _myUid = myUid;
      _convId = ConversationResolver.resolve(
        uid1: myUid,
        uid2: widget.otherUserId,
        jobId: widget.jobId,
      );
    }
    _msgCtrl.addListener(() => setState(() {}));
    _initChat();
  }

  Future<void> _initChat() async {
    final auth = context.read<AuthProvider>();
    final myUid = auth.uid;
    if (myUid == null) return;
    _myUid = myUid;

    // 1. Resolve canonical conversation ID synchronously and immediately
    _convId = ConversationResolver.resolve(
      uid1: myUid,
      uid2: widget.otherUserId,
      jobId: widget.jobId,
    );

    // 2. Start 3-second bootstrap timer for local connection display
    _bootstrapTimer?.cancel();
    _bootstrapTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && !_bootstrapDone) {
        setState(() => _bootstrapDone = true);
      }
    });

    // 3. Initialize Presence and listen to remote user's presence in RTDB
    try {
      unawaited(PresenceService.instance.initialize(myUid));
      _presenceSub?.cancel();
      _presenceSub = PresenceService.instance
          .listenUserPresence(widget.otherUserId)
          .listen((presence) {
        if (mounted) {
          setState(() {
            _remotePresence = presence;
          });
        }
      });
    } catch (e) {
      debugPrint('[ChatScreen] Presence setup note: $e');
    }

    try {
      // 4. Stream messages (automatically decrypted & merged with local Outbox)
      _msgSub?.cancel();
      _msgSub = MessagingFacade.instance
          .streamMessages(
        convId: _convId!,
        myUid: myUid,
        otherUid: widget.otherUserId,
      )
          .listen((msgs) {
        if (!mounted) return;
        setState(() {
          _messages = msgs;
          _connected = true;
        });
        _scrollToBottom();

        // 5. Mark conversation read
        MessagingFacade.instance.markConversationRead(
          convId: _convId!,
          myUid: myUid,
          messages: msgs,
        );
      }, onError: (e) {
        debugPrint('[ChatScreen] Message stream error: $e');
        if (mounted) setState(() => _connected = false);
      });

      // 6. Stream typing indicator
      _typingSub?.cancel();
      _typingSub = MessagingFacade.instance
          .streamTyping(convId: _convId!, otherUid: widget.otherUserId)
          .listen((isTyping) {
        if (mounted) setState(() => _otherTyping = isTyping);
      });

      // 7. Asynchronously ensure messaging subsystem and conversation record exist
      MessagingFacade.instance.initialize(myUid).catchError((e) {
        debugPrint('[ChatScreen] Initialize background note: $e');
      });
      MessagingFacade.instance.getOrCreateConversation(
        myUid: myUid,
        otherUid: widget.otherUserId,
        myName: auth.name,
        otherName: widget.workerName,
        jobId: widget.jobId,
        jobTitle: widget.jobTitle,
      ).catchError((e) {
        debugPrint('[ChatScreen] getOrCreateConversation background note: $e');
        return _convId!;
      });
    } catch (e) {
      debugPrint('[ChatScreen] _initChat error: $e');
    }
  }

  void _setReply(ChatMessage msg) {
    setState(() => _replyingTo = msg);
  }

  void _cancelReply() {
    setState(() => _replyingTo = null);
  }

  Future<void> _shareLocation() async {
    setState(() => _sharingLocation = true);
    try {
      final pos = await LocationService.getCurrentPosition();
      if (pos == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not get GPS location. Please check location permissions.'),
              backgroundColor: AppColors.red,
            ),
          );
        }
        return;
      }

      if (!mounted) return;
      final auth = context.read<AuthProvider>();
      final myUid = _myUid ?? auth.uid ?? FirebaseAuth.instance.currentUser?.uid;
      if (myUid == null || myUid.isEmpty) return;

      _convId ??= ConversationResolver.resolve(
        uid1: myUid,
        uid2: widget.otherUserId,
        jobId: widget.jobId,
      );

      final replyingMsg = _replyingTo;
      _cancelReply();

      await MessagingFacade.instance.sendMessage(
        myUid: myUid,
        otherUid: widget.otherUserId,
        convId: _convId!,
        text: '📍 Shared Location',
        type: 'location',
        replyToId: replyingMsg?.clientMessageId,
        replyToText: replyingMsg?.text,
        replyToSenderId: replyingMsg?.senderId,
        locationLat: pos.latitude,
        locationLng: pos.longitude,
      );

      _scrollToBottom();
    } catch (e) {
      debugPrint('[ChatScreen] Error sharing location: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to share location: $e'), backgroundColor: AppColors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _sharingLocation = false);
    }
  }

  Future<void> _sendMessage([String? text]) async {
    final msg = text ?? _msgCtrl.text.trim();
    if (msg.isEmpty) return;

    final auth = context.read<AuthProvider>();
    final myUid = _myUid ?? auth.uid ?? FirebaseAuth.instance.currentUser?.uid;
    if (myUid == null || myUid.isEmpty) {
      debugPrint('[ChatScreen] Cannot send: myUid is null');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please sign in to send messages.'), backgroundColor: AppColors.red),
        );
      }
      return;
    }

    if (widget.otherUserId.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invalid recipient.'), backgroundColor: AppColors.red),
        );
      }
      return;
    }

    // Ensure _convId is resolved immediately
    _convId ??= ConversationResolver.resolve(
      uid1: myUid,
      uid2: widget.otherUserId,
      jobId: widget.jobId,
    );

    final replyingMsg = _replyingTo;
    _cancelReply();

    debugPrint('[SEND_TAP] Sending message to ${widget.otherUserId} in $_convId');

    try {
      // Send message via Outbox (optimistic rendering immediate <10ms)
      await MessagingFacade.instance.sendMessage(
        myUid: myUid,
        otherUid: widget.otherUserId,
        convId: _convId!,
        text: msg,
        type: text != null ? 'voice' : 'text',
        replyToId: replyingMsg?.clientMessageId,
        replyToText: replyingMsg?.text,
        replyToSenderId: replyingMsg?.senderId,
      );

      // Phase 118: Clear composer only after local message/outbox creation succeeds
      if (text == null) {
        _msgCtrl.clear();
        _onTypingChanged('');
      }
      debugPrint('[SEND_LOCAL_CREATED] Queued in outbox successfully');
    } catch (e) {
      debugPrint('[SEND_ERROR] Failed to queue message: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to queue message: $e'), backgroundColor: AppColors.red),
        );
      }
      // Retain draft in _msgCtrl if local creation fails (Phase 80)
    }

    _scrollToBottom();
  }

  void _onTypingChanged(String val) {
    final auth = context.read<AuthProvider>();
    final myUid = auth.uid;
    if (_convId == null || myUid == null) return;
    MessagingFacade.instance.setTyping(
      convId: _convId!,
      myUid: myUid,
      isTyping: val.isNotEmpty,
    );
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _voiceInput() async {
    setState(() => _isListening = true);
    await _voice.initialize();
    await _voice.startListening(
      onResult: (text, isFinal) {
        if (isFinal && text.isNotEmpty) {
          setState(() => _isListening = false);
          _sendMessage(text);
        }
      },
      onListeningComplete: () => setState(() => _isListening = false),
    );
  }

  @override
  void dispose() {
    _msgSub?.cancel();
    _typingSub?.cancel();
    _presenceSub?.cancel();
    _bootstrapTimer?.cancel();
    _msgCtrl.dispose();
    _scrollCtrl.dispose();

    if (_convId != null && _myUid != null) {
      try {
        MessagingFacade.instance.setTyping(
          convId: _convId!,
          myUid: _myUid!,
          isTyping: false,
        );
      } catch (e) {
        debugPrint('[ChatScreen] Non-fatal typing cleanup error: $e');
      }
    }
    super.dispose();
  }

  Widget _buildPresenceSubtitle() {
    if (_otherTyping) {
      return Text(
        'typing...',
        style: GoogleFonts.plusJakartaSans(
          fontSize: 10,
          color: AppColors.primary,
          fontWeight: FontWeight.w700,
          fontStyle: FontStyle.italic,
        ),
      );
    }

    // Transient connecting state for max 3 seconds during initial socket connect (Phase 5)
    final connStatus = MessagingConnectivityService.instance.status;
    final localConn = PresenceService.instance.localConnection;
    if (!_bootstrapDone &&
        (connStatus == MessagingConnectionStatus.bootstrapping ||
            localConn == LocalConnectionState.connecting)) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              color: AppColors.gold,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            'Connecting...',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 10,
              color: AppColors.gold,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      );
    }

    final isOnline = _remotePresence.state == RemotePresenceState.online;
    if (isOnline) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              color: AppColors.green,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            'Online',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 10,
              color: AppColors.green,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      );
    }

    // Remote user is offline
    String offlineLabel = 'Offline';
    if (_remotePresence.lastSeen != null) {
      offlineLabel = 'Last seen at ${_formatTime(_remotePresence.lastSeen!)}';
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: const BoxDecoration(
            color: AppColors.textFaint,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          offlineLabel,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 10,
            color: AppColors.textFaint,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final myId = auth.uid ?? '';

    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 1,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textHead),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            CircleAvatar(
              backgroundColor: AppColors.primaryPale,
              radius: 18,
              child: Text(
                widget.workerName.isNotEmpty ? widget.workerName[0].toUpperCase() : 'U',
                style: GoogleFonts.sora(fontSize: 15, fontWeight: FontWeight.w900, color: AppColors.primary),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.workerName,
                    style: GoogleFonts.sora(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.textHead),
                    overflow: TextOverflow.ellipsis,
                  ),
                  _buildPresenceSubtitle(),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.analytics_outlined, color: AppColors.textLight, size: 20),
            tooltip: 'Messaging Diagnostics',
            onPressed: () => _showDiagnosticPanel(context),
          ),
        ],
      ),
      body: Column(
        children: [
          // Job Context Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            color: AppColors.primaryPale,
            child: Row(
              children: [
                const Icon(Icons.work_outline_rounded, size: 14, color: AppColors.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Re: ${widget.jobTitle}',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (_connected)
                  const Icon(Icons.check_circle_outline_rounded, size: 13, color: AppColors.green),
              ],
            ),
          ),

          // Messages List
          Expanded(
            child: _messages.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 64,
                          height: 64,
                          decoration: const BoxDecoration(
                            color: AppColors.primaryPale,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.forum_outlined, size: 32, color: AppColors.primary),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Direct Marketplace Chat',
                          style: GoogleFonts.sora(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.textHead),
                        ),
                        const SizedBox(height: 4),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 32),
                          child: Text(
                            'Messages are securely delivered in real-time between you and ${widget.workerName}.',
                            style: GoogleFonts.plusJakartaSans(fontSize: 12, color: AppColors.textLight),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    controller: _scrollCtrl,
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
                    itemCount: _messages.length + (_otherTyping ? 1 : 0),
                    itemBuilder: (ctx, i) {
                      if (_otherTyping && i == _messages.length) return _typingBubble();
                      return _buildMsg(_messages[i], myId, i);
                    },
                  ),
          ),

          // Quick Replies
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
            child: Wrap(
              spacing: 8,
              runSpacing: 6,
              children: _quickReplies.map((reply) => GestureDetector(
                onTap: () {
                  _sendMessage(reply);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: AppColors.primaryPale,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.primaryBorder),
                  ),
                  child: Text(reply, style: GoogleFonts.notoSansKannada(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.primary)),
                ),
              )).toList(),
            ),
          ),

          // Reply Preview Banner
          if (_replyingTo != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              color: AppColors.surface2,
              child: Row(
                children: [
                  Container(
                    width: 3,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Replying to ${_replyingTo!.isMe(_myUid ?? '') ? 'You' : widget.workerName}',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary,
                          ),
                        ),
                        Text(
                          _replyingTo!.text,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.notoSansKannada(
                            fontSize: 12,
                            color: AppColors.textBody,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18, color: AppColors.textLight),
                    onPressed: _cancelReply,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),

          // Message Composer Input Bar
          Container(
            color: AppColors.surface,
            padding: EdgeInsets.fromLTRB(12, 8, 12, MediaQuery.of(context).viewInsets.bottom + 16),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.surface2,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(
                      children: [
                        const SizedBox(width: 14),
                        Expanded(
                          child: TextField(
                            controller: _msgCtrl,
                            maxLines: 3,
                            minLines: 1,
                            onChanged: _onTypingChanged,
                            decoration: InputDecoration(
                              hintText: 'ಸಂದೇಶ ಟೈಪ್ ಮಾಡಿ...',
                              border: InputBorder.none,
                              hintStyle: GoogleFonts.notoSansKannada(color: AppColors.textFaint, fontSize: 13),
                            ),
                            style: GoogleFonts.notoSansKannada(fontSize: 13, color: AppColors.textHead),
                            textInputAction: TextInputAction.send,
                            onSubmitted: (_) => _sendMessage(),
                          ),
                        ),
                        // Attachment button — B03 fix
                        GestureDetector(
                          onTap: () async {
                            HapticFeedback.lightImpact();
                            final picker = ImagePicker();
                            final XFile? image = await picker.pickImage(
                              source: ImageSource.gallery,
                              maxWidth: 1280,
                              maxHeight: 1280,
                              imageQuality: 80,
                            );
                            if (image != null && mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    '📎 ಫೋಟೋ ಆಯ್ಕೆ ಮಾಡಲಾಗಿದೆ / Photo selected: ${image.name}',
                                    style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
                                  ),
                                  backgroundColor: AppColors.green,
                                  behavior: SnackBarBehavior.floating,
                                  duration: const Duration(seconds: 2),
                                ),
                              );
                            }
                          },
                          child: Container(
                            width: 36,
                            height: 36,
                            margin: const EdgeInsets.only(right: 2),
                            decoration: const BoxDecoration(
                              color: Colors.transparent,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.attach_file_rounded, color: AppColors.textLight, size: 20),
                          ),
                        ),
                        // Share Location button
                        GestureDetector(
                          onTap: _sharingLocation ? null : _shareLocation,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            width: 36,
                            height: 36,
                            margin: const EdgeInsets.only(right: 2),
                            decoration: BoxDecoration(
                              color: _sharingLocation ? AppColors.primaryPale : Colors.transparent,
                              shape: BoxShape.circle,
                            ),
                            child: _sharingLocation
                                ? const Center(child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary)))
                                : const Icon(Icons.location_on_outlined, color: AppColors.textLight, size: 20),
                          ),
                        ),
                        // Voice input button
                        GestureDetector(
                          onTap: _isListening ? null : _voiceInput,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            width: 36,
                            height: 36,
                            margin: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: _isListening ? AppColors.red : AppColors.primaryPale,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              _isListening ? Icons.stop : Icons.mic,
                              color: _isListening ? Colors.white : AppColors.primary,
                              size: 18,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () {
                    if (_msgCtrl.text.trim().isNotEmpty) _sendMessage();
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      gradient: _msgCtrl.text.trim().isNotEmpty
                          ? const LinearGradient(colors: [AppColors.primary, Color(0xFFFF6B35)])
                          : const LinearGradient(colors: [AppColors.border, AppColors.border]),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMsg(ChatMessage msg, String myId, int i) {
    final isMe = msg.isMe(myId);
    final text = msg.plaintext;
    final isVoice = msg.isVoice;
    final isLocation = msg.isLocation;
    final isError = text.startsWith('[Decryption Error');

    return GestureDetector(
      onLongPress: () => _setReply(msg),
      child: Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: isMe ? AppColors.primary : AppColors.surface,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(18),
              topRight: const Radius.circular(18),
              bottomLeft: isMe ? const Radius.circular(18) : const Radius.circular(4),
              bottomRight: isMe ? const Radius.circular(4) : const Radius.circular(18),
            ),
            border: isMe ? null : Border.all(color: isError ? AppColors.red : AppColors.border),
            boxShadow: [BoxShadow(color: Colors.black.withAlpha(10), blurRadius: 6)],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Quoted reply header inside message
              if (msg.hasReply)
                Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
                  decoration: BoxDecoration(
                    color: isMe ? Colors.white.withAlpha(46) : AppColors.surface2,
                    borderRadius: BorderRadius.circular(8),
                    border: Border(
                      left: BorderSide(
                        color: isMe ? Colors.white70 : AppColors.primary,
                        width: 3,
                      ),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        msg.replyToSenderId == myId ? 'You' : widget.workerName,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: isMe ? Colors.white : AppColors.primary,
                        ),
                      ),
                      Text(
                        msg.replyToText ?? '',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.notoSansKannada(
                          fontSize: 11,
                          color: isMe ? Colors.white70 : AppColors.textBody,
                        ),
                      ),
                    ],
                  ),
                ),

              // Voice indicator
              if (isVoice)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.mic, size: 14, color: isMe ? Colors.white70 : AppColors.primary),
                      const SizedBox(width: 4),
                      Text(
                        'Voice message',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: isMe ? Colors.white70 : AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                ),

              // Location card
              if (isLocation)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.location_on_rounded, size: 16, color: isMe ? Colors.white : AppColors.primary),
                          const SizedBox(width: 4),
                          Text(
                            'Shared Location',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: isMe ? Colors.white : AppColors.textHead,
                            ),
                          ),
                        ],
                      ),
                      if (msg.locationLat != null && msg.locationLng != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          '${msg.locationLat!.toStringAsFixed(4)}°, ${msg.locationLng!.toStringAsFixed(4)}°',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 10,
                            color: isMe ? Colors.white70 : AppColors.textLight,
                          ),
                        ),
                        const SizedBox(height: 6),
                        InkWell(
                          onTap: () async {
                            final uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=${msg.locationLat},${msg.locationLng}');
                            try {
                              await launchUrl(uri, mode: LaunchMode.externalApplication);
                            } catch (_) {}
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: isMe ? Colors.white : AppColors.primary,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.navigation_rounded, size: 12, color: isMe ? AppColors.primary : Colors.white),
                                const SizedBox(width: 4),
                                Text(
                                  'Open in Maps',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    color: isMe ? AppColors.primary : Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

              // Standard text display (hidden or secondary if pure location message)
              if (!isLocation || (text != '📍 Shared Location' && text.isNotEmpty))
                Text(
                  text,
                  style: GoogleFonts.notoSansKannada(
                    fontSize: 13,
                    color: isError
                        ? AppColors.red
                        : (isMe ? Colors.white : AppColors.textHead),
                    fontWeight: isError ? FontWeight.w700 : FontWeight.w600,
                  ),
                ),

              const SizedBox(height: 3),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _formatTime(msg.sentAt),
                    style: TextStyle(fontSize: 9, color: isMe ? Colors.white70 : AppColors.textFaint),
                  ),
                  if (isMe) ...[
                    const SizedBox(width: 4),
                    _buildStatusTick(msg),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    ).animate(delay: Duration(milliseconds: i < 10 ? i * 20 : 0)).slideY(begin: 0.1, duration: 150.ms).fadeIn();
  }

  /// WhatsApp-style ticks
  Widget _buildStatusTick(ChatMessage msg) {
    switch (msg.status) {
      case MessageStatus.queued:
      case MessageStatus.sending:
        return const SizedBox(
          width: 10,
          height: 10,
          child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.white70),
        );
      case MessageStatus.sent:
        // Single check (grey/white)
        return const Icon(Icons.check_rounded, size: 13, color: Colors.white70);
      case MessageStatus.delivered:
        // Double check (grey/white)
        return const Icon(Icons.done_all_rounded, size: 14, color: Colors.white70);
      case MessageStatus.read:
        // Double check (blue)
        return const Icon(Icons.done_all_rounded, size: 14, color: Color(0xFF64B5F6));
      case MessageStatus.failed:
        return GestureDetector(
          onTap: () => MessagingFacade.instance.retryMessage(msg.clientMessageId),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline_rounded, size: 13, color: Color(0xFFFF8A80)),
              SizedBox(width: 2),
              Text('Retry', style: TextStyle(fontSize: 9, color: Color(0xFFFF8A80), fontWeight: FontWeight.bold)),
            ],
          ),
        );
    }
  }

  Widget _typingBubble() {
    return const Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: EdgeInsets.only(bottom: 8),
        child: _TypingIndicator(),
      ),
    );
  }

  void _showDiagnosticPanel(BuildContext context) {
    final myUid = _myUid ?? FirebaseAuth.instance.currentUser?.uid ?? 'unknown';
    final transportStatus = MessagingConnectivityService.instance.status;
    final rtdbConn = PresenceService.instance.localConnection;
    final queued = MessagingOutboxService.instance.queuedCount;
    final failed = MessagingOutboxService.instance.failedCount;

    if (!context.mounted) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.analytics_outlined, color: AppColors.primary),
                const SizedBox(width: 8),
                Text('Messaging Telemetry & Diagnostics',
                    style: GoogleFonts.sora(fontSize: 15, fontWeight: FontWeight.bold)),
              ],
            ),
            const Divider(height: 20),
            _diagRow('Auth Status', myUid != 'unknown' ? 'AUTHENTICATED' : 'UNAUTHENTICATED'),
            _diagRow('Local Transport', transportStatus.name.toUpperCase()),
            _diagRow('RTDB Presence Socket', rtdbConn.name.toUpperCase()),
            _diagRow('Remote User State', _remotePresence.state.name.toUpperCase()),
            _diagRow('Remote Last Seen', _remotePresence.lastSeen != null ? _formatTime(_remotePresence.lastSeen!) : 'None'),
            _diagRow('Outbox Queue', '$queued active / $failed failed'),
            _diagRow('Conversation ID', _convId ?? 'Unresolved'),
            const SizedBox(height: 12),
            Text(
              'Firebase-native real-time messaging with Firestore rules authorization.',
              style: GoogleFonts.plusJakartaSans(fontSize: 11, color: AppColors.textFaint, fontStyle: FontStyle.italic),
            ),
          ],
        ),
      ),
    );
  }

  Widget _diagRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: GoogleFonts.plusJakartaSans(fontSize: 11, color: AppColors.textLight, fontWeight: FontWeight.w600)),
          Text(value, style: GoogleFonts.plusJakartaSans(fontSize: 11, color: AppColors.textHead, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  String _formatTime(DateTime dt) {
    return '${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
  }
}

// ── Typing Indicator (3-dot bounce animation) ────────────────────────────────
class _TypingIndicator extends StatelessWidget {
  const _TypingIndicator();
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(16),
          topRight: Radius.circular(16),
          bottomRight: Radius.circular(16),
        ),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(3, (i) =>
          Container(
            width: 7, height: 7,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: const BoxDecoration(
              color: AppColors.textLight,
              shape: BoxShape.circle,
            ),
          )
          .animate(onPlay: (c) => c.repeat())
          .moveY(
            begin: 0, end: -4,
            delay: Duration(milliseconds: i * 150),
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeInOut,
          )
          .then()
          .moveY(
            begin: -4, end: 0,
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeInOut,
          ),
        ),
      ),
    );
  }
}
