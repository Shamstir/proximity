import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../utils/constants.dart';
import '../models/group.dart';
import '../services/mesh_service.dart';
import 'chat_screen.dart';
import 'fake_nfc_dialog.dart';

class DiscoverGroupsScreen extends StatefulWidget {
  final String userName;

  const DiscoverGroupsScreen({
    super.key,
    required this.userName,
  });

  @override
  State<DiscoverGroupsScreen> createState() => _DiscoverGroupsScreenState();
}

class _DiscoverGroupsScreenState extends State<DiscoverGroupsScreen> {
  late MeshService _meshService;
  StreamSubscription? _groupsSubscription;
  StreamSubscription? _statusSubscription;
  StreamSubscription? _keyReceivedSubscription;

  List<Group> _groups = [];
  String _status = "Searching...";
  bool _isJoining = false;

  @override
  void initState() {
    super.initState();

    _meshService = Provider.of<MeshService>(context, listen: false);

    _groupsSubscription = _meshService.discoveredGroupsStream.listen((groups) {
      if (mounted) {
        setState(() {
          _groups = groups;
        });
      }
    });

    _statusSubscription = _meshService.statusStream.listen((status) {
      if (mounted) {
        setState(() {
          _status = status;
        });
      }
    });

    _initAndDiscover();
  }

  Future<void> _initAndDiscover() async {
    await _meshService.stopMesh();
    _meshService.initialize(widget.userName);
    await _startDiscovery();
  }

  Future<void> _startDiscovery() async {
    await _meshService.startDiscovery();
  }

  // ── Join via Nearby — host will push the key automatically ──────────────────
  Future<void> _joinViaNearbly(Group group) async {
    setState(() => _isJoining = true);

    final keyCompleter = Completer<void>();
    _keyReceivedSubscription?.cancel();
    _keyReceivedSubscription = _meshService.keyReceivedStream.listen((_) {
      if (!keyCompleter.isCompleted) keyCompleter.complete();
    });

    final success = await _meshService.joinGroup(
      group,
      requestKeyOnConnect: true,
    );

    if (!mounted) return;

    if (!success) {
      setState(() => _isJoining = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Failed to connect. Please try again.'),
          backgroundColor: Colors.red.shade800,
        ),
      );
      return;
    }

    final animFuture = FakeNfcTransferDialog.show(context, isSender: false);
    bool keyReceived = false;
    try {
      await Future.wait([
        animFuture,
        keyCompleter.future.timeout(const Duration(seconds: 15)),
      ]);
      keyReceived = true;
    } catch (_) {
      await animFuture;
    }

    if (!mounted) return;

    if (!keyReceived) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Key was not received automatically. Joining as observer.',
          ),
          backgroundColor: Colors.amber.shade800,
        ),
      );
    }

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          isHost: false,
          userName: widget.userName,
          group: group,
          isObserver: !keyReceived,
        ),
      ),
    );
  }

  // ── Join by manually entering the key — observer mode ──────────────────────
  Future<void> _joinWithManualKey(Group group) async {
    final keyController = TextEditingController();

    final enteredKey = await showDialog<String>(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) => _ManualKeyDialog(controller: keyController),
    );

    if (!mounted) return;

    // Whether or not they entered a key, we join them as observer.
    // If they provided a valid key we apply it; otherwise observer sees cipher.
    setState(() => _isJoining = true);

    final success = await _meshService.joinGroup(
      group,
      requestKeyOnConnect: false,
    );

    if (!mounted) return;

    if (!success) {
      setState(() => _isJoining = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Failed to connect. Please try again.'),
          backgroundColor: Colors.red.shade800,
        ),
      );
      return;
    }

    // If they typed a key, try to apply it
    final trimmed = enteredKey?.trim() ?? '';
    bool hasValidKey = false;
    if (trimmed.isNotEmpty) {
      try {
        await _meshService.setGroupKeyFromBase64(trimmed);
        hasValidKey = true;
      } catch (_) {
        // Invalid key — still join but as pure observer
      }
    }

    if (!mounted) return;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          isHost: false,
          userName: widget.userName,
          group: group,
          // Observer mode: no key or invalid key → see encrypted text, can't send
          isObserver: !hasValidKey,
        ),
      ),
    );
  }

  // ── Show join-mode chooser bottom sheet ────────────────────────────────────
  Future<void> _showJoinOptions(Group group) async {
    if (_isJoining) return;

    if (!group.isEncrypted) {
      // Plain group — just join directly
      setState(() => _isJoining = true);
      final success = await _meshService.joinGroup(group);
      if (!mounted) return;
      if (success) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => ChatScreen(
              isHost: false,
              userName: widget.userName,
              group: group,
              isObserver: false,
            ),
          ),
        );
      } else {
        setState(() => _isJoining = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Failed to join. Please try again.'),
            backgroundColor: Colors.red.shade800,
          ),
        );
      }
      return;
    }

    // Show options for encrypted groups
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => _JoinOptionsSheet(
        group: group,
        onNearby: () {
          Navigator.pop(sheetCtx);
          _joinViaNearbly(group);
        },
        onManualKey: () {
          Navigator.pop(sheetCtx);
          _joinWithManualKey(group);
        },
      ),
    );
  }

  void _refresh() {
    setState(() {
      _groups = [];
      _status = "Refreshing...";
    });
    _meshService.refreshDiscovery();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new,
            color: AppColors.primary,
            size: 18,
          ),
          onPressed: () {
            _meshService.stopMesh();
            Navigator.pop(context);
          },
        ),
        title: Text(
          "JOIN GROUP",
          style: AppTextStyles.body.copyWith(
            fontWeight: FontWeight.w500,
            letterSpacing: 1,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: AppColors.primary, size: 20),
            onPressed: _refresh,
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
            height: 1,
            color: AppColors.divider,
          ),
        ),
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            color: AppColors.card,
            child: Row(
              children: [
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    color: AppColors.secondary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _status.toUpperCase(),
                    style: AppTextStyles.caption,
                  ),
                ),
                Text(
                  "${_groups.length} FOUND",
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.accent,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _groups.isEmpty ? _buildEmptyState() : _buildGroupsList(),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.divider, width: 1),
            ),
            child: const Icon(
              Icons.search,
              color: AppColors.secondary,
              size: 28,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            "SEARCHING FOR GROUPS",
            style: AppTextStyles.subHeading.copyWith(fontSize: 12),
          ),
          const SizedBox(height: 8),
          Text(
            "Make sure nearby devices are hosting",
            style: AppTextStyles.caption,
          ),
        ],
      ),
    );
  }

  Widget _buildGroupsList() {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _groups.length,
      separatorBuilder: (_, __) => const Divider(
        height: 1,
        color: AppColors.divider,
        indent: 20,
        endIndent: 20,
      ),
      itemBuilder: (context, index) {
        final group = _groups[index];
        return _buildGroupTile(group);
      },
    );
  }

  Widget _buildGroupTile(Group group) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _isJoining ? null : () => _showJoinOptions(group),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(2),
                ),
                child: Center(
                  child: Text(
                    group.name.isNotEmpty ? group.name[0].toUpperCase() : "?",
                    style: AppTextStyles.heading.copyWith(fontSize: 20),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      group.name,
                      style: AppTextStyles.body.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (group.agenda.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        group.agenda,
                        style: AppTextStyles.caption,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      "Hosted by ${group.hostName}",
                      style: AppTextStyles.caption.copyWith(
                        color: AppColors.accent,
                        fontSize: 10,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          group.isEncrypted
                              ? Icons.lock_rounded
                              : Icons.lock_open_rounded,
                          size: 10,
                          color: group.isEncrypted
                              ? AppColors.primary
                              : AppColors.secondary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          group.isEncrypted ? "encrypted" : "open",
                          style: AppTextStyles.caption.copyWith(
                            fontSize: 9,
                            color: group.isEncrypted
                                ? AppColors.primary.withValues(alpha: 0.7)
                                : AppColors.secondary.withValues(alpha: 0.7),
                          ),
                        ),
                        if (group.isEncrypted) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              border: Border.all(
                                  color: AppColors.divider, width: 0.5),
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Text(
                              "tap to choose join method",
                              style: AppTextStyles.caption.copyWith(
                                fontSize: 8,
                                color:
                                    AppColors.secondary.withValues(alpha: 0.6),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.arrow_forward_ios,
                color: AppColors.secondary,
                size: 14,
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _groupsSubscription?.cancel();
    _statusSubscription?.cancel();
    _keyReceivedSubscription?.cancel();
    super.dispose();
  }
}

// ── Join Options Bottom Sheet ───────────────────────────────────────────────────
class _JoinOptionsSheet extends StatelessWidget {
  final Group group;
  final VoidCallback onNearby;
  final VoidCallback onManualKey;

  const _JoinOptionsSheet({
    required this.group,
    required this.onNearby,
    required this.onManualKey,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.divider, width: 0.5),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 4),
            width: 36,
            height: 3,
            decoration: BoxDecoration(
              color: AppColors.divider,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'JOIN "${group.name.toUpperCase()}"',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Choose how you want to receive the encryption key',
                  style: AppTextStyles.caption,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _OptionTile(
            icon: Icons.wifi_tethering_rounded,
            iconColor: const Color(0xFF4ADE80),
            title: 'Nearby Key Transfer',
            subtitle:
                'Host sends the key automatically\nover Nearby Connection',
            badge: 'RECOMMENDED',
            badgeColor: const Color(0xFF4ADE80),
            onTap: onNearby,
          ),
          const Divider(
              height: 1, color: AppColors.divider, indent: 20, endIndent: 20),
          _OptionTile(
            icon: Icons.keyboard_rounded,
            iconColor: AppColors.secondary,
            title: 'Enter Key Manually',
            subtitle: 'Type the key yourself\nYou will join in Observer mode',
            badge: 'OBSERVER',
            badgeColor: Colors.amber,
            onTap: onManualKey,
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final String badge;
  final Color badgeColor;
  final VoidCallback onTap;

  const _OptionTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.badge,
    required this.badgeColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: iconColor.withValues(alpha: 0.3),
                    width: 0.5,
                  ),
                ),
                child: Icon(icon, color: iconColor, size: 22),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          title,
                          style: AppTextStyles.body.copyWith(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: badgeColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: badgeColor.withValues(alpha: 0.3),
                              width: 0.5,
                            ),
                          ),
                          child: Text(
                            badge,
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 7,
                              fontWeight: FontWeight.w600,
                              color: badgeColor,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: AppTextStyles.caption.copyWith(height: 1.5),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(
                Icons.arrow_forward_ios,
                size: 13,
                color: AppColors.secondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Manual Key Entry Dialog ─────────────────────────────────────────────────────
class _ManualKeyDialog extends StatelessWidget {
  final TextEditingController controller;

  const _ManualKeyDialog({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.keyboard_rounded,
                    color: Colors.amber, size: 18),
                const SizedBox(width: 10),
                Text(
                  'ENTER SECRET KEY',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                    letterSpacing: 1.5,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Paste the encryption key shared by the host.\nLeaving this blank joins you as a read-only observer.',
              style: AppTextStyles.caption.copyWith(height: 1.6),
            ),
            const SizedBox(height: 20),
            // Observer mode info banner
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Colors.amber.withValues(alpha: 0.3),
                  width: 0.5,
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.visibility_off_rounded,
                      size: 14, color: Colors.amber),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Observer mode: you will see encrypted\nciphertext and cannot send messages.',
                      style: AppTextStyles.caption.copyWith(
                        color: Colors.amber.withValues(alpha: 0.85),
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Container(
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.divider, width: 0.5),
              ),
              child: TextField(
                controller: controller,
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 11,
                  color: AppColors.primary,
                  height: 1.5,
                ),
                cursorColor: AppColors.primary,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: 'Paste Base64 key here...',
                  hintStyle: GoogleFonts.jetBrainsMono(
                    fontSize: 11,
                    color: AppColors.secondary.withValues(alpha: 0.4),
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.all(14),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.content_paste_rounded,
                        size: 16, color: AppColors.secondary),
                    onPressed: () async {
                      final data = await Clipboard.getData('text/plain');
                      if (data?.text != null) {
                        controller.text = data!.text!;
                      }
                    },
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(null),
                    child: Text(
                      'SKIP — OBSERVER',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 10,
                        color: AppColors.secondary,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: AppColors.background,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: () => Navigator.of(context).pop(controller.text),
                    child: Text(
                      'JOIN',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.5,
                      ),
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
