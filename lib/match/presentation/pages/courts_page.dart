import 'package:footrank/core/widgets/back_chip.dart';
import 'package:flutter/material.dart';
import 'package:footrank/core/theme/app_colors.dart';
import 'package:footrank/core/utils/maps_launcher.dart';
import 'package:footrank/core/widgets/async_views.dart';
import 'package:footrank/core/widgets/court_image_preview.dart';
import 'package:footrank/core/widgets/premium.dart';
import 'package:footrank/match/data/court_repository.dart';
import 'package:footrank/models/court_model.dart';
import 'package:footrank/core/theme/theme_controller.dart';
import 'package:footrank/core/theme/app_tokens.dart';

/// Read-only directory of every active court, grouped by city — reachable
/// from Home so anyone can see where matches can be played before ever
/// creating one (the ranked-pick flow itself lives on Create Match).
class CourtsPage extends StatefulWidget {
  const CourtsPage({super.key});

  @override
  State<CourtsPage> createState() => _CourtsPageState();
}

class _CourtsPageState extends State<CourtsPage>
    with ThemeRepaintMixin {
  final _repo = CourtRepository();
  late Future<List<CourtModel>> _future;

  @override
  void initState() {
    super.initState();
    _future = _repo.fetchAllCourts();
  }

  void _retry() => setState(() {
    _future = _repo.fetchAllCourts();
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 68,
        leadingWidth: kBackChipLeadingWidth,
        titleSpacing: 0,
        leading: Navigator.of(context).canPop() ? const BackChip() : null,
        title: const Text('Courts'),
      ),
      body: AmbientBackground(
        child: SafeArea(
          child: FutureBuilder<List<CourtModel>>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const SkeletonList();
              }
              if (snapshot.hasError) {
                return ErrorView(
                  message: 'Could not load courts',
                  onRetry: _retry,
                );
              }
              final courts = snapshot.data ?? [];
              if (courts.isEmpty) {
                return const EmptyView(
                  icon: Icons.sports_soccer,
                  title: 'No courts listed yet',
                );
              }

              final byCity = <String, List<CourtModel>>{};
              for (final c in courts) {
                (byCity[c.city] ??= []).add(c);
              }
              final cities = byCity.keys.toList()..sort();

              // One running index across headers and rows alike, fed through
              // the capped helper. The previous `delay += 40` accumulator was
              // uncapped, so a list of 6 cities x 5 courts left the last row
              // waiting well over a second before it began to appear.
              var i = 0;
              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [
                  for (final city in cities) ...[
                    FadeSlideIn(
                      delay: AppMotion.staggerFor(i++),
                      animateOnceId: 'city:$city',
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(4, 16, 4, 10),
                        child: Text(
                          city,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.17,
                              ),
                        ),
                      ),
                    ),
                    for (final c in byCity[city]!) ...[
                      FadeSlideIn(
                        delay: AppMotion.staggerFor(i++),
                        animateOnceId: c.id,
                        child: _CourtRow(court: c),
                      ),
                      const SizedBox(height: 10),
                    ],
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _CourtRow extends StatelessWidget {
  final CourtModel court;
  const _CourtRow({required this.court});

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              onTap: () => showCourtImagePreview(
                context,
                name: court.name,
                imageUrl: court.imageUrl,
              ),
              child: court.imageUrl != null
                  ? Image.network(
                      court.imageUrl!,
                      width: 72,
                      height: 72,
                      fit: BoxFit.cover,
                      loadingBuilder: (context, child, progress) =>
                          progress == null ? child : _placeholder(context),
                      errorBuilder: (_, __, ___) => _placeholder(context),
                    )
                  : _placeholder(context),
            ),
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
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                ),
                if (court.address != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    court.address!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: AppColors.muted(context),
                        ),
                  ),
                ],
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 6,
                    ),
                    minimumSize: const Size(0, 44),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    side: Theme.of(context).brightness == Brightness.dark
                        ? BorderSide(
                            color: Colors.white.withValues(alpha: 0.24))
                        : const BorderSide(
                            color: AppColors.limeDeep, width: 1.5),
                    textStyle: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                  onPressed: () => openInMaps(
                    name: court.name,
                    address: court.address,
                    city: court.city,
                  ),
                  icon: Icon(Icons.near_me_outlined,
                      size: 18, color: AppColors.brand(context)),
                  label: const Text('Get Directions'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _placeholder(BuildContext context) => Container(
    width: 72,
    height: 72,
    color: AppColors.chip(context),
    child: Icon(
      Icons.sports_soccer,
      size: 28,
      color: AppColors.brand(context).withValues(alpha: 0.75),
    ),
  );
}
