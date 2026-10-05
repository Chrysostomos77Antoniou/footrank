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
import 'package:footrank/models/team_model.dart';
import 'package:footrank/team/data/team_repository.dart';
import 'package:footrank/team/presentation/widgets/team_ui.dart';
import 'package:footrank/core/widgets/feedback.dart';

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
        showSuccess(context, 'Team updated');
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AmbientBackground(
        child: SafeArea(
          child: Column(
            children: [
              const TeamPageHeader(title: 'Edit Team'),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 32, 20, 24),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        FadeSlideIn(
                          child: Center(
                            child: _LogoPicker(
                              name:
                                  _nameCtrl.text.isEmpty ? '?' : _nameCtrl.text,
                              pickedBytes: _pickedBytes,
                              currentUrl: _currentLogo,
                              onTap: _pickImage,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        FadeSlideIn(
                          delay: const Duration(milliseconds: 60),
                          child: Center(
                            child: TextButton.icon(
                              onPressed: _pickImage,
                              style: TextButton.styleFrom(
                                minimumSize: const Size(0, 44),
                                foregroundColor: AppColors.brand(context),
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 14),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(
                                        AppSemantic.controlRadius)),
                              ),
                              icon: const Icon(Icons.image_outlined, size: 20),
                              label: const Text('Change team logo'),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        FadeSlideIn(
                          delay: const Duration(milliseconds: 120),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const TeamFieldLabel('Team Name'),
                              TextFormField(
                                controller: _nameCtrl,
                                textCapitalization: TextCapitalization.words,
                                style: const TextStyle(
                                    fontSize: 15, fontWeight: FontWeight.w600),
                                decoration: teamFieldDecoration(context,
                                    hint: 'Team Name',
                                    icon: Icons.shield_outlined),
                                validator: (v) => v == null || v.trim().isEmpty
                                    ? 'Team name is required'
                                    : null,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 18),
                        FadeSlideIn(
                          delay: const Duration(milliseconds: 160),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const TeamFieldLabel('City'),
                              DropdownButtonFormField<String>(
                                value: _city,
                                isExpanded: true,
                                style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurface),
                                decoration: teamFieldDecoration(context,
                                    hint: 'City', icon: Icons.place_outlined),
                                items: kCities
                                    .map((c) => DropdownMenuItem(
                                        value: c, child: Text(c)))
                                    .toList(),
                                onChanged: (v) => setState(() => _city = v),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    const inner = 98.0; // 110 - 2 * (3 ring + 3 gap)
    Widget logo;
    if (pickedBytes != null) {
      logo = CircleAvatar(
        radius: inner / 2,
        backgroundImage: MemoryImage(Uint8List.fromList(pickedBytes!)),
      );
    } else if (currentUrl != null && currentUrl!.isNotEmpty) {
      logo = CircleAvatar(
          radius: inner / 2,
          backgroundImage: CachedNetworkImageProvider(currentUrl!));
    } else {
      logo = Container(
        width: inner,
        height: inner,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isDark ? AppColors.darkElevated : AppColors.limeDeep,
        ),
        alignment: Alignment.center,
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : '?',
          style: TextStyle(
            fontFamily: AppFonts.display,
            fontSize: 40,
            fontWeight: FontWeight.w800,
            color: isDark ? scheme.onSurface : Colors.white,
          ),
        ),
      );
    }

    return Semantics(
      button: true,
      label: 'Change team logo',
      child: GestureDetector(
        onTap: onTap,
        child: SizedBox(
          width: 110,
          height: 110,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 110,
                height: 110,
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.brand(context), width: 3),
                ),
                child: ClipOval(child: logo),
              ),
              Positioned(
                right: -3,
                bottom: -3,
                child: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: AppColors.action,
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: Theme.of(context).scaffoldBackgroundColor,
                        width: 3),
                  ),
                  child: Icon(Icons.camera_alt_outlined,
                      color: AppColors.onAction(context), size: 18),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
