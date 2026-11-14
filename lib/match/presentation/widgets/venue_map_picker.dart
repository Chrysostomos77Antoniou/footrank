import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:footrank/core/config/maps_config.dart';
import 'package:footrank/core/constants/cities.dart';
import 'package:footrank/core/theme/app_colors.dart';
import 'package:footrank/match/data/places_service.dart';
import 'package:footrank/match/presentation/widgets/venue_widgets.dart';
import 'package:footrank/models/venue_location.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// What the map picker returns: the venue name for the text and where it is.
class VenuePick {
  final String name;
  final VenueLocation location;
  const VenuePick(this.name, this.location);
}

typedef VenuePickerFn = Future<VenuePick?> Function(
  BuildContext context, {
  required String city,
});

/// Opens the map picker. A top-level variable so widget tests can swap in a
/// fake instead of a real map; the app never reassigns it.
VenuePickerFn venuePicker = showVenueMapPicker;

Future<VenuePick?> showVenueMapPicker(
  BuildContext context, {
  required String city,
}) {
  return showModalBottomSheet<VenuePick>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    // The map needs to pan freely, so the sheet is closed with the X / back.
    enableDrag: false,
    builder: (_) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: FractionallySizedBox(
        heightFactor: 0.92,
        child: VenueMapPicker(city: city),
      ),
    ),
  );
}

LatLng _centerOf(String city) {
  final c = kCityCenters[city] ?? kCityCenters['Nicosia']!;
  return LatLng(c[0], c[1]);
}

/// Search + map sheet. Captains find the court by name, or drop a pin by
/// tapping the map when it isn't listed.
class VenueMapPicker extends StatefulWidget {
  final String city;

  @visibleForTesting
  final PlacesService? places;

  const VenueMapPicker({super.key, required this.city, this.places});

  @override
  State<VenueMapPicker> createState() => _VenueMapPickerState();
}

class _VenueMapPickerState extends State<VenueMapPicker> {
  late final PlacesService _places = widget.places ?? PlacesService();
  final _searchCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  GoogleMapController? _map;
  Timer? _debounce;
  int _searchSeq = 0;

  List<PlaceSuggestion> _suggestions = const [];
  bool _searching = false;
  bool _resolving = false;
  String? _searchError;

  LatLng? _pin;
  String? _placeId;
  String _googleName = '';
  bool _manual = false;
  String? _nameError;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    _nameCtrl.dispose();
    _map?.dispose();
    if (widget.places == null) _places.dispose();
    super.dispose();
  }

  void _onQueryChanged(String q) {
    _debounce?.cancel();
    if (q.trim().length < 2) {
      setState(() {
        _suggestions = const [];
        _searchError = null;
        _searching = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () => _search(q));
  }

  Future<void> _search(String q) async {
    final seq = ++_searchSeq;
    setState(() {
      _searching = true;
      _searchError = null;
    });
    final c = _centerOf(widget.city);
    try {
      final r = await _places.autocomplete(q,
          biasLat: c.latitude, biasLng: c.longitude);
      if (!mounted || seq != _searchSeq) return;
      setState(() {
        _suggestions = r;
        _searching = false;
        if (r.isEmpty) {
          _searchError = 'Nothing found. Tap the map to drop a pin instead.';
        }
      });
    } on PlacesException catch (e) {
      if (!mounted || seq != _searchSeq) return;
      setState(() {
        _suggestions = const [];
        _searching = false;
        _searchError = '${e.message} You can tap the map to drop a pin.';
      });
    }
  }

  Future<void> _choose(PlaceSuggestion s) async {
    FocusScope.of(context).unfocus();
    setState(() {
      _resolving = true;
      _searchError = null;
    });
    try {
      final coords = await _places.coordsOf(s.placeId);
      if (!mounted) return;
      final name = cleanVenueInput(s.name);
      final shortName = name.runes.length > kVenueMaxLength
          ? String.fromCharCodes(name.runes.take(kVenueMaxLength))
          : name;
      final at = LatLng(coords.lat, coords.lng);
      setState(() {
        _pin = at;
        _placeId = s.placeId;
        _googleName = shortName;
        _manual = false;
        _nameError = null;
        _suggestions = const [];
        _searchCtrl.text = shortName;
        _resolving = false;
      });
      await _map?.animateCamera(CameraUpdate.newLatLngZoom(at, 17));
    } on PlacesException catch (e) {
      if (!mounted) return;
      setState(() {
        _resolving = false;
        _searchError = e.message;
      });
    }
  }

  void _dropPin(LatLng at) {
    FocusScope.of(context).unfocus();
    final wasManual = _manual;
    setState(() {
      _pin = at;
      _placeId = null;
      _manual = true;
      _nameError = null;
      _suggestions = const [];
      // Moving a pin keeps the typed name; switching from a search result
      // starts with an empty name.
      if (!wasManual) _nameCtrl.clear();
    });
  }

  void _confirm() {
    final at = _pin;
    if (at == null) return;
    final name = _manual ? cleanVenueInput(_nameCtrl.text) : _googleName;
    final err = validateVenueInput(name);
    if (err != null) {
      setState(() => _nameError = err);
      return;
    }
    Navigator.pop(
      context,
      VenuePick(
        name,
        VenueLocation(
          placeId: _manual ? null : _placeId,
          lat: at.latitude,
          lng: at.longitude,
          source: _manual ? 'manual' : 'google',
        ),
      ),
    );
  }

  Widget _mapArea(BuildContext context) {
    if (!MapsConfig.supported) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'The map is only available in the FootRank phone app.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.muted(context)),
          ),
        ),
      );
    }
    final pin = _pin;
    return GoogleMap(
      initialCameraPosition:
          CameraPosition(target: _centerOf(widget.city), zoom: 12.5),
      onMapCreated: (c) => _map = c,
      onTap: _dropPin,
      onLongPress: _dropPin,
      markers: {
        if (pin != null) Marker(markerId: const MarkerId('venue'), position: pin),
      },
      myLocationButtonEnabled: false,
      zoomControlsEnabled: false,
      mapToolbarEnabled: false,
      compassEnabled: false,
      gestureRecognizers: {
        Factory<OneSequenceGestureRecognizer>(() => EagerGestureRecognizer()),
      },
    );
  }

  Widget _suggestionList(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(12),
      color: theme.colorScheme.surface,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 280),
        child: ListView.separated(
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          itemCount: _suggestions.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (_, i) {
            final s = _suggestions[i];
            return ListTile(
              dense: true,
              leading: Icon(Icons.place_outlined,
                  color: AppColors.brand(context)),
              title: Text(s.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: s.secondary.isEmpty
                  ? null
                  : Text(s.secondary,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
              onTap: () => _choose(s),
            );
          },
        ),
      ),
    );
  }

  Widget _bottomPanel(BuildContext context) {
    final theme = Theme.of(context);
    final muted = AppColors.muted(context);
    if (_pin == null) {
      return Text(
        'Search for the court above, or tap the map to drop a pin where it is.',
        style: theme.textTheme.bodySmall?.copyWith(color: muted, height: 1.4),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_manual)
          TextField(
            controller: _nameCtrl,
            maxLength: kVenueMaxLength,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              labelText: "Court's name",
              helperText: 'Pin dropped by hand. Type the name of the court.',
              errorText: _nameError,
              prefixIcon: const Icon(Icons.stadium_outlined),
            ),
            onChanged: (_) {
              if (_nameError != null) setState(() => _nameError = null);
            },
            onSubmitted: (_) => _confirm(),
          )
        else
          Row(
            children: [
              Icon(Icons.place, color: AppColors.brand(context)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _googleName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: _confirm,
          child: const Text('Use this place'),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 8, 8),
          child: Row(
            children: [
              Expanded(
                child: Text('Find the court',
                    style: theme.textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w800)),
              ),
              IconButton(
                tooltip: 'Close',
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            controller: _searchCtrl,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Search the court by name',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searching || _resolving
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : null,
            ),
            onChanged: _onQueryChanged,
          ),
        ),
        if (_searchError != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _searchError!,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: AppColors.muted(context)),
              ),
            ),
          ),
        const SizedBox(height: 8),
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(child: _mapArea(context)),
              if (_suggestions.isNotEmpty)
                Positioned(
                  left: 16,
                  right: 16,
                  top: 0,
                  child: _suggestionList(context),
                ),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: _bottomPanel(context),
          ),
        ),
      ],
    );
  }
}

/// Read-only form field that opens the map picker. Replaces the typed venue
/// box: the name always comes from the map (or a hand-dropped pin).
class VenuePickerField extends FormField<VenuePick> {
  VenuePickerField({
    super.key,
    required String? city,
    VenuePick? initialPick,
    ValueChanged<VenuePick?>? onChanged,
    bool required = true,
    String labelText = 'Venue',
    String hintText = 'Find the court on the map',
  }) : super(
          initialValue: initialPick,
          validator: (v) =>
              required && v == null ? 'Pick the venue on the map' : null,
          builder: (state) {
            final context = state.context;
            final pick = state.value;
            final muted = AppColors.muted(context);

            Future<void> open() async {
              if (city == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Select a city first')),
                );
                return;
              }
              final result = await venuePicker(context, city: city);
              if (result == null) return;
              state.didChange(result);
              onChanged?.call(result);
            }

            return InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: open,
              child: InputDecorator(
                isEmpty: false,
                decoration: InputDecoration(
                  labelText: labelText,
                  errorText: state.errorText,
                  prefixIcon: const Icon(Icons.stadium_outlined),
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (pick != null && !required)
                        IconButton(
                          tooltip: 'Remove venue',
                          icon: const Icon(Icons.close),
                          onPressed: () {
                            state.didChange(null);
                            onChanged?.call(null);
                          },
                        ),
                      Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: Icon(Icons.map_outlined,
                            color: AppColors.brand(context)),
                      ),
                    ],
                  ),
                ),
                child: Text(
                  pick?.name ?? hintText,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: pick == null
                      ? TextStyle(color: muted)
                      : const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            );
          },
        );
}

/// A small, non-interactive map of the venue. Tapping it runs [onTap] (open
/// directions). Shows nothing when there are no coordinates or no map support.
class VenueMiniMap extends StatelessWidget {
  final VenueLocation? location;
  final VoidCallback? onTap;
  final double height;

  const VenueMiniMap({
    super.key,
    required this.location,
    this.onTap,
    this.height = 150,
  });

  @override
  Widget build(BuildContext context) {
    final loc = location;
    if (loc == null || !loc.hasCoords || !MapsConfig.supported) {
      return const SizedBox.shrink();
    }
    final at = LatLng(loc.lat!, loc.lng!);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          height: height,
          child: Stack(
            children: [
              GoogleMap(
                initialCameraPosition: CameraPosition(target: at, zoom: 16),
                markers: {Marker(markerId: const MarkerId('venue'), position: at)},
                liteModeEnabled: defaultTargetPlatform == TargetPlatform.android,
                zoomControlsEnabled: false,
                zoomGesturesEnabled: false,
                scrollGesturesEnabled: false,
                rotateGesturesEnabled: false,
                tiltGesturesEnabled: false,
                myLocationButtonEnabled: false,
                mapToolbarEnabled: false,
                compassEnabled: false,
              ),
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onTap,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
