import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import 'package:footrank/core/constants/cities.dart';
import 'package:footrank/core/services/gallery_picker.dart';
import 'package:footrank/core/theme/app_colors.dart';
import 'package:footrank/core/utils/error_text.dart';
import 'package:footrank/core/widgets/brand_widgets.dart';
import 'package:footrank/core/widgets/premium.dart';
import 'package:footrank/models/user_model.dart';
import 'package:footrank/profile/data/profile_repository.dart';

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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile updated')),
        );
        context.pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(_friendly(e))));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _friendly(Object e) {
    final m = e.toString();
    if (m.contains('PHONE_TAKEN') ||
        m.contains('uq_user_contacts_phone_normalized')) {
      return 'That phone number is already linked to another account';
    }
    if (m.contains('PHONE_INVALID')) {
      return 'Enter a valid Cyprus mobile, e.g. 99 123456';
    }
    if (m.contains('PHONE_REQUIRED')) {
      return 'Phone number is required';
    }
    if (m.contains('duplicate') || m.contains('unique')) {
      return 'That username is already taken';
    }
    return friendlyError(e);
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
    return Scaffold(
      appBar: AppBar(title: const Text('Edit Profile')),
      body: AmbientBackground(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            child: Form(
              key: _formKey,
              child: Column(
                children: [
                  FadeSlideIn(
                    child: _AvatarPicker(
                      name: _nameCtrl.text.isEmpty ? '?' : _nameCtrl.text,
                      pickedBytes: _pickedBytes,
                      currentUrl: _currentAvatar,
                      onTap: _pickImage,
                    ),
                  ),
                  const SizedBox(height: 8),
                  FadeSlideIn(
                    delay: const Duration(milliseconds: 60),
                    child: TextButton.icon(
                      onPressed: _pickImage,
                      icon: const Icon(Icons.photo_library_outlined),
                      label: const Text('Change photo'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FadeSlideIn(
                    delay: const Duration(milliseconds: 100),
                    child: TextFormField(
                      controller: _nameCtrl,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Full Name',
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                      validator: (v) => v == null || v.trim().isEmpty
                          ? 'Name is required'
                          : null,
                    ),
                  ),
                  const SizedBox(height: 16),
                  FadeSlideIn(
                    delay: const Duration(milliseconds: 140),
                    child: TextFormField(
                      controller: _usernameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Username',
                        prefixText: '@',
                        prefixIcon: Icon(Icons.alternate_email),
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return 'Username is required';
                        }
                        if (v.trim().length < 3) return 'At least 3 characters';
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                  FadeSlideIn(
                    delay: const Duration(milliseconds: 180),
                    child: DropdownButtonFormField<String>(
                      value: _city,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'City',
                        prefixIcon: Icon(Icons.place_outlined),
                      ),
                      items: kCities
                          .map((c) =>
                              DropdownMenuItem(value: c, child: Text(c)))
                          .toList(),
                      onChanged: (v) => setState(() => _city = v),
                    ),
                  ),
                  const SizedBox(height: 16),
                  FadeSlideIn(
                    delay: const Duration(milliseconds: 220),
                    child: DropdownButtonFormField<String>(
                      value: _position,
                      decoration: const InputDecoration(
                        labelText: 'Preferred Position',
                        prefixIcon: Icon(Icons.sports_soccer_outlined),
                      ),
                      items: _positions
                          .map((p) =>
                              DropdownMenuItem(value: p, child: Text(p)))
                          .toList(),
                      onChanged: (v) => setState(() => _position = v),
                    ),
                  ),
                  const SizedBox(height: 16),
                  FadeSlideIn(
                    delay: const Duration(milliseconds: 260),
                    child: TextFormField(
                      controller: _phoneCtrl,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Contact phone',
                        prefixIcon: Icon(Icons.phone_outlined),
                        helperText:
                            'Shared with opponents for confirmed matches',
                      ),
                      validator: _validatePhone,
                    ),
                  ),
                  const SizedBox(height: 28),
                  FadeSlideIn(
                    delay: const Duration(milliseconds: 300),
                    child: BrandButton(
                      label: 'Save Changes',
                      loading: _saving,
                      onPressed: _save,
                    ),
                  ),
                ],
              ),
            ),
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
    Widget avatar;
    if (pickedBytes != null) {
      avatar = CircleAvatar(
        radius: 52,
        backgroundImage: MemoryImage(Uint8List.fromList(pickedBytes!)),
      );
    } else if (currentUrl != null && currentUrl!.isNotEmpty) {
      avatar = CircleAvatar(radius: 52, backgroundImage: CachedNetworkImageProvider(currentUrl!));
    } else {
      avatar = GradientAvatar(name: name, radius: 52);
    }

    return GestureDetector(
      onTap: onTap,
      child: Stack(
        alignment: Alignment.bottomRight,
        children: [
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.brand(context), width: 3),
            ),
            child: avatar,
          ),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.brand(context),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.camera_alt,
                color: AppColors.onBrand(context), size: 18),
          ),
        ],
      ),
    );
  }
}
