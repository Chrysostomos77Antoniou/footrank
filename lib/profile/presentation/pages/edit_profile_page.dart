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
  late final _phoneCtrl = TextEditingController(text: widget.user.phone ?? '');
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
        phone: _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
        avatarUrl: avatarUrl,
      );
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
    if (m.contains('duplicate') || m.contains('unique')) {
      return 'That username is already taken';
    }
    return friendlyError(e);
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
                  _AvatarPicker(
                    name: _nameCtrl.text.isEmpty ? '?' : _nameCtrl.text,
                    pickedBytes: _pickedBytes,
                    currentUrl: _currentAvatar,
                    onTap: _pickImage,
                  ),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: _pickImage,
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('Change photo'),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _nameCtrl,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Full Name',
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                    validator: (v) =>
                        v == null || v.trim().isEmpty ? 'Name is required' : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
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
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
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
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
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
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _phoneCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Contact phone (optional)',
                      prefixIcon: Icon(Icons.phone_outlined),
                      helperText: 'Shared with opponents for confirmed matches',
                    ),
                  ),
                  const SizedBox(height: 28),
                  PressableScale(
                    onTap: _saving ? () {} : _save,
                    child: Container(
                      height: 54,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.brand(context),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: _saving
                          ? SizedBox(
                              height: 22,
                              width: 22,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: AppColors.onBrand(context)),
                            )
                          : Text('Save Changes',
                              style: TextStyle(
                                  color: AppColors.onBrand(context),
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800)),
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
