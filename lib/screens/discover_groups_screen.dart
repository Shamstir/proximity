import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../utils/constants.dart';
import '../models/group.dart';
import '../services/mesh_service.dart';
import 'chat_screen.dart';

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

  Future<void> _joinGroup(Group group) async {
    setState(() => _isJoining = true);
    
    if (group.isEncrypted) {
      final nfc = _meshService.nfcService;
      final nfcAvailable = await nfc.isAvailable();
      
      if (nfcAvailable && mounted) {
        final nfcResult = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => _NfcJoinerDialog(
            meshService: _meshService,
            groupName: group.name,
          ),
        );
        
        if (nfcResult == true) {
        }
      }
    }
    
    if (!mounted) return;
    
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
          ),
        ),
      );
    } else {
      setState(() => _isJoining = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Failed to join group. Please try again.'),
          backgroundColor: Colors.red.shade800,
        ),
      );
    }
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
          icon: const Icon(Icons.arrow_back_ios_new, 
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
                SizedBox(
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
            child: _groups.isEmpty
              ? _buildEmptyState()
              : _buildGroupsList(),
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
      separatorBuilder: (_, __) => Divider(
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
        onTap: _isJoining ? null : () => _joinGroup(group),
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
                          group.isEncrypted ? Icons.lock_rounded : Icons.lock_open_rounded,
                          size: 10,
                          color: group.isEncrypted ? AppColors.primary : AppColors.secondary,
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
    super.dispose();
  }
}

class _NfcJoinerDialog extends StatefulWidget {
  final MeshService meshService;
  final String groupName;

  const _NfcJoinerDialog({
    required this.meshService,
    required this.groupName,
  });

  @override
  State<_NfcJoinerDialog> createState() => _NfcJoinerDialogState();
}

class _NfcJoinerDialogState extends State<_NfcJoinerDialog>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  String _status = "Ready to receive keys";
  bool _isExchanging = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _startJoinerExchange();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    widget.meshService.nfcService.stopSession();
    super.dispose();
  }

  Future<void> _startJoinerExchange() async {
    setState(() {
      _isExchanging = true;
      _status = "Tap the host's phone...";
    });

    try {
      await widget.meshService.pauseNearbyForNfc();

      var pubKey = await widget.meshService.getMyPublicKeyBase64();
      if (pubKey == null) {
        await widget.meshService.initEncryption();
        pubKey = await widget.meshService.getMyPublicKeyBase64();
      }
      
      if (pubKey == null) {
        setState(() {
          _status = "Failed to initialize keys";
          _isExchanging = false;
        });
        return;
      }

      final nfc = widget.meshService.nfcService;
      
      if (!mounted) return;
      setState(() => _status = "Reading host's keys...");
      
      final hostData = await nfc.joinerExchange(
        joinerPublicKey: pubKey,
      );

      if (!mounted) return;

      if (hostData != null) {
        setState(() => _status = "Got host's keys! Setting up...");
        
        await widget.meshService.initEncryptionAsJoiner(
          hostData['treeState']!,
          widget.meshService.uniqueId,
        );
        
        setState(() => _status = "Sharing your key back...");
        
        await Future.delayed(const Duration(seconds: 5));
        
        await nfc.stopEmitting();
        
        if (mounted) {
          setState(() => _status = "Keys exchanged! ✓");
          await Future.delayed(const Duration(milliseconds: 500));
          if (mounted) Navigator.of(context).pop(true);
        }
      } else {
        setState(() {
          _status = "Could not read host's keys. Retry?";
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
                      color: AppColors.primary.withValues(alpha: 0.1),
                      border: Border.all(
                        color: AppColors.primary.withValues(
                          alpha: 0.3 + (_pulseController.value * 0.3),
                        ),
                        width: 2,
                      ),
                    ),
                    child: const Icon(
                      Icons.nfc_rounded,
                      color: AppColors.primary,
                      size: 36,
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 24),
            Text(
              "RECEIVE KEYS",
              style: TextStyle(
                color: AppColors.primary,
                fontSize: 16,
                fontWeight: FontWeight.w600,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "tap the host's phone to get encryption keys",
              style: TextStyle(
                color: AppColors.secondary,
                fontSize: 12,
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
                style: TextStyle(
                  color: AppColors.accent,
                  fontSize: 11,
                  fontFamily: 'monospace',
                ),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text(
                    "SKIP",
                    style: TextStyle(
                      color: AppColors.secondary,
                      letterSpacing: 1,
                    ),
                  ),
                ),
                if (!_isExchanging)
                  TextButton(
                    onPressed: _startJoinerExchange,
                    child: Text(
                      "RETRY",
                      style: TextStyle(
                        color: AppColors.primary,
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
