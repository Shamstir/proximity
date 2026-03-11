import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../utils/constants.dart';

class CreateGroupDialog extends StatefulWidget {
  const CreateGroupDialog({super.key});

  @override
  State<CreateGroupDialog> createState() => _CreateGroupDialogState();

  static Future<({String name, String agenda, bool isEncrypted})?> show(BuildContext context) {
    return showGeneralDialog<({String name, String agenda, bool isEncrypted})>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.black87,
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, anim1, anim2) => const CreateGroupDialog(),
      transitionBuilder: (context, anim1, anim2, child) {
        final curve = CurvedAnimation(parent: anim1, curve: Curves.easeOutCubic);
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.08),
            end: Offset.zero,
          ).animate(curve),
          child: FadeTransition(
            opacity: curve,
            child: child,
          ),
        );
      },
    );
  }
}

class _CreateGroupDialogState extends State<CreateGroupDialog> {
  final _nameController = TextEditingController();
  final _agendaController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isCreateHeld = false;
  bool _isEncrypted = true;

  TextStyle get _monoFont => GoogleFonts.jetBrainsMono(
    fontSize: 13,
    fontWeight: FontWeight.w400,
    height: 1.5,
    color: AppColors.primary,
  );

  @override
  void dispose() {
    _nameController.dispose();
    _agendaController.dispose();
    super.dispose();
  }

  void _handleCreate() {
    if (_formKey.currentState!.validate()) {
      HapticFeedback.lightImpact();
      Navigator.of(context).pop((
        name: _nameController.text.trim(),
        agenda: _agendaController.text.trim(),
        isEncrypted: _isEncrypted,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: 28,
          vertical: MediaQuery.of(context).viewInsets.bottom > 0 ? 24 : 60,
        ),
        child: Material(
          color: Colors.transparent,
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: AppColors.divider,
                width: 0.5,
              ),
            ),
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [

                      Row(
                        children: [
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: AppColors.primary.withValues(alpha: 0.2),
                                width: 0.5,
                              ),
                            ),
                            child: const Icon(
                              Icons.add_rounded,
                              color: AppColors.primary,
                              size: 16,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            "NEW GROUP",
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppColors.primary,
                              letterSpacing: 2,
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 28),


                      Container(
                        height: 0.5,
                        color: AppColors.divider,
                      ),

                      const SizedBox(height: 24),


                      Text(
                        "NAME",
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                          color: AppColors.secondary,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(height: 8),


                      Container(
                        decoration: BoxDecoration(
                          color: AppColors.card,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: AppColors.divider,
                            width: 0.5,
                          ),
                        ),
                        child: TextFormField(
                          controller: _nameController,
                          style: _monoFont,
                          cursorColor: AppColors.primary,
                          cursorWidth: 1,
                          decoration: InputDecoration(
                            hintText: "group name",
                            hintStyle: _monoFont.copyWith(
                              color: AppColors.secondary.withValues(alpha: 0.35),
                            ),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'enter a name';
                            }
                            return null;
                          },
                          autofocus: true,
                        ),
                      ),

                      const SizedBox(height: 20),


                      Text(
                        "AGENDA",
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                          color: AppColors.secondary,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(height: 8),


                      Container(
                        decoration: BoxDecoration(
                          color: AppColors.card,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: AppColors.divider,
                            width: 0.5,
                          ),
                        ),
                        child: TextFormField(
                          controller: _agendaController,
                          style: _monoFont,
                          cursorColor: AppColors.primary,
                          cursorWidth: 1,
                          maxLines: 3,
                          minLines: 2,
                          decoration: InputDecoration(
                            hintText: "what's this about?",
                            hintStyle: _monoFont.copyWith(
                              color: AppColors.secondary.withValues(alpha: 0.35),
                            ),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 20),


                      GestureDetector(
                        onTap: () => setState(() => _isEncrypted = !_isEncrypted),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: AppColors.card,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: _isEncrypted
                                  ? AppColors.primary.withValues(alpha: 0.3)
                                  : AppColors.divider,
                              width: 0.5,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                _isEncrypted ? Icons.lock_rounded : Icons.lock_open_rounded,
                                color: _isEncrypted ? AppColors.primary : AppColors.secondary,
                                size: 16,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _isEncrypted ? "ENCRYPTED" : "UNENCRYPTED",
                                      style: GoogleFonts.jetBrainsMono(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: _isEncrypted ? AppColors.primary : AppColors.secondary,
                                        letterSpacing: 1.2,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      _isEncrypted
                                          ? "end-to-end encrypted"
                                          : "messages sent in plaintext",
                                      style: GoogleFonts.jetBrainsMono(
                                        fontSize: 9,
                                        fontWeight: FontWeight.w400,
                                        color: AppColors.secondary.withValues(alpha: 0.6),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              SizedBox(
                                height: 24,
                                width: 40,
                                child: Switch(
                                  value: _isEncrypted,
                                  onChanged: (v) => setState(() => _isEncrypted = v),
                                  activeColor: AppColors.primary,
                                  activeTrackColor: AppColors.primary.withValues(alpha: 0.3),
                                  inactiveThumbColor: AppColors.secondary,
                                  inactiveTrackColor: AppColors.divider,
                                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 28),


                      Row(
                        children: [

                          Expanded(
                            child: GestureDetector(
                              onTap: () => Navigator.of(context).pop(),
                              child: Container(
                                height: 46,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: AppColors.divider,
                                    width: 0.5,
                                  ),
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  "CANCEL",
                                  style: GoogleFonts.jetBrainsMono(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                    color: AppColors.secondary,
                                    letterSpacing: 1.5,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),

                          Expanded(
                            child: GestureDetector(
                              onTapDown: (_) => setState(() => _isCreateHeld = true),
                              onTapUp: (_) {
                                setState(() => _isCreateHeld = false);
                                _handleCreate();
                              },
                              onTapCancel: () => setState(() => _isCreateHeld = false),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 100),
                                height: 46,
                                decoration: BoxDecoration(
                                  color: _isCreateHeld
                                      ? AppColors.accent
                                      : AppColors.primary,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                alignment: Alignment.center,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.arrow_forward_rounded,
                                      color: AppColors.background,
                                      size: 14,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      "CREATE",
                                      style: GoogleFonts.jetBrainsMono(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.background,
                                        letterSpacing: 1.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
