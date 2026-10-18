import 'package:flutter/material.dart';
import 'package:footrank/admin/data/admin_repository.dart';
import 'package:footrank/admin/models/admin_court_model.dart';
import 'package:footrank/admin/presentation/widgets/admin_widgets.dart';
import 'package:footrank/core/constants/cities.dart';
import 'package:footrank/core/theme/app_colors.dart';
import 'package:footrank/core/theme/app_tokens.dart';
import 'package:footrank/core/utils/error_text.dart';
import 'package:footrank/core/utils/motion.dart';
import 'package:footrank/core/widgets/brand_widgets.dart';
import 'package:footrank/core/widgets/premium.dart';
import 'package:image_picker/image_picker.dart';
import 'package:footrank/core/widgets/feedback.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AdminCourtsPage extends StatefulWidget {
  /// Injected in widget tests; production uses the real repository.
  final AdminRepository? repo;

  const AdminCourtsPage({super.key, this.repo});

  @override
  State<AdminCourtsPage> createState() => _AdminCourtsPageState();
}

class _AdminCourtsPageState extends State<AdminCourtsPage> {
  late final AdminRepository _repo = widget.repo ?? AdminRepository();
  List<AdminCourtModel>? _courts;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final courts = await _repo.fetchAllCourts();
      if (!mounted) return;
      setState(() {
        _courts = courts;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    }
  }

  void _replace(AdminCourtModel court) {
    final current = _courts;
    if (current == null) return;
    setState(() {
      _courts = [for (final c in current) c.id == court.id ? court : c];
    });
  }

  Future<void> _openEditor([AdminCourtModel? court]) async {
    final result = await showAdminDialog<AdminCourtModel>(
      context: context,
      builder: (_) => _CourtEditorDialog(court: court),
    );
    if (result == null) return;
    try {
      await _repo.upsertCourt(result, isNew: court == null);
      await _load();
    } catch (e) {
      if (mounted) {
        showError(context, e);
      }
    }
  }

  /// Optimistic: the switch moves the instant it is tapped, and snaps back
  /// (with an error) only if the save fails -- waiting on the network before
  /// the control responds makes it feel broken.
  Future<void> _toggleActive(AdminCourtModel court) async {
    final next = court.copyWith(active: !court.active);
    _replace(next);
    try {
      await _repo.upsertCourt(next);
    } catch (e) {
      _replace(court);
      if (mounted) {
        showError(context, e);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final courts = _courts;
    final Widget body;
    final String bodyKey;
    if (courts != null) {
      bodyKey = 'content';
      body = AdminCourtsView(
        courts: courts,
        onEdit: _openEditor,
        onToggleActive: _toggleActive,
      );
    } else if (_error != null) {
      bodyKey = 'error';
      body = Align(
        alignment: Alignment.topCenter,
        child: AdminEmptyState(
          icon: Icons.error_outline,
          message: friendlyError(_error!),
          actionLabel: 'Try again',
          onAction: () {
            setState(() => _error = null);
            _load();
          },
        ),
      );
    } else {
      bodyKey = 'loading';
      body = const AdminTableSkeleton();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AdminHeader(
          title: 'Courts',
          subtitle: 'Every bookable court, across every city.',
          action: AdminPressScale(
            child: FilledButton.icon(
              onPressed: () => _openEditor(),
              // The app's global FilledButtonThemeData sets minimumSize to
              // Size.fromHeight(52) for the mobile app's full-width buttons --
              // that's Size(double.infinity, 52). Left as-is here, this button
              // (a sibling of Expanded in a Row) claims effectively all the
              // header's width, squeezing the title down to a sliver.
              style: FilledButton.styleFrom(
                minimumSize: Size.zero,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
              icon: const Icon(Icons.add, size: 18),
              label: Text(isAdminPhone(context) ? 'Add' : 'Add court'),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Expanded(
          child: AsyncSwitcher(switcherKey: bodyKey, child: body),
        ),
      ],
    );
  }
}

/// Columns the admin can show or hide in the courts table. The court name
/// itself is always shown. Declaration order is display order.
enum CourtColumn {
  city('City', 2),
  address('Address', 3),
  phone('Phone', 2),
  hours('Hours', 3),
  active('Active', 0, 56);

  const CourtColumn(this.label, this.flex, [this.fixedWidth]);
  final String label;
  final int flex;
  final double? fixedWidth;
}

enum CourtStatusFilter { all, active, inactive }

const _kColumnsPrefsKey = 'admin_courts_columns';
const _kDefaultColumns = {
  CourtColumn.city,
  CourtColumn.hours,
  CourtColumn.active,
};

/// The courts filter bar + table. Public (and free of any network code) so
/// it can be exercised in widget tests with fake data.
class AdminCourtsView extends StatefulWidget {
  final List<AdminCourtModel> courts;
  final ValueChanged<AdminCourtModel> onEdit;
  final ValueChanged<AdminCourtModel> onToggleActive;

  const AdminCourtsView({
    super.key,
    required this.courts,
    required this.onEdit,
    required this.onToggleActive,
  });

  @override
  State<AdminCourtsView> createState() => _AdminCourtsViewState();
}

class _AdminCourtsViewState extends State<AdminCourtsView> {
  CourtStatusFilter _status = CourtStatusFilter.all;
  String? _city;
  String _query = '';
  final _search = TextEditingController();
  Set<CourtColumn> _columns = {..._kDefaultColumns};

  @override
  void initState() {
    super.initState();
    _loadColumns();
  }

  // Which columns are shown is a personal view preference, so it survives
  // reloads. Best-effort: if storage is unavailable the defaults stand.
  Future<void> _loadColumns() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getStringList(_kColumnsPrefsKey);
      if (saved == null || !mounted) return;
      setState(() {
        _columns = CourtColumn.values
            .where((c) => saved.contains(c.name))
            .toSet();
      });
    } catch (_) {}
  }

  Future<void> _saveColumns() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
        _kColumnsPrefsKey,
        _columns.map((c) => c.name).toList(),
      );
    } catch (_) {}
  }

  void _toggleColumn(CourtColumn column) {
    setState(() {
      _columns = _columns.contains(column)
          ? ({..._columns}..remove(column))
          : ({..._columns}..add(column));
    });
    _saveColumns();
  }

  void _clearFilters() {
    _search.clear();
    setState(() {
      _status = CourtStatusFilter.all;
      _city = null;
      _query = '';
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// A court is "complete" once players have everything they need to
  /// actually go there: opening hours, a phone number and a photo.
  static bool _isComplete(AdminCourtModel c) =>
      (c.hours?.trim().isNotEmpty ?? false) &&
      (c.phone?.trim().isNotEmpty ?? false) &&
      (c.imageUrl?.trim().isNotEmpty ?? false);

  @override
  Widget build(BuildContext context) {
    final all = widget.courts;

    // City -> number of courts. A city that vanished (its last court was
    // edited to another city) quietly stops filtering.
    final cityCounts = <String, int>{};
    for (final c in all) {
      cityCounts[c.city] = (cityCounts[c.city] ?? 0) + 1;
    }
    final cities = cityCounts.keys.toList()..sort();
    final city = cityCounts.containsKey(_city) ? _city : null;

    // Status counts reflect the chosen city, so a chip never promises
    // courts the city filter has already excluded.
    final inCity = city == null
        ? all
        : all.where((c) => c.city == city).toList();
    final activeCount = inCity.where((c) => c.active).length;
    final byStatus = switch (_status) {
      CourtStatusFilter.all => inCity,
      CourtStatusFilter.active => inCity.where((c) => c.active).toList(),
      CourtStatusFilter.inactive => inCity.where((c) => !c.active).toList(),
    };
    final q = _query.trim().toLowerCase();
    final shown = q.isEmpty
        ? byStatus
        : byStatus
              .where(
                (c) =>
                    c.name.toLowerCase().contains(q) ||
                    c.city.toLowerCase().contains(q) ||
                    (c.address?.toLowerCase().contains(q) ?? false),
              )
              .toList();
    final isFiltered =
        city != null || _status != CourtStatusFilter.all || q.isNotEmpty;
    final completeCount = all.where(_isComplete).length;

    final columns = CourtColumn.values.where(_columns.contains).toList();

    final phone = isAdminPhone(context);
    final searchField = AdminSearchField(
      controller: _search,
      hint: 'Search courts…',
      onChanged: (v) => setState(() => _query = v),
    );
    final statusChips = <Widget>[
      AdminFilterChip(
        label: 'All',
        count: inCity.length,
        selected: _status == CourtStatusFilter.all,
        onTap: () => setState(() => _status = CourtStatusFilter.all),
      ),
      AdminFilterChip(
        label: 'Active',
        count: activeCount,
        selected: _status == CourtStatusFilter.active,
        onTap: () => setState(() => _status = CourtStatusFilter.active),
      ),
      AdminFilterChip(
        label: 'Inactive',
        count: inCity.length - activeCount,
        selected: _status == CourtStatusFilter.inactive,
        onTap: () => setState(() => _status = CourtStatusFilter.inactive),
      ),
    ];
    final divider = Container(
      width: 1,
      height: 18,
      margin: const EdgeInsets.symmetric(horizontal: 2),
      color: AppColors.inputBorder(context),
    );
    final cityPopover = AdminPopover(
      triggerBuilder: (context, toggle, open) => AdminFilterChip(
        icon: Icons.location_city_outlined,
        label: city ?? 'All cities',
        selected: city != null,
        caret: true,
        open: open,
        onTap: toggle,
      ),
      menuBuilder: (context, close) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AdminMenuItem(
            label: 'All cities',
            hint: '${all.length}',
            checked: city == null,
            onTap: () {
              setState(() => _city = null);
              close();
            },
          ),
          for (final name in cities)
            AdminMenuItem(
              label: name,
              hint: '${cityCounts[name]}',
              checked: city == name,
              onTap: () {
                setState(() => _city = name);
                close();
              },
            ),
        ],
      ),
    );
    final columnsPopover = AdminPopover(
      alignEnd: true,
      width: 200,
      triggerBuilder: (context, toggle, open) => AdminFilterChip(
        icon: Icons.view_column_outlined,
        label: 'Columns',
        selected: false,
        caret: true,
        open: open,
        onTap: toggle,
      ),
      // Stays open while toggling so several columns can be changed in one go.
      menuBuilder: (context, close) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
            child: Text(
              'SHOW COLUMNS',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).hintColor,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
              ),
            ),
          ),
          for (final c in CourtColumn.values)
            AdminMenuItem(
              label: c.label,
              checked: _columns.contains(c),
              onTap: () => _toggleColumn(c),
            ),
        ],
      ),
    );

    final brand = AppColors.brand(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AdminGrid(
          phoneScroll: true,
          minTileWidth: 210,
          count: 4,
          itemBuilder: (i, w) => switch (i) {
            0 => AdminMiniStat(
              index: 0,
              icon: Icons.place_rounded,
              value: '${all.length}',
              label: 'Courts on file',
              color: brand,
            ),
            1 => AdminMiniStat(
              index: 1,
              icon: Icons.visibility_rounded,
              value: '${all.where((c) => c.active).length}',
              label: 'Live for players',
              color: AppColors.success,
            ),
            2 => AdminMiniStat(
              index: 2,
              icon: Icons.fact_check_rounded,
              value: '$completeCount of ${all.length}',
              label: 'Profiles complete',
              color: AppColors.gold,
              progress: all.isEmpty ? 0 : completeCount / all.length,
            ),
            _ => AdminMiniStat(
              index: 3,
              icon: Icons.location_city_rounded,
              value: '${cityCounts.length}',
              label: cityCounts.length == 1 ? 'City covered' : 'Cities covered',
              color: brand,
            ),
          },
        ),
        const SizedBox(height: AppSpacing.md),
        if (phone)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              searchField,
              const SizedBox(height: AppSpacing.xs),
              AdminFilterBar(children: [...statusChips, divider, cityPopover]),
            ],
          )
        else
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Wrap(
                  spacing: AppSpacing.xs,
                  runSpacing: AppSpacing.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SizedBox(width: 250, child: searchField),
                    ...statusChips,
                    divider,
                    cityPopover,
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              columnsPopover,
            ],
          ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Text(
              isFiltered
                  ? 'Showing ${shown.length} of ${all.length} courts'
                  : '${all.length} ${all.length == 1 ? 'court' : 'courts'}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).hintColor,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            if (isFiltered) ...[
              const SizedBox(width: AppSpacing.xs),
              AdminPressScale(
                child: TextButton(
                  onPressed: _clearFilters,
                  style: TextButton.styleFrom(
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    foregroundColor: AppColors.brand(context),
                    textStyle: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  child: const Text('Clear filters'),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Expanded(
          child: shown.isEmpty
              ? Align(
                  alignment: Alignment.topCenter,
                  child: AdminEmptyState(
                    icon: Icons.place_outlined,
                    message: all.isEmpty
                        ? 'No courts yet -- add the first one.'
                        : 'No courts match these filters.',
                    actionLabel: all.isEmpty ? null : 'Clear filters',
                    onAction: all.isEmpty ? null : _clearFilters,
                  ),
                )
              : FadeSlideIn(
                  // GlassCard doesn't force a width, so under the loose
                  // constraints this sits inside it shrinks to fit its
                  // content and then gets left where the Column places it --
                  // forcing full width here guarantees it always spans the
                  // page instead of floating narrower than expected.
                  child: SizedBox(
                    width: double.infinity,
                    child: GlassCard(
                      padding: EdgeInsets.all(
                        phone ? AppSpacing.xxs : AppSpacing.sm,
                      ),
                      child: AdminScrollableTable(
                        child: Column(
                          children: [
                            if (!phone)
                              AdminTableHeader(
                                columns: [
                                  'Court',
                                  for (final c in columns) c.label,
                                  '',
                                ],
                                flex: [3, for (final c in columns) c.flex, 0],
                                fixedWidths: [
                                  null,
                                  for (final c in columns) c.fixedWidth,
                                  44,
                                ],
                              ),
                            for (var i = 0; i < shown.length; i++)
                              // Only the first screenful cascades in, once
                              // per court per session -- re-filtering is a
                              // frequent action and must feel instant.
                              FadeSlideIn(
                                key: ValueKey(shown[i].id),
                                delay: AppMotion.staggerFor(i),
                                animateOnceId: 'admin-court-${shown[i].id}',
                                offsetY: 6,
                                child: phone
                                    ? _CourtCard(
                                        court: shown[i],
                                        onEdit: () => widget.onEdit(shown[i]),
                                        onToggleActive: () =>
                                            widget.onToggleActive(shown[i]),
                                      )
                                    : _CourtRow(
                                        court: shown[i],
                                        columns: columns,
                                        onEdit: () => widget.onEdit(shown[i]),
                                        onToggleActive: () =>
                                            widget.onToggleActive(shown[i]),
                                      ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}

/// Phone version of a court row: two lines of identity on the left, the
/// live switch on the right. The whole card opens the editor.
class _CourtCard extends StatelessWidget {
  final AdminCourtModel court;
  final VoidCallback onEdit;
  final VoidCallback onToggleActive;

  const _CourtCard({
    required this.court,
    required this.onEdit,
    required this.onToggleActive,
  });

  @override
  Widget build(BuildContext context) {
    final hint = Theme.of(context).hintColor;
    final detail = [
      court.city,
      if (court.hours?.trim().isNotEmpty ?? false) court.hours!.trim(),
    ].join(' · ');
    return AdminRowTile(
      onTap: onEdit,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          GradientAvatar(
            name: court.name,
            imageUrl: court.imageUrl,
            radius: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  court.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.5, color: hint),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Semantics(
            label: court.active ? 'Active' : 'Inactive',
            child: Switch(
              value: court.active,
              onChanged: (_) => onToggleActive(),
            ),
          ),
        ],
      ),
    );
  }
}

class _CourtRow extends StatelessWidget {
  final AdminCourtModel court;
  final List<CourtColumn> columns;
  final VoidCallback onEdit;
  final VoidCallback onToggleActive;

  const _CourtRow({
    required this.court,
    required this.columns,
    required this.onEdit,
    required this.onToggleActive,
  });

  Widget _textCell(BuildContext context, CourtColumn column, String? text) {
    final muted = column != CourtColumn.city;
    return Expanded(
      flex: column.flex,
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          (text == null || text.isEmpty) ? '—' : text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: muted ? TextStyle(color: Theme.of(context).hintColor) : null,
        ),
      ),
    );
  }

  Widget _cell(BuildContext context, CourtColumn column) {
    switch (column) {
      case CourtColumn.city:
        return _textCell(context, column, court.city);
      case CourtColumn.address:
        return _textCell(context, column, court.address);
      case CourtColumn.phone:
        return _textCell(context, column, court.phone);
      case CourtColumn.hours:
        return _textCell(context, column, court.hours);
      case CourtColumn.active:
        // Fixed-width trailing column (not flex-proportional) so the
        // switch sits in the same pixel position on every row, instead of
        // drifting with each row's text length.
        return SizedBox(
          width: column.fixedWidth,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Tooltip(
              message: court.active
                  ? 'Active — tap to deactivate'
                  : 'Inactive — tap to activate',
              child: Switch(
                value: court.active,
                onChanged: (_) => onToggleActive(),
              ),
            ),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdminRowTile(
      onTap: onEdit,
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
          for (final c in columns) _cell(context, c),
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
                  icon: isNew
                      ? Icons.add_location_alt_outlined
                      : Icons.edit_location_alt_outlined,
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
                            style: Theme.of(context).textTheme.labelMedium
                                ?.copyWith(color: AppColors.danger),
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
                          initialValue: _city,
                          decoration: const InputDecoration(
                            labelText: 'City',
                            prefixIcon: Icon(Icons.location_city, size: 20),
                          ),
                          items: kCities
                              .map(
                                (c) =>
                                    DropdownMenuItem(value: c, child: Text(c)),
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
                                  prefixIcon: Icon(
                                    Icons.call_outlined,
                                    size: 20,
                                  ),
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
                            border: Border.all(
                              color: AppColors.border(context),
                            ),
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
                        child: AdminPressScale(
                          child: OutlinedButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text('Cancel'),
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: AdminPressScale(
                          child: FilledButton(
                            onPressed: _save,
                            child: const Text('Save'),
                          ),
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
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).hintColor,
                  ),
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
                        color: hasImage
                            ? Colors.white
                            : AppColors.brand(context),
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
