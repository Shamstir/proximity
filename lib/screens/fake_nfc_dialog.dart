import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../utils/constants.dart';

/// A purely visual dialog that simulates a Nearby/NFC key transfer.
/// No real NFC hardware is used. Completes after ~3 s and pops with [true].
class FakeNfcTransferDialog extends StatefulWidget {
  /// Whether this device is the one *sending* the key (host side).
  final bool isSender;

  const FakeNfcTransferDialog({super.key, this.isSender = false});

  /// Convenience helper that shows the dialog and returns when done.
  static Future<void> show(BuildContext context, {bool isSender = false}) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black87,
      builder: (_) => FakeNfcTransferDialog(isSender: isSender),
    );
  }

  @override
  State<FakeNfcTransferDialog> createState() => _FakeNfcTransferDialogState();
}

class _FakeNfcTransferDialogState extends State<FakeNfcTransferDialog>
    with TickerProviderStateMixin {
  // ── animations ─────────────────────────────────────────────────────────────
  late AnimationController _approachCtrl;  // phones moving toward each other
  late AnimationController _pulseCtrl;     // ripple ring
  late AnimationController _successCtrl;   // checkmark fade-in
  late Animation<double> _leftPhone;
  late Animation<double> _rightPhone;

  // ── state ──────────────────────────────────────────────────────────────────
  int _step = 0; // 0=scanning, 1=tap, 2=transferring, 3=done
  final List<String> _steps = [
    'Scanning nearby device...',
    'Tap detected',
    'Transferring key...',
    '✓  Key received',
  ];

  @override
  void initState() {
    super.initState();

    _approachCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _successCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );

    _leftPhone = Tween<double>(begin: -70, end: -4).animate(
      CurvedAnimation(parent: _approachCtrl, curve: Curves.easeInOut),
    );
    _rightPhone = Tween<double>(begin: 70, end: 4).animate(
      CurvedAnimation(parent: _approachCtrl, curve: Curves.easeInOut),
    );

    _runSequence();
  }

  Future<void> _runSequence() async {
    // Step 0: scanning
    setState(() => _step = 0);
    await Future.delayed(const Duration(milliseconds: 700));

    // Step 1: phones approach
    await _approachCtrl.forward();
    setState(() => _step = 1);
    // Light pulse burst
    await _pulseCtrl.forward();
    _pulseCtrl.reset();
    await _pulseCtrl.forward();
    _pulseCtrl.reset();

    // Step 2: transfer  
    setState(() => _step = 2);
    await Future.delayed(const Duration(milliseconds: 900));

    // Step 3: done ✓
    setState(() => _step = 3);
    _successCtrl.forward();
    await Future.delayed(const Duration(milliseconds: 1100));

    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  void dispose() {
    _approachCtrl.dispose();
    _pulseCtrl.dispose();
    _successCtrl.dispose();
    super.dispose();
  }

  // ── build ───────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildTitle(),
            const SizedBox(height: 32),
            _buildPhoneAnimation(),
            const SizedBox(height: 32),
            _buildStepLabel(),
            const SizedBox(height: 8),
            _buildProgressDots(),
          ],
        ),
      ),
    );
  }

  Widget _buildTitle() {
    return Column(
      children: [
        Text(
          widget.isSender ? 'SENDING KEY' : 'RECEIVING KEY',
          style: GoogleFonts.jetBrainsMono(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppColors.primary,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'via Nearby Connection',
          style: GoogleFonts.jetBrainsMono(
            fontSize: 10,
            color: AppColors.secondary,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }

  Widget _buildPhoneAnimation() {
    return SizedBox(
      height: 120,
      child: AnimatedBuilder(
        animation: Listenable.merge([_approachCtrl, _pulseCtrl]),
        builder: (context, _) {
          return Stack(
            alignment: Alignment.center,
            children: [
              // Ripple rings that appear on "tap"
              if (_step >= 1)
                ..._buildRipples(),
              // Left phone
              Transform.translate(
                offset: Offset(_leftPhone.value, 0),
                child: _buildPhone(isLeft: true),
              ),
              // Right phone
              Transform.translate(
                offset: Offset(_rightPhone.value, 0),
                child: _buildPhone(isLeft: false),
              ),
              // Success checkmark
              if (_step == 3)
                FadeTransition(
                  opacity: _successCtrl,
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFF4ADE80).withValues(alpha: 0.15),
                    ),
                    child: const Icon(
                      Icons.check_rounded,
                      color: Color(0xFF4ADE80),
                      size: 22,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  List<Widget> _buildRipples() {
    return List.generate(3, (i) {
      final delay = i * 0.33;
      final t = (_pulseCtrl.value - delay).clamp(0.0, 1.0);
      final radius = 10.0 + t * 60.0;
      final alpha = (1.0 - t) * 0.6;
      return Positioned.fill(
        child: Center(
          child: Container(
            width: radius * 2,
            height: radius * 2,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: AppColors.accent.withValues(alpha: alpha),
                width: 1.2,
              ),
            ),
          ),
        ),
      );
    });
  }

  Widget _buildPhone({required bool isLeft}) {
    final accentColor = _step >= 2
        ? const Color(0xFF4ADE80)
        : (_step == 1 ? AppColors.accent : AppColors.secondary);

    return Container(
      width: 44,
      height: 80,
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: accentColor.withValues(alpha: 0.6),
          width: 1.5,
        ),
        boxShadow: _step >= 1
            ? [
                BoxShadow(
                  color: accentColor.withValues(alpha: 0.25),
                  blurRadius: 12,
                  spreadRadius: 2,
                )
              ]
            : null,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Screen glow
          Container(
            width: 28,
            height: 40,
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: _step >= 2 ? 0.12 : 0.05),
              borderRadius: BorderRadius.circular(4),
            ),
            child: _step >= 2
                ? Icon(
                    isLeft == widget.isSender
                        ? Icons.upload_rounded
                        : Icons.download_rounded,
                    size: 14,
                    color: accentColor,
                  )
                : null,
          ),
          const SizedBox(height: 6),
          // Home bar
          Container(
            width: 16,
            height: 2,
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(1),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepLabel() {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: Text(
        _steps[_step],
        key: ValueKey(_step),
        style: GoogleFonts.jetBrainsMono(
          fontSize: 12,
          color: _step == 3
              ? const Color(0xFF4ADE80)
              : AppColors.accent,
          letterSpacing: 0.5,
          fontWeight: _step == 3 ? FontWeight.w600 : FontWeight.w400,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildProgressDots() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(4, (i) {
        final active = i <= _step;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width: active ? 18 : 6,
          height: 4,
          decoration: BoxDecoration(
            color: active
                ? (_step == 3
                    ? const Color(0xFF4ADE80)
                    : AppColors.primary)
                : AppColors.divider,
            borderRadius: BorderRadius.circular(2),
          ),
        );
      }),
    );
  }
}
