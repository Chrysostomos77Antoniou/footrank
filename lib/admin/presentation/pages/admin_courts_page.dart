import 'package:flutter/material.dart';
import 'package:footrank/admin/data/admin_repository.dart';
import 'package:footrank/admin/models/admin_court_model.dart';
import 'package:footrank/admin/presentation/widgets/admin_widgets.dart';
import 'package:footrank/core/constants/cities.dart';
import 'package:footrank/core/theme/app_colors.dart';
import 'package:footrank/core/theme/app_tokens.dart';
import 'package:footrank/core/utils/error_text.dart';
import 'package:footrank/core/widgets/brand_widgets.dart';
import 'package:footrank/core/widgets/premium.dart';
import 'package:image_picker/image_picker.dart';

class AdminCourtsPage extends StatefulWidget {
  const AdminCourtsPage({super.key});

  @override
  State<AdminCourtsPage> createState() => _AdminCourtsPageState();
}

enum _ActiveFilter { all, active, inactive }

class _AdminCourtsPageState extends State<AdminCourtsPage> {
  final _repo = AdminRepository();
  late Future<List<AdminCourtModel>> _future;
  _ActiveFilter _filter = _ActiveFilter.all;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() => setState(() => _future = _repo.fetchAllCourts());

  List<AdminCourtModel> _applyFilter(List<AdminCourtModel> courts) {
    switch (_filter) {
      case _ActiveFilter.all:
        return courts;
      case _ActiveFilter.active:
        return courts.where((c) => c.active).toList();
      case _ActiveFilter.inactive:
        return courts.where((c) => !c.active).toList();
    }
  }

  Future<void> _openEditor([AdminCourtModel? court]) async {
    final result = await showDialog<AdminCourtModel>(
      context: context,
      animationStyle: kAdminDialogAnimationStyle,
      builder: (_) => _CourtEditorDialog(court: court),
    );
    if (result == null) return;
    try {
      await _repo.upsertCourt(result, isNew: court == null);
      _reload();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    }
  }

  Future<void> _toggleActive(AdminCourtModel court) async {
    try {
      await _repo.upsertCourt(court.copyWith(active: !court.active));
      _reload();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AdminHeader(
          title: 'Courts',
          subtitle: 'Every bookable court, across every city.',
          action: FilledButton.icon(
            onPressed: () => _openEditor(),
            // The app's global FilledButtonThemeData sets minimumSize to
            // Size.fromHeight(52) for the mobile app's full-width buttons --
            // that's Size(double.infinity, 52). Left as-is here, this button
            // (a sibling of Expanded in a Row) claims effectively all the
            // header's width, squeezing the title down to a sliver.
            style: FilledButton.styleFrom(
              minimumSize: Size.zero,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add court'),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Row(
          children: [
            ChoiceChip(
              label: const Text('All'),
              selected: _filter == _ActiveFilter.all,
              onSelected: (_) => setState(() => _filter = _ActiveFilter.all),
            ),
            const SizedBox(width: AppSpacing.xs),
            ChoiceChip(
              label: const Text('Active'),
              selected: _filter == _ActiveFilter.active,
              onSelected: (_) =>
                  setState(() => _filter = _ActiveFilter.active),
            ),
            const SizedBox(width: AppSpacing.xs),
            ChoiceChip(
              label: const Text('Inactive'),
              selected: _filter == _ActiveFilter.inactive,
              onSelected: (_) =>
                  setState(() => _filter = _ActiveFilter.inactive),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Expanded(
          child: FutureBuilder<List<AdminCourtModel>>(
            future: _future,
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final courts = _applyFilter(snapshot.data!);
              if (courts.isEmpty) {
                return AdminEmptyState(
                  icon: Icons.place_outlined,
                  message: _filter == _ActiveFilter.all
                      ? 'No courts yet -- add the first one.'
                      : 'No ${_filter == _ActiveFilter.active ? 'active' : 'inactive'} courts.',
                );
              }
              return FadeSlideIn(
                // GlassCard doesn't force a width, so under the loose
                // constraints this sits inside it shrinks to fit its
                // content and then gets left where the Column places it --
                // forcing full width here guarantees it always spans the
                // page instead of floating narrower than expected.
                child: SizedBox(
                  width: double.infinity,
                  child: GlassCard(
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    child: AdminScrollableTable(
                      child: Column(
                        children: [
                          const AdminTableHeader(
                            columns: ['Court', 'City', 'Hours', 'Active', ''],
                            flex: [3, 2, 3, 0, 0],
                            fixedWidths: [null, null, null, 56, 44],
                          ),
                          for (final court in courts)
                            _CourtRow(
                              court: court,
                              onEdit: () => _openEditor(court),
                              onToggleActive: () => _toggleActive(court),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _CourtRow extends StatelessWidget {
  final AdminCourtModel court;
  final VoidCallback onEdit;
  final VoidCallback onToggleActive;

  const _CourtRow({
    required this.court,
    required this.onEdit,
    required this.onToggleActive,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onEdit,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: 10,
        ),
        child: Row(
          children: [
            Expanded(
              flex: 3,
              child: Row(
                children: [
                  GradientAvatar(
                    name: court.name,
                    imageUrl: court.imageUrl,
                    radius: 16,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      court.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 2,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(court.city),
              ),
            ),
            Expanded(
              flex: 3,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  court.hours ?? '—',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Theme.of(context).hintColor),
                ),
              ),
            ),
            // Fixed-width trailing columns (not flex-proportional) so the
            // switch and edit button sit in the same pixel position on
            // every row, instead of drifting with each row's text length.
            SizedBox(
              width: 56,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Tooltip(
                  message: court.active ? 'Active — tap to deactivate' : 'Inactive — tap to activate',
                  child: Switch(
                    value: court.active,
                    onChanged: (_) => onToggleActive(),
                  ),
                ),
              ),
            ),
            SizedBox(
              width: 44,
              child: IconButton(
                tooltip: 'Edit court',
                icon: const Icon(Icons.edit_outlined, size: 18),
                onPressed: onEdit,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CourtEditorDialog extends StatefulWidget {
  final AdminCourtModel? court;
  const _CourtEditorDialog({this.court});

  @override
  State<_CourtEditorDialog> createState() => _CourtEditorDialogState();
}

class _CourtEditorDialogState extends State<_CourtEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.court?.name);
  late final _address = TextEditingController(text: widget.court?.address);
  late final _phone = TextEditingController(text: widget.court?.phone);
  late final _website = TextEditingController(text: widget.court?.website);
  late final _imageUrl = TextEditingController(text: widget.court?.imageUrl);
  late final _sortOrder = TextEditingController(
    text: widget.court?.sortOrder?.toString(),
  );
  late String _city = widget.court?.city ?? kCities.first;
  late bool _active = widget.court?.active ?? true;
  late TimeOfDay? _opens;
  late TimeOfDay? _closes;

  bool _uploading = false;
  String? _uploadError;

  @override
  void initState() {
    super.initState();
    final parsed = _parseHours(widget.court?.hours);
    _opens = parsed.$1;
    _closes = parsed.$2;
  }

  // The stored `hours` column predates this UI and was free text (e.g.
  // "Mon-Sun 09:00-23:00") -- best-effort pull the first "H:MM - H:MM" pair
  // out of whatever's there so editing an old court doesn't start blank.
  static (TimeOfDay?, TimeOfDay?) _parseHours(String? raw) {
    if (raw == null) return (null, null);
    final m = RegExp(
      r'(\d{1,2}):(\d{2})\s*-\s*(\d{1,2}):(\d{2})',
    ).firstMatch(raw);
    if (m == null) return (null, null);
    return (
      TimeOfDay(hour: int.parse(m.group(1)!), minute: int.parse(m.group(2)!)),
      TimeOfDay(hour: int.parse(m.group(3)!), minute: int.parse(m.group(4)!)),
    );
  }

  static String _fmt24(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> _pickOpens() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _opens ?? const TimeOfDay(hour: 9, minute: 0),
    );
    if (picked != null) setState(() => _opens = picked);
  }

  Future<void> _pickCloses() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _closes ?? const TimeOfDay(hour: 23, minute: 0),
    );
    if (picked != null) setState(() => _closes = picked);
  }

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    _phone.dispose();
    _website.dispose();
    _imageUrl.dispose();
    _sortOrder.dispose();
    super.dispose();
  }

  // On web, ImageSource.gallery opens the browser's native file picker --
  // on a phone browser that picker itself offers "Photo Library"/"Camera",
  // so one source covers "from my computer or from my phone's gallery".
  Future<void> _pickAndUploadImage() async {
    final XFile? file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (file == null) return;
    setState(() {
      _uploading = true;
      _uploadError = null;
    });
    try {
      final bytes = await file.readAsBytes();
      final ext = file.name.contains('.') ? file.name.split('.').last : 'jpg';
      final url = await AdminRepository().uploadCourtImage(bytes, ext);
      if (!mounted) return;
      setState(() => _imageUrl.text = url);
    } catch (e) {
      if (mounted) setState(() => _uploadError = friendlyError(e));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final opens = _opens;
    final closes = _closes;
    Navigator.of(context).pop(
      AdminCourtModel(
        id: widget.court?.id ?? '',
        name: _name.text.trim(),
        city: _city,
        address: _address.text.trim().isEmpty ? null : _address.text.trim(),
        phone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
        website: _website.text.trim().isEmpty ? null : _website.text.trim(),
        hours: opens != null && closes != null
            ? '${_fmt24(opens)} - ${_fmt24(closes)}'
            : null,
        imageUrl: _imageUrl.text.trim().isEmpty ? null : _imageUrl.text.trim(),
        active: _active,
        sortOrder: int.tryParse(_sortOrder.text.trim()),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isNew = widget.court == null;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(AppSpacing.lg),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 700),
        child: GlassCard(
          padding: EdgeInsets.zero,
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _DialogTitleBar(
                  icon: isNew ? Icons.add_location_alt_outlined : Icons.edit_location_alt_outlined,
                  title: isNew ? 'Add court' : 'Edit court',
                  subtitle: isNew
                      ? 'Create a new bookable court'
                      : widget.court!.name,
                  onClose: () => Navigator.of(context).pop(),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.xl,
                      AppSpacing.lg,
                      AppSpacing.xl,
                      AppSpacing.xl,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _CourtPhotoPicker(
                          imageUrl: _imageUrl.text,
                          uploading: _uploading,
                          onTap: _pickAndUploadImage,
                        ),
                        if (_uploadError != null) ...[
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            _uploadError!,
                            style: Theme.of(
                              context,
                            ).textTheme.labelMedium?.copyWith(color: AppColors.danger),
                          ),
                        ],
                        const SizedBox(height: AppSpacing.xl),
                        const _SectionLabel(
                          icon: Icons.info_outline,
                          label: 'Basic info',
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        TextFormField(
                          controller: _name,
                          decoration: const InputDecoration(
                            labelText: 'Name',
                            prefixIcon: Icon(Icons.sports_soccer, size: 20),
                          ),
                          validator: (v) =>
                              v == null || v.trim().isEmpty ? 'Required' : null,
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        DropdownButtonFormField<String>(
                          value: _city,
                          decoration: const InputDecoration(
                            labelText: 'City',
                            prefixIcon: Icon(Icons.location_city, size: 20),
                          ),
                          items: kCities
                              .map(
                                (c) => DropdownMenuItem(value: c, child: Text(c)),
                              )
                              .toList(),
                          onChanged: (c) => setState(() => _city = c ?? _city),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        TextFormField(
                          controller: _address,
                          decoration: const InputDecoration(
                            labelText: 'Address',
                            prefixIcon: Icon(Icons.place_outlined, size: 20),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        const _SectionLabel(
                          icon: Icons.contact_page_outlined,
                          label: 'Contact & ordering',
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 3,
                              child: TextFormField(
                                controller: _phone,
                                decoration: const InputDecoration(
                                  labelText: 'Phone',
                                  prefixIcon: Icon(Icons.call_outlined, size: 20),
                                ),
                              ),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              flex: 2,
                              child: TextFormField(
                                controller: _sortOrder,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  labelText: 'Sort order',
                                  hintText: '1 = first',
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        TextFormField(
                          controller: _website,
                          decoration: const InputDecoration(
                            labelText: 'Website',
                            prefixIcon: Icon(Icons.language, size: 20),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        const _SectionLabel(
                          icon: Icons.schedule_outlined,
                          label: 'Working hours',
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Row(
                          children: [
                            Expanded(
                              child: _TimePickerField(
                                label: 'Opens',
                                value: _opens,
                                onTap: _pickOpens,
                              ),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: _TimePickerField(
                                label: 'Closes',
                                value: _closes,
                                onTap: _pickCloses,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.md),
                        Container(
                          decoration: BoxDecoration(
                            color: AppColors.brand(
                              context,
                            ).withValues(alpha: _active ? 0.08 : 0),
                            borderRadius: BorderRadius.circular(AppRadius.md),
                            border: Border.all(color: AppColors.border(context)),
                          ),
                          child: SwitchListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.md,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(AppRadius.md),
                            ),
                            title: const Text(
                              'Active',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                            subtitle: Text(
                              _active
                                  ? 'Visible to players when booking'
                                  : 'Hidden from players',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            value: _active,
                            onChanged: (v) => setState(() => _active = v),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.xl,
                    0,
                    AppSpacing.xl,
                    AppSpacing.xl,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: FilledButton(
                          onPressed: _save,
                          child: const Text('Save'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Header bar for [_CourtEditorDialog] -- an icon badge + title/subtitle on
/// the left, an explicit close button on the right, so the dialog reads like
/// a proper panel instead of a form dropped on a blank sheet.
class _DialogTitleBar extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onClose;

  const _DialogTitleBar({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.brand(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
      ),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border(context))),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Icon(icon, color: accent, size: 20),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: Theme.of(context).hintColor),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 20),
            onPressed: onClose,
            tooltip: 'Close',
          ),
        ],
      ),
    );
  }
}

/// Small "SECTION LABEL" heading used to group the editor's fields, matching
/// the table header style ([AdminTableHeader]) used elsewhere in the panel.
class _SectionLabel extends StatelessWidget {
  final IconData icon;
  final String label;
  const _SectionLabel({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).hintColor;
    return Row(
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: AppSpacing.xxs),
        Text(
          label.toUpperCase(),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: color,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
          ),
        ),
      ],
    );
  }
}

/// Tap-to-open time picker styled like a [TextFormField] -- keeps working
/// hours restricted to actual time values instead of free text.
class _TimePickerField extends StatelessWidget {
  final String label;
  final TimeOfDay? value;
  final VoidCallback onTap;

  const _TimePickerField({
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.md),
      onTap: onTap,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: const Icon(Icons.schedule_outlined, size: 20),
        ),
        child: Text(
          value == null ? '--:--' : value!.format(context),
          style: value == null
              ? TextStyle(color: Theme.of(context).hintColor)
              : null,
        ),
      ),
    );
  }
}

/// Photo preview + upload control for the court editor. Tapping anywhere on
/// the box (or the pill button) opens the device's picker -- on web this is
/// the browser's native file input, which on a phone offers the gallery/
/// camera directly, and on desktop offers the filesystem.
class _CourtPhotoPicker extends StatelessWidget {
  final String imageUrl;
  final bool uploading;
  final VoidCallback onTap;

  const _CourtPhotoPicker({
    required this.imageUrl,
    required this.uploading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final hasImage = imageUrl.trim().isNotEmpty;
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: InkWell(
        onTap: uploading ? null : onTap,
        child: Container(
          height: 160,
          width: double.infinity,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            border: Border.all(color: AppColors.border(context)),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (hasImage)
                Image.network(
                  imageUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => _placeholder(context),
                )
              else
                _placeholder(context),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0),
                        Colors.black.withValues(alpha: hasImage ? 0.55 : 0.05),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: AppSpacing.sm,
                right: AppSpacing.sm,
                bottom: AppSpacing.sm,
                child: Row(
                  children: [
                    if (uploading)
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else
                      Icon(
                        Icons.upload_outlined,
                        size: 16,
                        color: hasImage ? Colors.white : AppColors.brand(context),
                      ),
                    const SizedBox(width: AppSpacing.xs),
                    Text(
                      uploading
                          ? 'Uploading...'
                          : (hasImage ? 'Change photo' : 'Upload photo'),
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontSize: 13,
                        color: hasImage
                            ? Colors.white
                            : AppColors.brand(context),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _placeholder(BuildContext context) {
    return Center(
      child: Icon(
        Icons.image_outlined,
        size: 36,
        color: Theme.of(context).hintColor,
      ),
    );
  }
}
