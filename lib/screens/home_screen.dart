import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import '../utils/constants.dart';
import '../services/mesh_service.dart';
import 'chat_screen.dart';
import 'create_group_dialog.dart';
import 'discover_groups_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  bool _isProcessing = false;
  String _status = "READY";
  final TextEditingController _nameController = TextEditingController(text: "");
  bool _hapticEnabled = false;

  late AnimationController _gearAnimController;
  double _gearTargetAngle = 0.0;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  late AnimationController _createBtnController;
  late AnimationController _joinBtnController;

  int _prevNameLength = 0;

  @override
  void initState() {
    super.initState();

    _gearAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.15, end: 0.6).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _createBtnController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
      lowerBound: 0.0,
      upperBound: 1.0,
    );
    _joinBtnController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
      lowerBound: 0.0,
      upperBound: 1.0,
    );

    _nameController.addListener(_onNameChanged);
  }

  void _onNameChanged() {
    final newLen = _nameController.text.length;
    if (newLen == _prevNameLength) return;

    final delta = newLen - _prevNameLength;
    final angleDelta = delta * 15.0 * (math.pi / 180.0);
    _gearTargetAngle += angleDelta;
    _prevNameLength = newLen;

    if (_hapticEnabled) {
      HapticFeedback.vibrate();
    }

    _gearAnimController.forward(from: 0.0);
    setState(() {});
  }

  @override
  void dispose() {
    _gearAnimController.dispose();
    _pulseController.dispose();
    _createBtnController.dispose();
    _joinBtnController.dispose();
    _nameController.removeListener(_onNameChanged);
    _nameController.dispose();
    super.dispose();
  }

  Future<bool> _requestPermissions() async {
    setState(() => _status = "Requesting permissions...");

    Map<Permission, PermissionStatus> statuses = await [
      Permission.bluetooth,
      Permission.bluetoothAdvertise,
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
      Permission.location,
      Permission.nearbyWifiDevices,
    ].request();

    bool allGranted = statuses.values.every(
      (status) => status.isGranted || status.isLimited,
    );

    if (!allGranted) {
      setState(() => _status = "Permissions denied");
      return false;
    }

    return true;
  }

  Future<void> _handleCreateNetwork(BuildContext context) async {
    if (_nameController.text.trim().isEmpty) {
      setState(() => _status = "Enter a name first");
      return;
    }

    final groupInfo = await CreateGroupDialog.show(context);
    if (groupInfo == null) return;

    setState(() {
      _isProcessing = true;
      _status = "INITIALIZING";
    });

    bool hasPermissions = await _requestPermissions();
    if (!hasPermissions) {
      setState(() => _isProcessing = false);
      return;
    }

    final mesh = Provider.of<MeshService>(context, listen: false);
    
    await mesh.stopMesh();
    mesh.initialize(_nameController.text.trim());

    setState(() => _status = "CREATING GROUP");

    final created = await mesh.createGroup(
      groupInfo.name,
      groupInfo.agenda,
      isEncrypted: groupInfo.isEncrypted,
    );

    if (!mounted) return;

    if (!created) {
      setState(() {
        _isProcessing = false;
        _status = "READY";
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Failed to create group. Please try again.'),
          backgroundColor: Colors.red.shade800,
        ),
      );
      return;
    }


    if (groupInfo.isEncrypted) {
      await mesh.initEncryption();
    }

    if (!mounted) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          isHost: true,
          userName: _nameController.text.trim(),
          group: mesh.currentGroup,
        ),
      ),
    );

    if (mounted) {
      setState(() {
        _isProcessing = false;
        _status = "READY";
      });
    }
  }

  Future<void> _handleJoinNetwork(BuildContext context) async {
    if (_nameController.text.trim().isEmpty) {
      setState(() => _status = "Enter a name first");
      return;
    }

    setState(() {
      _isProcessing = true;
      _status = "SCANNING";
    });

    bool hasPermissions = await _requestPermissions();
    if (!hasPermissions) {
      setState(() => _isProcessing = false);
      return;
    }

    if (!mounted) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DiscoverGroupsScreen(
          userName: _nameController.text.trim(),
        ),
      ),
    );

    if (mounted) {
      setState(() {
        _isProcessing = false;
        _status = "READY";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32.0),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: MediaQuery.of(context).size.height -
                  MediaQuery.of(context).padding.top -
                  MediaQuery.of(context).padding.bottom,
            ),
            child: IntrinsicHeight(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Spacer(flex: 2),


                  Column(
                    children: [
                      _buildGearIcon(),
                      const SizedBox(height: 32),
                      Text(
                        "PROXIMITY",
                        style: AppTextStyles.displayLarge,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "OFFLINE MESH",
                        style: AppTextStyles.subHeading,
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),

                  const Spacer(),

                  _buildNameField(),

                  const SizedBox(height: 40),

                  _buildPremiumButton(
                    label: "CREATE",
                    icon: Icons.add_rounded,
                    onTap: _isProcessing
                        ? null
                        : () => _handleCreateNetwork(context),
                    isPrimary: true,
                    controller: _createBtnController,
                  ),
                  const SizedBox(height: 14),
                  _buildPremiumButton(
                    label: "JOIN",
                    icon: Icons.group_add_rounded,
                    onTap: _isProcessing
                        ? null
                        : () => _handleJoinNetwork(context),
                    isPrimary: false,
                    controller: _joinBtnController,
                  ),

                  const Spacer(),

                  _buildStatusBar(),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGearIcon() {
    return GestureDetector(
      onTap: () {
        setState(() => _hapticEnabled = !_hapticEnabled);
        if (_hapticEnabled) {
          HapticFeedback.lightImpact();
        }
      },
      child: AnimatedBuilder(
      animation: Listenable.merge([_gearAnimController, _pulseController]),
      builder: (context, child) {
        return SizedBox(
          width: 100,
          height: 100,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppColors.primary
                        .withValues(alpha: _pulseAnimation.value * 0.4),
                    width: 0.5,
                  ),
                ),
              ),
              Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppColors.primary
                        .withValues(alpha: _pulseAnimation.value * 0.2),
                    width: 0.5,
                  ),
                ),
              ),
              TweenAnimationBuilder<double>(
                tween: Tween<double>(end: _gearTargetAngle),
                duration: const Duration(milliseconds: 400),
                curve: Curves.easeOutBack,
                builder: (context, angle, child) {
                  return Transform.rotate(
                    angle: angle,
                    child: child,
                  );
                },
                child: Icon(
                  Icons.enhanced_encryption,
                  size: 42,
                  color: AppColors.primary
                      .withValues(alpha: 0.85 + _pulseAnimation.value * 0.15),
                ),
              ),
            ],
          ),
        );
      },
    ),
    );
  }

  Widget _buildNameField() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider, width: 0.5),
        color: AppColors.card,
      ),
      child: TextField(
        controller: _nameController,
        style: AppTextStyles.body.copyWith(fontSize: 16),
        textAlign: TextAlign.center,
        cursorColor: AppColors.primary,
        decoration: InputDecoration(
          hintText: "Your Name",
          hintStyle: AppTextStyles.body.copyWith(
            color: AppColors.secondary.withValues(alpha: 0.5),
            fontSize: 16,
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 18,
          ),
          prefixIcon: Padding(
            padding: const EdgeInsets.only(left: 16),
            child: Icon(
              Icons.person_outline_rounded,
              color: AppColors.secondary.withValues(alpha: 0.5),
              size: 20,
            ),
          ),
          prefixIconConstraints: const BoxConstraints(minWidth: 48),
          suffixIcon: const SizedBox(width: 48),
        ),
      ),
    );
  }

  Widget _buildPremiumButton({
    required String label,
    required IconData icon,
    required VoidCallback? onTap,
    required bool isPrimary,
    required AnimationController controller,
  }) {
    return GestureDetector(
      onTapDown: (_) => controller.forward(),
      onTapUp: (_) {
        controller.reverse();
        onTap?.call();
      },
      onTapCancel: () => controller.reverse(),
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, child) {
          final scale = 1.0 - (controller.value * 0.03);
          return Transform.scale(
            scale: scale,
            child: child,
          );
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: 56,
          decoration: BoxDecoration(
            color: isPrimary ? AppColors.primary : Colors.transparent,
            border: Border.all(
              color: isPrimary
                  ? AppColors.primary
                  : AppColors.secondary.withValues(alpha: 0.3),
              width: isPrimary ? 1 : 0.5,
            ),
            borderRadius: BorderRadius.circular(6),
          ),
          alignment: Alignment.center,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color: isPrimary ? AppColors.background : AppColors.primary,
              ),
              const SizedBox(width: 10),
              Text(
                label,
                style: AppTextStyles.button.copyWith(
                  color:
                      isPrimary ? AppColors.background : AppColors.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBar() {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: Column(
        key: ValueKey(_status + _isProcessing.toString()),
        children: [
          if (_isProcessing)
            SizedBox(
              width: 120,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(1),
                child: LinearProgressIndicator(
                  backgroundColor: AppColors.divider,
                  color: AppColors.primary,
                  minHeight: 1.5,
                ),
              ),
            ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 5,
                height: 5,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _isProcessing
                      ? Colors.amber
                      : (_status == "READY"
                          ? const Color(0xFF4ADE80)
                          : Colors.red.shade400),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _status,
                style: AppTextStyles.caption.copyWith(fontSize: 10),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
