import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import 'package:footrank/core/constants/cities.dart';
import 'package:footrank/core/services/gallery_picker.dart';
import 'package:footrank/core/theme/app_colors.dart';
import 'package:footrank/core/theme/app_tokens.dart';
import 'package:footrank/core/widgets/brand_widgets.dart';
import 'package:footrank/core/widgets/premium.dart';
import 'package:footrank/models/user_model.dart';
import 'package:footrank/profile/data/profile_repository.dart';
import 'package:footrank/profile/presentation/widgets/profile_avatar.dart';
import 'package:footrank/profile/presentation/widgets/profile_fields.dart';
import 'package:footrank/core/widgets/feedback.dart';

const _positions = ['Goalkeeper', 'Defender', 'Midfielder', 'Forward'];

class EditProfilePage extends StatefulWidget {
  final UserModel user;
  const EditProfilePage({super.key, required this.user});

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  final _formKey = GlobalKey<FormState>();
  final _repo = ProfileRepository();

  late final _nameCtrl = TextEditingController(text: widget.user.name);
  late final _usernameCtrl = TextEditingController(text: widget.user.username);
  final _phoneCtrl = TextEditingController();
  late String? _city = canonicalCity(widget.user.city);
  late String? _position = widget.user.position;

  List<int>? _pickedBytes;
  String? _pickedExt;
  String? _currentAvatar;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _currentAvatar = widget.user.avatarUrl;
    // Load the phone from the owner-only contacts table.
    _repo.fetchMyPhone().then((p) {
      if (mounted && p != null) _phoneCtrl.text = p;
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _usernameCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picked = await GalleryPicker.pick();
    if (picked == null) return;
    setState(() {
      _pickedBytes = picked.bytes;
      _pickedExt = picked.ext;
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      String? avatarUrl = _currentAvatar;
      if (_pickedBytes != null) {
        avatarUrl = await _repo.uploadAvatar(_pickedBytes!, _pickedExt ?? 'jpg');
      }
      await _repo.updateProfile(
        name: _nameCtrl.text.trim(),
        username: _usernameCtrl.text.trim(),
        city: _city,
        position: _position,
        avatarUrl: avatarUrl,
      );
      await _repo.saveMyPhone(_phoneCtrl.text.trim());
      if (mounted) {
        showSuccess(context, 'Profile updated');
        context.pop(true);
      }
    } catch (e) {
      if (mounted) {
        showError(context, e);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Cyprus mobile: 8 digits starting with 9, with or without the +357 /
  /// 00357 prefix. Mirrors the server-side check (and profile_setup_page's
  /// copy) so the user gets the error inline instead of after a round-trip.
  static String? _validatePhone(String? v) {
    final digits = (v ?? '').replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return 'Phone number is required';
    var d = digits;
    if (d.startsWith('00')) d = d.substring(2);
    if (d.length == 8 && d.startsWith('9')) d = '357$d';
    if (!RegExp(r'^3579[0-9]{7}$').hasMatch(d)) {
      return 'Enter a valid Cyprus mobile, e.g. 99 123456';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final fieldStyle = profileFieldTextStyle(context);
    final iconDown = Icon(Icons.keyboard_arrow_down,
        size: 18, color: AppColors.muted(context));
    return Scaffold(
      body: AmbientBackground(
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Tooltip(
                              message: 'Back',
                              child: PressableScale(
                                onTap: () => Navigator.of(context).maybePop(),
                                semanticLabel: 'Back',
                                child: Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).brightness ==
                                            Brightness.dark
                                        ? AppColors.darkCard
                                        : AppColors.lightCard,
                                    borderRadius: BorderRadius.circular(
                                        AppSemantic.controlRadius),
                                    border: Border.all(
                                        color: AppColors.border(context)),
                                  ),
                                  child: Icon(Icons.chevron_left,
                                      size: 26, color: onSurface),
                                ),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Text(
                                'Edit Profile',
                                style: TextStyle(
                                  fontFamily: AppFonts.display,
                                  fontSize: 26,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.26,
                                  height: 1.2,
                                  color: onSurface,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        FadeSlideIn(
                          child: Center(
                            child: _AvatarPicker(
                              name:
                                  _nameCtrl.text.isEmpty ? '?' : _nameCtrl.text,
                              pickedBytes: _pickedBytes,
                              currentUrl: _currentAvatar,
                              onTap: _pickImage,
                            ),
                          ),
                        ),
                        const SizedBox(height: 2),
                        FadeSlideIn(
                          delay: const Duration(milliseconds: 60),
                          child: Center(
                            child: TextButton.icon(
                              onPressed: _pickImage,
                              style: TextButton.styleFrom(
                                foregroundColor: AppColors.brand(context),
                                minimumSize: const Size(0, 44),
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 14),
                                textStyle: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              icon: const Icon(Icons.photo_library_outlined,
                                  size: 18),
                              label: const Text('Change photo'),
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        FadeSlideIn(
                          delay: const Duration(milliseconds: 100),
                          child: LabeledField(
                            label: 'Full Name',
                            child: TextFormField(
                              controller: _nameCtrl,
                              textCapitalization: TextCapitalization.words,
                              style: fieldStyle,
                              decoration: profileInputDecoration(
                                context,
                                icon: Icons.person_outline,
                              ),
                              validator: (v) => v == null || v.trim().isEmpty
                                  ? 'Name is required'
                                  : null,
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        FadeSlideIn(
                          delay: const Duration(milliseconds: 140),
                          child: LabeledField(
                            label: 'Username',
                            child: TextFormField(
                              controller: _usernameCtrl,
                              style: fieldStyle,
                              decoration: profileInputDecoration(
                                context,
                                icon: Icons.alternate_email,
                                prefixText: '@',
                              ),
                              validator: (v) {
                                if (v == null || v.trim().isEmpty) {
                                  return 'Username is required';
                                }
                                if (v.trim().length < 3) {
                                  return 'At least 3 characters';
                                }
                                return null;
                              },
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        FadeSlideIn(
                          delay: const Duration(milliseconds: 180),
                          child: LabeledField(
                            label: 'City',
                            child: DropdownButtonFormField<String>(
                              value: _city,
                              isExpanded: true,
                              style: fieldStyle,
                              icon: iconDown,
                              borderRadius: BorderRadius.circular(
                                  AppSemantic.controlRadius),
                              decoration: profileInputDecoration(
                                context,
                                icon: Icons.place_outlined,
                                verticalPadding: 14,
                              ),
                              items: kCities
                                  .map((c) => DropdownMenuItem(
                                      value: c, child: Text(c)))
                                  .toList(),
                              onChanged: (v) => setState(() => _city = v),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        FadeSlideIn(
                          delay: const Duration(milliseconds: 220),
                          child: LabeledField(
                            label: 'Preferred Position',
                            child: DropdownButtonFormField<String>(
                              value: _position,
                              isExpanded: true,
                              style: fieldStyle,
                              icon: iconDown,
                              borderRadius: BorderRadius.circular(
                                  AppSemantic.controlRadius),
                              decoration: profileInputDecoration(
                                context,
                                icon: Icons.sports_soccer_outlined,
                                verticalPadding: 14,
                              ),
                              items: _positions
                                  .map((p) => DropdownMenuItem(
                                      value: p, child: Text(p)))
                                  .toList(),
                              onChanged: (v) => setState(() => _position = v),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        FadeSlideIn(
                          delay: const Duration(milliseconds: 260),
                          child: LabeledField(
                            label: 'Contact phone',
                            child: TextFormField(
                              controller: _phoneCtrl,
                              keyboardType: TextInputType.phone,
                              style: fieldStyle.copyWith(
                                fontFeatures: const [
                                  FontFeature.tabularFigures()
                                ],
                              ),
                              decoration: profileInputDecoration(
                                context,
                                icon: Icons.phone_outlined,
                                helperText:
                                    'Shared with opponents for confirmed matches',
                              ),
                              validator: _validatePhone,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                child: FadeSlideIn(
                  delay: const Duration(milliseconds: 300),
                  child: BrandButton(
                    label: 'Save Changes',
                    loading: _saving,
                    onPressed: _save,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AvatarPicker extends StatelessWidget {
  final String name;
  final List<int>? pickedBytes;
  final String? currentUrl;
  final VoidCallback onTap;

  const _AvatarPicker({
    required this.name,
    required this.pickedBytes,
    required this.currentUrl,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    ImageProvider? image;
    if (pickedBytes != null) {
      image = MemoryImage(Uint8List.fromList(pickedBytes!));
    } else if (currentUrl != null && currentUrl!.isNotEmpty) {
      image = CachedNetworkImageProvider(currentUrl!);
    }
    final bg = Theme.of(context).scaffoldBackgroundColor;

    return Semantics(
      button: true,
      label: 'Change profile photo',
      child: GestureDetector(
        onTap: onTap,
        child: SizedBox(
          width: 104,
          height: 104,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              ProfileAvatar(
                name: name,
                image: image,
                size: 104,
                ring: 3,
                gap: 3,
                fontSize: 38,
              ),
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: AppColors.action,
                    shape: BoxShape.circle,
                    border: Border.all(color: bg, width: 2),
                  ),
                  child: Icon(Icons.camera_alt_outlined,
                      color: AppColors.onAction(context), size: 16),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
