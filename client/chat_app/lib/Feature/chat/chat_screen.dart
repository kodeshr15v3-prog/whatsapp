import 'dart:async';
import 'dart:convert';
import 'package:chat_app/Provider/chat_provider.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:chat_app/Core/constant.dart';
import '../../core/storage.dart';
import 'package:web_socket_channel/html.dart';

class ChatScreen extends ConsumerStatefulWidget {
  final String chatId;
  final String name;
  const ChatScreen({super.key, required this.chatId, required this.name});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _msgCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final List<Map<String, dynamic>> _messages = [];

  WebSocketChannel? _channel;
  String? _myUserId;
  bool _loading = true;
  //for typingg
  String? _typingText; // "kavy is typing..."
  Timer? _typingTimer; // stops typing after 2 sec

  bool _isOnline = false;
  String _lastSeen = '';

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _myUserId = await AppStorage.getUserId();
    await _loadHistory();
    await _fetchStatus();
    _connectWebSocket(); // connect first
    await Future.delayed(
      // small delay so channel is ready
      const Duration(milliseconds: 300),
    );
    await _markAsRead();
  }

  Widget _buildTick(String status) {
    if (status == 'read') {
      return const Row(
        mainAxisSize: MainAxisSize.min,
        children: [Icon(Icons.done_all, size: 14, color: Colors.blue)],
      );
    } else if (status == 'delivered') {
      return const Row(
        mainAxisSize: MainAxisSize.min,
        children: [Icon(Icons.done_all, size: 14, color: Colors.white70)],
      );
    } else {
      return const Row(
        mainAxisSize: MainAxisSize.min,
        children: [Icon(Icons.done, size: 14, color: Colors.white70)],
      );
    }
  }

  Future<void> _markAsRead() async {
    try {
      final token = await AppStorage.getToken();
      final dio = Dio();
      await dio.post(
        '${AppConstants.baseUrl}/chats/${widget.chatId}/read',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );

      // mark all messages from other person as read locally
      setState(() {
        for (int i = 0; i < _messages.length; i++) {
          if (_messages[i]['sender_id'] != _myUserId) {
            _messages[i] = {..._messages[i], 'status': 'read'};
          }
        }
      });

      // send read ack via WebSocket to sender
      final otherMsgs = _messages
          .where((m) => m['sender_id'] != _myUserId)
          .toList();

      if (otherMsgs.isEmpty || _channel == null) return;

      final senderId = otherMsgs.first['sender_id'] as String;
      final msgIds = otherMsgs.map((m) => m['id'] as String).toList();

      _channel!.sink.add(
        jsonEncode({
          'event': 'read',
          'chat_id': widget.chatId,
          'msg_ids': msgIds,
          'sender_id': senderId,
        }),
      );
    } catch (_) {}
  }

  // ── load old messages ───────────────────────────────────────────
  Future<void> _loadHistory() async {
    try {
      final token = await AppStorage.getToken();
      final dio = Dio();
      final res = await dio.get(
        '${AppConstants.baseUrl}/messages/${widget.chatId}',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      final msgs = List<Map<String, dynamic>>.from(res.data);
      setState(() {
        _messages.addAll(msgs);
        _loading = false;
      });
      _scrollToBottom();
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  // ── connect websocket ───────────────────────────────────────────
  Future<void> _connectWebSocket() async {
    final token = await AppStorage.getToken();
    final uri = Uri.parse('${AppConstants.wsUrl}/ws/chat?token=$token');

    // use HtmlWebSocketChannel for Flutter Web
    _channel = HtmlWebSocketChannel.connect(uri);

    _channel!.stream.listen(
      (raw) {
        final msg = Map<String, dynamic>.from(jsonDecode(raw));
        final event = msg['event'] as String? ?? 'message';

        if (event == 'typing') {
          setState(() => _typingText = '${msg['user_name']} is typing...');
        } else if (event == 'stop_typing') {
          setState(() => _typingText = null);
        } else if (event == 'delivered') {
          // update message status to delivered
          final msgId = msg['msg_id'] as String;
          setState(() {
            final i = _messages.indexWhere((m) => m['id'] == msgId);
            if (i != -1)
              _messages[i] = {..._messages[i], 'status': 'delivered'};
          });
        } else if (event == 'read') {
          // update all mentioned messages to read
          final msgIds = List<String>.from(msg['msg_ids'] ?? []);
          setState(() {
            for (final id in msgIds) {
              final i = _messages.indexWhere((m) => m['id'] == id);
              if (i != -1) _messages[i] = {..._messages[i], 'status': 'read'};
            }
          });
        } else if (event == 'message') {
          setState(() => _messages.add(msg));
          _scrollToBottom();

          // send delivered ack back to sender
          if (msg['sender_id'] != _myUserId) {
            _channel?.sink.add(
              jsonEncode({
                'event': 'delivered',
                'chat_id': widget.chatId,
                'msg_id': msg['id'],
                'sender_id': msg['sender_id'],
              }),
            );
          }
        }
      },
      onError: (e) => print('[WS] error: $e'),
      onDone: () => print('[WS] disconnected'),
    );
  }

  // ── send message ────────────────────────────────────────────────
  void _send() {
    final content = _msgCtrl.text.trim();
    if (content.isEmpty || _channel == null) return;

    _channel!.sink.add(
      jsonEncode({
        'event': 'message',
        'chat_id': widget.chatId,
        'content': content,
      }),
    );
    _msgCtrl.clear();
    _markAsRead();
  }

  // ── scroll to bottom ────────────────────────────────────────────
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

  void _onTyping() {
    // send typing event
    _channel?.sink.add(
      jsonEncode({'event': 'typing', 'chat_id': widget.chatId}),
    );

    // cancel previous timer
    _typingTimer?.cancel();

    // stop typing after 2 seconds of no input
    _typingTimer = Timer(const Duration(seconds: 2), () {
      _channel?.sink.add(
        jsonEncode({'event': 'stop_typing', 'chat_id': widget.chatId}),
      );
    });
  }

  @override
  void dispose() {
    _typingTimer?.cancel();
    _channel?.sink.close();
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Widget _buildDateSeparator(String date) {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.grey.shade300,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          date,
          style: const TextStyle(fontSize: 11, color: Colors.black54),
        ),
      ),
    );
  }

  String _dateLabel(String isoString) {
    try {
      final dt = DateTime.parse(isoString).toLocal();
      final now = DateTime.now();
      if (dt.day == now.day && dt.month == now.month) return 'Today';
      final yesterday = now.subtract(const Duration(days: 1));
      if (dt.day == yesterday.day && dt.month == yesterday.month)
        return 'Yesterday';
      return '${dt.day}/${dt.month}/${dt.year}';
    } catch (_) {
      return '';
    }
  }

  Future<void> _fetchStatus() async {
    try {
      final token = await AppStorage.getToken();
      final dio = Dio();

      // get other person's user id from chat members
      final res = await dio.get(
        '${AppConstants.baseUrl}/chats/${widget.chatId}/member',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );

      final otherId = res.data['other_user_id'] as String;
      final status = await dio.get(
        '${AppConstants.baseUrl}/users/$otherId/status',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );

      setState(() {
        _isOnline = status.data['is_online'] as bool? ?? false;
        final ls = status.data['last_seen'] as String?;
        if (ls != null) {
          final dt = DateTime.parse(ls).toLocal();
          final h = dt.hour.toString().padLeft(2, '0');
          final m = dt.minute.toString().padLeft(2, '0');
          _lastSeen = 'last seen $h:$m';
        }
      });
    } catch (_) {}
  }

  String _formatTime(String isoString) {
    if (isoString.isEmpty) return '';
    try {
      final dt = DateTime.parse(isoString).toLocal();
      final h = dt.hour.toString().padLeft(2, '0');
      final m = dt.minute.toString().padLeft(2, '0');
      return '$h:$m';
    } catch (_) {
      return '';
    }
  }

  // ── build ───────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color.fromRGBO(236, 236, 236, 1),
      appBar: AppBar(
        backgroundColor: Colors.green.shade400,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () {
            ref.invalidate(myChatsProvider);
            context.go('/chats');
          },
        ),
        title: Row(
          children: [
            CircleAvatar(
              backgroundColor: Colors.white,
              radius: 18,
              child: Text(
                widget.name.isNotEmpty ? widget.name[0].toUpperCase() : '?',
                style: TextStyle(
                  color: Colors.green.shade400,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                Text(
                  _typingText != null
                      ? _typingText!
                      : _isOnline
                      ? 'Online'
                      : _lastSeen.isNotEmpty
                      ? _lastSeen
                      : '',
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                ),
              ],
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          // ── message list ───────────────────────────────────────
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _messages.isEmpty
                ? const Center(
                    child: Text(
                      'Say hello! 👋',
                      style: TextStyle(color: Colors.grey, fontSize: 16),
                    ),
                  )
                : ListView.builder(
                    controller: _scrollCtrl,
                    padding: const EdgeInsets.all(12),
                    itemCount: _messages.length,
                    itemBuilder: (_, i) {
                      final msg = _messages[i];

                      // show date separator when date changes
                      bool showDate = false;
                      if (i == 0) {
                        showDate = true;
                      } else {
                        final prev =
                            _messages[i - 1]['created_at'] as String? ?? '';
                        final curr = msg['created_at'] as String? ?? '';
                        if (prev.isNotEmpty && curr.isNotEmpty) {
                          final prevDt = DateTime.parse(prev).toLocal();
                          final currDt = DateTime.parse(curr).toLocal();
                          showDate = prevDt.day != currDt.day;
                        }
                      }

                      return Column(
                        children: [
                          if (showDate)
                            _buildDateSeparator(
                              _dateLabel(msg['created_at'] as String? ?? ''),
                            ),
                          _buildBubble(msg),
                        ],
                      );
                    },
                  ),
          ),

          // ── composer ───────────────────────────────────────────
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _msgCtrl,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(),
                    onChanged: (_) => _onTyping(),
                    decoration: InputDecoration(
                      hintText: 'Type a message...',
                      filled: true,
                      fillColor: const Color.fromRGBO(235, 235, 235, 1),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(30),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _send,
                  child: CircleAvatar(
                    backgroundColor: Colors.green.shade400,
                    radius: 24,
                    child: const Icon(
                      Icons.send,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── bubble widget ───────────────────────────────────────────────
  Widget _buildBubble(Map<String, dynamic> msg) {
    final isMe = msg['sender_id'] == _myUserId;
    final status = msg['status'] as String? ?? 'sent';

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.70,
        ),
        decoration: BoxDecoration(
          color: isMe ? Colors.green.shade400 : Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isMe ? 16 : 4),
            bottomRight: Radius.circular(isMe ? 4 : 16),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              msg['content'] ?? '',
              style: TextStyle(
                color: isMe ? Colors.white : Colors.black87,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _formatTime(msg['created_at'] ?? ''),
                  style: TextStyle(
                    fontSize: 10,
                    color: isMe ? Colors.white.withOpacity(0.7) : Colors.grey,
                  ),
                ),
                if (isMe) ...[const SizedBox(width: 4), _buildTick(status)],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
