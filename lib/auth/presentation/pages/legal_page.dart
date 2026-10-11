import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:footrank/auth/data/legal_versions.dart';

/// The legal documents hosted at [LegalVersions.baseUrl].
enum LegalDocument {
  terms('Terms of Service', 'terms.html'),
  privacy('Privacy Policy', 'privacy.html');

  const LegalDocument(this.title, this.path);
  final String title;
  final String path;

  Uri get uri => Uri.parse('${LegalVersions.baseUrl}/$path');
}

/// Opens [doc] on its own screen inside the app.
///
/// The text is still served from the website, so it always matches the policy
/// linked in the App Store / Google Play listings and can be updated without
/// shipping a new app version.
Future<void> openLegalDocument(BuildContext context, LegalDocument doc) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => LegalPage(document: doc)),
  );
}

class LegalPage extends StatefulWidget {
  const LegalPage({super.key, required this.document});

  final LegalDocument document;

  @override
  State<LegalPage> createState() => _LegalPageState();
}

class _LegalPageState extends State<LegalPage> {
  late final WebViewController _controller;
  int _progress = 0;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (p) {
            if (mounted) setState(() => _progress = p);
          },
          onPageStarted: (_) {
            if (mounted) setState(() => _failed = false);
          },
          onWebResourceError: (error) {
            // Ignore failures of sub-resources; only the page itself matters.
            if (error.isForMainFrame ?? true) {
              if (mounted) setState(() => _failed = true);
            }
          },
          onNavigationRequest: (request) {
            // Keep the two legal pages in the app; send any other link
            // (e.g. the Commissioner's website) to the system browser.
            final url = Uri.tryParse(request.url);
            final isOurs = url != null &&
                request.url.startsWith(LegalVersions.baseUrl);
            if (isOurs || request.url == 'about:blank') {
              return NavigationDecision.navigate;
            }
            if (url != null) {
              launchUrl(url, mode: LaunchMode.externalApplication);
            }
            return NavigationDecision.prevent;
          },
        ),
      )
      ..loadRequest(widget.document.uri);
  }

  void _reload() {
    setState(() {
      _failed = false;
      _progress = 0;
    });
    _controller.loadRequest(widget.document.uri);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.document.title)),
      body: SafeArea(
        child: _failed
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.wifi_off_rounded, size: 40),
                      const SizedBox(height: 12),
                      Text(
                        'Could not load the ${widget.document.title}. '
                        'Check your connection and try again.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: _reload,
                        child: const Text('Try again'),
                      ),
                      TextButton(
                        onPressed: () => launchUrl(
                          widget.document.uri,
                          mode: LaunchMode.externalApplication,
                        ),
                        child: const Text('Open in browser'),
                      ),
                    ],
                  ),
                ),
              )
            : Stack(
                children: [
                  WebViewWidget(controller: _controller),
                  if (_progress < 100)
                    LinearProgressIndicator(value: _progress / 100),
                ],
              ),
      ),
    );
  }
}
