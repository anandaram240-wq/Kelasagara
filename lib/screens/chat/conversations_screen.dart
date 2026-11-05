// lib/screens/chat/conversations_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../providers/auth_provider.dart';
import '../../services/messaging/presence_service.dart';
import 'chat_screen.dart';

/// WhatsApp-style conversation list displaying active chats,
/// unread badges, job context, and real-time presence.
class ConversationsScreen extends StatelessWidget {
  final Stream<QuerySnapshot<Map<String, dynamic>>>? customStream;
  const ConversationsScreen({super.key, this.customStream});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final myUid = auth.uid;

    if (myUid == null || myUid.isEmpty) {
      return Scaffold(
        backgroundColor: AppColors.bg,
        appBar: AppBar(
          title: Text('Messages', style: GoogleFonts.sora(fontWeight: FontWeight.w800, color: AppColors.textHead)),
          backgroundColor: AppColors.surface,
          elevation: 1,
        ),
        body: Center(
          child: Text(
            'Please sign in to view your messages.',
            style: GoogleFonts.plusJakartaSans(color: AppColors.textLight),
          ),
        ),
      );
    }

    Stream<QuerySnapshot<Map<String, dynamic>>> convStream;
    if (customStream != null) {
      convStream = customStream!;
    } else {
      try {
        convStream = FirebaseFirestore.instance
            .collection('conversations')
            .where('participants', arrayContains: myUid)
            .snapshots();
      } catch (_) {
        convStream = const Stream.empty();
      }
    }

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Messages', style: GoogleFonts.sora(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.textHead)),
            Text('ಸಂದೇಶಗಳು', style: GoogleFonts.notoSansKannada(fontSize: 11, color: AppColors.textLight, fontWeight: FontWeight.w600)),
          ],
        ),
        backgroundColor: AppColors.surface,
        elevation: 1,
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: convStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: AppColors.primary));
          }

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.cloud_off_rounded, size: 48, color: AppColors.textFaint),
                    const SizedBox(height: 12),
                    Text(
                      'Could not load conversations',
                      style: GoogleFonts.sora(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textHead),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${snapshot.error}',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.plusJakartaSans(fontSize: 12, color: AppColors.textLight),
                    ),
                  ],
                ),
              ),
            );
          }

          final rawDocs = snapshot.data?.docs ?? [];
          final docs = [...rawDocs];
          docs.sort((a, b) {
            final aTime = (a.data()['lastMessageAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
            final bTime = (b.data()['lastMessageAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
            return bTime.compareTo(aTime);
          });
          if (docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: const BoxDecoration(
                      color: AppColors.primaryPale,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.chat_bubble_outline_rounded, size: 36, color: AppColors.primary),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No conversations yet',
                    style: GoogleFonts.sora(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textHead),
                  ),
                  const SizedBox(height: 6),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 40),
                    child: Text(
                      'Conversations will appear here when you chat with workers or hirers.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.plusJakartaSans(fontSize: 13, color: AppColors.textLight),
                    ),
                  ),
                ],
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const Divider(height: 1, indent: 76, color: AppColors.divider),
            itemBuilder: (context, index) {
              final doc = docs[index];
              final data = doc.data();

              final participants = List<String>.from(data['participants'] ?? []);
              final otherUid = participants.firstWhere((p) => p != myUid, orElse: () => '');
              final names = (data['participantNames'] as Map<String, dynamic>?) ?? {};
              final otherName = names[otherUid] as String? ?? 'User';
              final jobTitle = data['jobTitle'] as String? ?? 'Direct Chat';
              final jobId = data['jobId'] as String?;
              final lastMsg = data['lastMessage'] as String? ?? '';
              final unreadMap = (data['unreadCount'] as Map<String, dynamic>?) ?? {};
              final unread = (unreadMap[myUid] as num?)?.toInt() ?? 0;

              DateTime? lastAt;
              final rawLastAt = data['lastMessageAt'] ?? data['updatedAt'];
              if (rawLastAt is Timestamp) {
                lastAt = rawLastAt.toDate();
              } else if (rawLastAt is String) {
                lastAt = DateTime.tryParse(rawLastAt);
              }

              return _ConversationTile(
                myUid: myUid,
                otherUid: otherUid,
                otherName: otherName,
                jobTitle: jobTitle,
                jobId: jobId,
                lastMessage: lastMsg,
                lastMessageAt: lastAt,
                unreadCount: unread,
              );
            },
          );
        },
      ),
    );
  }
}

class _ConversationTile extends StatelessWidget {
  final String myUid;
  final String otherUid;
  final String otherName;
  final String jobTitle;
  final String? jobId;
  final String lastMessage;
  final DateTime? lastMessageAt;
  final int unreadCount;

  const _ConversationTile({
    required this.myUid,
    required this.otherUid,
    required this.otherName,
    required this.jobTitle,
    this.jobId,
    required this.lastMessage,
    this.lastMessageAt,
    required this.unreadCount,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ChatScreen(
              workerName: otherName,
              jobTitle: jobTitle,
              otherUserId: otherUid,
              jobId: jobId,
            ),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            // Avatar with live presence indicator
            Stack(
              clipBehavior: Clip.none,
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: AppColors.primaryPale,
                  child: Text(
                    otherName.isNotEmpty ? otherName[0].toUpperCase() : 'U',
                    style: GoogleFonts.sora(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.primary),
                  ),
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: StreamBuilder<RemotePresence>(
                    stream: PresenceService.instance.listenUserPresence(otherUid),
                    builder: (context, snapshot) {
                      final isOnline = snapshot.data?.state == RemotePresenceState.online;
                      if (!isOnline) return const SizedBox.shrink();
                      return Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: AppColors.green,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(width: 12),

            // Name, job badge & last message
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          otherName,
                          style: GoogleFonts.sora(
                            fontSize: 14,
                            fontWeight: unreadCount > 0 ? FontWeight.w800 : FontWeight.w700,
                            color: AppColors.textHead,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (lastMessageAt != null)
                        Text(
                          _formatTime(lastMessageAt!),
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 11,
                            fontWeight: unreadCount > 0 ? FontWeight.w700 : FontWeight.w500,
                            color: unreadCount > 0 ? AppColors.primary : AppColors.textLight,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),

                  // Job context badge
                  if (jobTitle.isNotEmpty && jobTitle != 'Direct Chat')
                    Container(
                      margin: const EdgeInsets.only(bottom: 2),
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: AppColors.primaryPale,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'Re: $jobTitle',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),

                  // Last message snippet + unread badge
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          lastMessage.isNotEmpty ? lastMessage : 'Start conversation',
                          style: GoogleFonts.notoSansKannada(
                            fontSize: 12,
                            color: unreadCount > 0 ? AppColors.textHead : AppColors.textLight,
                            fontWeight: unreadCount > 0 ? FontWeight.w700 : FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (unreadCount > 0)
                        Container(
                          margin: const EdgeInsets.only(left: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '$unreadCount',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);

    if (diff.inDays == 0 && dt.day == now.day) {
      return '${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
    } else if (diff.inDays < 7) {
      const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return weekdays[dt.weekday - 1];
    } else {
      return '${dt.day}/${dt.month}';
    }
  }
}
