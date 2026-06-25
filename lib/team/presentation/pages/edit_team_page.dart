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
import 'package:footrank/models/team_model.dart';
import 'package:footrank/team/data/team_repository.dart';

class EditTeamPage extends StatefulWidget {
  final TeamModel team;
  const EditTeamPage({super.key, required this.team});

  @override
  State<EditTeamPage> createState() => _EditTeamPageState();
}

class _EditTeamPageState extends State<EditTeamPage> {
  final _formKey = GlobalKey<FormState>();
  final _repo = TeamRepository();

  late final _nameCtrl = TextEditingController(text: widget.team.name);
  late String? _city = canonicalCity(widget.team.city);

  List<int>? _pickedBytes;
  String? _pickedExt;
  String? _currentLogo;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _currentLogo = widget.team.logoUrl;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
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
      String? logoUrl = _currentLogo;
      if (_pickedBytes != null) {
        logoUrl = await _repo.uploadLogo(_pickedBytes!, _pickedExt ?? 'jpg');
      }
      await _repo.updateTeam(
        teamId: widget.team.id,
        name: _nameCtrl.text.trim(),
        city: _city,
        logoUrl: logoUrl,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Team updated')),
        );
        context.pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Edit Team')),
      body: AmbientBackground(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            child: Form(
              key: _formKey,
              child: Column(
                children: [
                  _LogoPicker(
                    name: _nameCtrl.text.isEmpty ? '?' : _nameCtrl.text,
                    pickedBytes: _pickedBytes,
                    currentUrl: _currentLogo,
                    onTap: _pickImage,
                  ),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: _pickImage,
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('Change team logo'),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _nameCtrl,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Team Name',
                      prefixIcon: Icon(Icons.shield_outlined),
                    ),
                    validator: (v) => v == null || v.trim().isEmpty
                        ? 'Team name is required'
                        : null,
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: _city,
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

class _LogoPicker extends StatelessWidget {
  final String name;
  final List<int>? pickedBytes;
  final String? currentUrl;
  final VoidCallback onTap;

  const _LogoPicker({
    required this.name,
    required this.pickedBytes,
    required this.currentUrl,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    Widget logo;
    if (pickedBytes != null) {
      logo = CircleAvatar(
        radius: 52,
        backgroundImage: MemoryImage(Uint8List.fromList(pickedBytes!)),
      );
    } else if (currentUrl != null && currentUrl!.isNotEmpty) {
      logo =
          CircleAvatar(radius: 52, backgroundImage: CachedNetworkImageProvider(currentUrl!));
    } else {
      logo = GradientAvatar(name: name, radius: 52);
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
            child: logo,
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
