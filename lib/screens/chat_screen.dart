import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../utils/constants.dart';
import '../models/chat_message.dart';
import '../models/group.dart';
import '../services/mesh_service.dart';

class ChatScreen extends StatefulWidget {
  final bool isHost;
  final String userName;
  final Group? group;
  
  const ChatScreen({
    super.key,
    required this.isHost,
    required this.userName,
    this.group,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with TickerProviderStateMixin {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  final List<ChatMessage> _messages = [];
  final List<AnimationController> _messageAnimControllers = [];
  
  late MeshService _meshService;
  StreamSubscription? _messageSubscription;
  StreamSubscription? _statusSubscription;
  StreamSubscription? _leaderSubscription;
  
  String _connectionStatus = "Connecting...";
  int _peerCount = 0;
  bool _isLeader = false;
  bool _isSendHeld = false;

  TextStyle get _chatFont => GoogleFonts.jetBrainsMono(
    fontSize: 13,
    fontWeight: FontWeight.w400,
    height: 1.6,
  );

  TextStyle get _chatFontSmall => GoogleFonts.jetBrainsMono(
    fontSize: 10,
    fontWeight: FontWeight.w400,
    height: 1.4,
  );

  @override
  void initState() {
    super.initState();
    
    _meshService = Provider.of<MeshService>(context, listen: false);
    _isLeader = widget.isHost;
    
    _messageSubscription = _meshService.messageStream.listen((meshMessage) {
      _addMessage(ChatMessage(
        id: meshMessage.id,
        text: meshMessage.text,
        type: MessageType.received,
        timestamp: meshMessage.timestamp,
        senderName: meshMessage.senderName,
      ));
    });
    
    _statusSubscription = _meshService.statusStream.listen((status) {
      setState(() {
        _connectionStatus = status;
        _peerCount = _meshService.peerCount;
      });
      
      if (status.contains("leader") || status.contains("Leader")) {
        _addSystemMessage(status);
      }
    });
    
    _meshService.peersStream.listen((_) {
      setState(() {
        _peerCount = _meshService.peerCount;
      });
    });
    
    _leaderSubscription = _meshService.leaderChangeStream.listen((isNowLeader) {
      setState(() {
        _isLeader = isNowLeader;
      });
      
      if (isNowLeader) {
        _addSystemMessage("You are now the group leader");
      } else {
        _addSystemMessage("Group ended — all members left");
      }
    });
    
    final groupName = widget.group?.name ?? "Mesh";
    _addMessage(ChatMessage(
      id: "system_welcome",
      text: widget.isHost 
          ? "You created \"$groupName\"\nWaiting for others to join..."
          : "You joined \"$groupName\"\nSay hello!",
      type: MessageType.received,
      timestamp: DateTime.now(),
      senderName: "System",
    ));
  }

  void _addMessage(ChatMessage message) {
    final controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    
    setState(() {
      _messages.add(message);
      _messageAnimControllers.add(controller);
    });
    
    controller.forward();
    _scrollToBottom();
  }

  void _addSystemMessage(String text) {
    _addMessage(ChatMessage(
      id: "system_${DateTime.now().millisecondsSinceEpoch}",
      text: text,
      type: MessageType.received,
      timestamp: DateTime.now(),
      senderName: "System",
    ));
  }

  void _sendMessage() {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    HapticFeedback.lightImpact();

    final message = ChatMessage(
      id: "${_meshService.uniqueId}_${DateTime.now().millisecondsSinceEpoch}",
      text: text,
      type: MessageType.sent,
      timestamp: DateTime.now(),
      senderName: widget.userName,
    );

    _addMessage(message);
    _meshService.sendMessage(text);
    _textController.clear();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _handleLeave() {
    _meshService.leaveGroup();
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final groupName = widget.group?.name ?? (_isLeader ? "HOSTING" : "CONNECTED");
    final groupAgenda = widget.group?.agenda;
    
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: _buildAppBar(groupName, groupAgenda),
      body: Column(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => _focusNode.unfocus(),
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                itemCount: _messages.length,
                itemBuilder: (context, index) {
                  return _buildAnimatedMessage(index);
                },
              ),
            ),
          ),
          _buildInputArea(),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(String groupName, String? groupAgenda) {
    return AppBar(
      backgroundColor: AppColors.background,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new, 
          color: AppColors.primary, 
          size: 16,
        ),
        onPressed: _handleLeave,
      ),
      centerTitle: false,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Flexible(
                child: Text(
                  groupName.toUpperCase(),
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                    letterSpacing: 1.5,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (_isLeader) ...[
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.3),
                      width: 0.5,
                    ),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    "HOST",
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 8,
                      fontWeight: FontWeight.w500,
                      color: AppColors.accent,
                      letterSpacing: 1,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 3),
          Row(
            children: [
              TweenAnimationBuilder<double>(
                tween: Tween(end: _peerCount > 0 ? 1.0 : 0.3),
                duration: const Duration(milliseconds: 500),
                builder: (context, opacity, child) {
                  return Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _peerCount > 0
                          ? const Color(0xFF4ADE80).withValues(alpha: opacity)
                          : AppColors.secondary.withValues(alpha: opacity),
                      boxShadow: _peerCount > 0
                          ? [BoxShadow(
                              color: const Color(0xFF4ADE80).withValues(alpha: 0.4),
                              blurRadius: 4,
                              spreadRadius: 1,
                            )]
                          : null,
                    ),
                  );
                },
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  groupAgenda != null && groupAgenda.isNotEmpty
                    ? groupAgenda
                    : "$_peerCount peers · ${_connectionStatus.toLowerCase()}",
                  style: _chatFontSmall.copyWith(
                    color: AppColors.secondary,
                    letterSpacing: 0.5,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
      actions: [
        if (_isLeader && (widget.group?.isEncrypted ?? true))
          IconButton(
            icon: const Icon(
              Icons.nfc_rounded,
              color: AppColors.accent,
              size: 18,
            ),
            tooltip: 'Add member via NFC',
            onPressed: _startNfcHostExchange,
          ),
        Center(
          child: Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.divider,
                  width: 0.5,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.people_outline_rounded,
                    size: 12,
                    color: AppColors.secondary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    "$_peerCount",
                    style: _chatFontSmall.copyWith(
                      color: AppColors.accent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(
          height: 0.5,
          color: AppColors.divider,
        ),
      ),
    );
  }

  Widget _buildAnimatedMessage(int index) {
    final message = _messages[index];
    final controller = _messageAnimControllers[index];
    final isMe = message.type == MessageType.sent;
    
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        final slideOffset = (1.0 - Curves.easeOutCubic.transform(controller.value));
        final opacity = Curves.easeOut.transform(controller.value);
        
        return Transform.translate(
          offset: Offset(
            isMe ? slideOffset * 30 : -slideOffset * 30,
            slideOffset * 10,
          ),
          child: Opacity(
            opacity: opacity,
            child: child,
          ),
        );
      },
      child: _buildMessageBubble(message),
    );
  }

  Widget _buildMessageBubble(ChatMessage message) {
    final isMe = message.type == MessageType.sent;
    final isSystem = message.senderName == "System";
    
    if (isSystem) {
      return _buildSystemMessage(message);
    }
    
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (!isMe)
            Padding(
              padding: const EdgeInsets.only(left: 2, bottom: 5),
              child: Text(
                message.senderName ?? "Unknown",
                style: _chatFontSmall.copyWith(
                  color: AppColors.accent.withValues(alpha: 0.7),
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.8,
                ),
              ),
            ),
          Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.72,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isMe ? AppColors.primary : AppColors.card,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(14),
                topRight: const Radius.circular(14),
                bottomLeft: Radius.circular(isMe ? 14 : 3),
                bottomRight: Radius.circular(isMe ? 3 : 14),
              ),
              border: isMe 
                  ? null 
                  : Border.all(color: AppColors.divider, width: 0.5),
            ),
            child: Text(
              message.text,
              style: _chatFont.copyWith(
                color: isMe ? AppColors.background : AppColors.primary,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              message.formattedTime,
              style: _chatFontSmall.copyWith(
                fontSize: 9,
                color: AppColors.secondary.withValues(alpha: 0.5),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSystemMessage(ChatMessage message) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: AppColors.divider.withValues(alpha: 0.5),
              width: 0.5,
            ),
          ),
          child: Text(
            message.text,
            style: _chatFontSmall.copyWith(
              color: AppColors.secondary,
              fontStyle: FontStyle.italic,
              letterSpacing: 0.3,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }

  Widget _buildInputArea() {
    return Container(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 14,
        bottom: MediaQuery.of(context).viewInsets.bottom > 0 ? 14 : 30,
      ),
      decoration: BoxDecoration(
        color: AppColors.background,
        border: Border(
          top: BorderSide(color: AppColors.divider, width: 0.5),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: AppColors.divider,
                  width: 0.5,
                ),
              ),
              child: TextField(
                controller: _textController,
                focusNode: _focusNode,
                style: _chatFont.copyWith(
                  color: AppColors.primary,
                  fontSize: 13,
                ),
                cursorColor: AppColors.primary,
                cursorWidth: 1,
                maxLines: 4,
                minLines: 1,
                decoration: InputDecoration(
                  hintText: "say something...",
                  hintStyle: _chatFont.copyWith(
                    color: AppColors.secondary.withValues(alpha: 0.4),
                    fontSize: 13,
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 18, 
                    vertical: 12,
                  ),
                ),
                onSubmitted: (_) => _sendMessage(),
              ),
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTapDown: (_) => setState(() => _isSendHeld = true),
            onTapUp: (_) {
              setState(() => _isSendHeld = false);
              _sendMessage();
            },
            onTapCancel: () => setState(() => _isSendHeld = false),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 100),
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: _isSendHeld
                    ? AppColors.accent
                    : AppColors.primary,
                shape: BoxShape.circle,
              ),
              child: AnimatedRotation(
                turns: _isSendHeld ? 0.1 : 0.0,
                duration: const Duration(milliseconds: 100),
                child: const Icon(
                  Icons.arrow_upward_rounded,
                  color: AppColors.background,
                  size: 20,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _startNfcHostExchange() async {
    final nfc = _meshService.nfcService;
    final nfcAvailable = await nfc.isAvailable();
    
    if (!nfcAvailable) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('NFC not available on this device.'),
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }
    
    if (!mounted) return;
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _NfcHostDialog(
        meshService: _meshService,
        onComplete: (String? joinerPubKey) async {
          if (joinerPubKey != null) {
            _addSystemMessage("New member's key exchanged via NFC");
          }
        },
      ),
    );
  }

  @override
  void dispose() {
    _messageSubscription?.cancel();
    _statusSubscription?.cancel();
    _leaderSubscription?.cancel();
    _textController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    for (final c in _messageAnimControllers) {
      c.dispose();
    }
    super.dispose();
  }
}

class _NfcHostDialog extends StatefulWidget {
  final MeshService meshService;
  final Future<void> Function(String? joinerPubKey) onComplete;

  const _NfcHostDialog({
    required this.meshService,
    required this.onComplete,
  });

  @override
  State<_NfcHostDialog> createState() => _NfcHostDialogState();
}

class _NfcHostDialogState extends State<_NfcHostDialog>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  String _status = "Ready to share keys";
  bool _isExchanging = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _startHostExchange();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _startHostExchange() async {
    setState(() {
      _isExchanging = true;
      _status = "Emitting keys via NFC...";
    });

    try {
      await widget.meshService.pauseNearbyForNfc();

      final pubKey = await widget.meshService.getMyPublicKeyBase64();
      final treeState = await widget.meshService.getTreeStateJson();

      if (pubKey == null) {
        setState(() => _status = "Encryption not initialized");
        _isExchanging = false;
        return;
      }

      final nfc = widget.meshService.nfcService;
      
      await nfc.hostExchange(
        hostPublicKey: pubKey,
        treeStateJson: treeState,
      );
      
      if (!mounted) return;
      setState(() => _status = "Tap the joiner's phone now...");

      await Future.delayed(const Duration(seconds: 8));
      
      if (!mounted) return;
      setState(() => _status = "Reading joiner's key...");
      
      final joinerKey = await nfc.readJoinerKey();

      if (!mounted) return;

      if (joinerKey != null) {
        setState(() => _status = "Keys exchanged! ✓");
        await widget.onComplete(joinerKey);
        await Future.delayed(const Duration(milliseconds: 500));
        if (mounted) Navigator.of(context).pop();
      } else {
        setState(() {
          _status = "Could not read joiner's key. Retry?";
          _isExchanging = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _status = "Error: $e";
          _isExchanging = false;
        });
      }
    } finally {
      await widget.meshService.resumeNearbyAfterNfc();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedBuilder(
              animation: _pulseController,
              builder: (context, child) {
                return Transform.scale(
                  scale: 1.0 + (_pulseController.value * 0.15),
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.accent.withValues(alpha: 0.1),
                      border: Border.all(
                        color: AppColors.accent.withValues(
                          alpha: 0.3 + (_pulseController.value * 0.3),
                        ),
                        width: 2,
                      ),
                    ),
                    child: const Icon(
                      Icons.nfc_rounded,
                      color: AppColors.accent,
                      size: 36,
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 24),
            Text(
              "SHARE KEYS",
              style: GoogleFonts.jetBrainsMono(
                color: AppColors.primary,
                fontSize: 16,
                fontWeight: FontWeight.w600,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "tap joiner's phone to share encryption keys",
              style: GoogleFonts.jetBrainsMono(
                color: AppColors.secondary,
                fontSize: 10,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _status,
                style: GoogleFonts.jetBrainsMono(
                  color: AppColors.accent,
                  fontSize: 11,
                ),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(
                    "CANCEL",
                    style: GoogleFonts.jetBrainsMono(
                      color: AppColors.secondary,
                      fontSize: 12,
                      letterSpacing: 1,
                    ),
                  ),
                ),
                if (!_isExchanging)
                  TextButton(
                    onPressed: _startHostExchange,
                    child: Text(
                      "RETRY",
                      style: GoogleFonts.jetBrainsMono(
                        color: AppColors.primary,
                        fontSize: 12,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
