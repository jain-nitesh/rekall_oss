import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../utils/constants.dart';

/// In-app browser with custom ReKall toolbar
class InAppBrowser extends StatefulWidget {
  final String url;
  final String title;

  const InAppBrowser({
    super.key,
    required this.url,
    required this.title,
  });

  @override
  State<InAppBrowser> createState() => _InAppBrowserState();
}

class _InAppBrowserState extends State<InAppBrowser> {
  InAppWebViewController? _webViewController;
  String _currentUrl = '';
  String _currentTitle = '';
  bool _isLoading = true;
  double _progress = 0.0;
  bool _canGoBack = false;
  bool _canGoForward = false;

  @override
  void initState() {
    super.initState();
    _currentUrl = widget.url;
    _currentTitle = widget.title;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppConstants.deepCharcoal,
        foregroundColor: AppConstants.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _currentTitle.isEmpty ? 'Loading...' : _currentTitle,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppConstants.white,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              _getDomain(_currentUrl),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w400,
                color: AppConstants.white.withValues(alpha: 0.7),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(
              Icons.arrow_back,
              color: _canGoBack
                  ? AppConstants.white
                  : AppConstants.white.withValues(alpha: 0.3),
            ),
            onPressed: _canGoBack ? () => _webViewController?.goBack() : null,
          ),
          IconButton(
            icon: Icon(
              Icons.arrow_forward,
              color: _canGoForward
                  ? AppConstants.white
                  : AppConstants.white.withValues(alpha: 0.3),
            ),
            onPressed:
                _canGoForward ? () => _webViewController?.goForward() : null,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _webViewController?.reload(),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: AppConstants.white),
            onSelected: _handleMenuAction,
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'copy',
                child: Row(
                  children: [
                    Icon(Icons.copy, size: 20),
                    SizedBox(width: 12),
                    Text('Copy Link'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'share',
                child: Row(
                  children: [
                    Icon(Icons.share, size: 20),
                    SizedBox(width: 12),
                    Text('Share'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'external',
                child: Row(
                  children: [
                    Icon(Icons.open_in_new, size: 20),
                    SizedBox(width: 12),
                    Text('Open in Browser'),
                  ],
                ),
              ),
            ],
          ),
        ],
        bottom: _isLoading
            ? PreferredSize(
                preferredSize: const Size.fromHeight(3),
                child: LinearProgressIndicator(
                  value: _progress,
                  backgroundColor: AppConstants.white.withValues(alpha: 0.2),
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    AppConstants.electricIndigo,
                  ),
                  minHeight: 3,
                ),
              )
            : null,
      ),
      body: InAppWebView(
        initialUrlRequest: URLRequest(
          url: WebUri(widget.url),
        ),
        initialSettings: InAppWebViewSettings(
          useShouldOverrideUrlLoading: true,
          mediaPlaybackRequiresUserGesture: false,
          allowsInlineMediaPlayback: true,
          useOnLoadResource: true,
          supportZoom: true,
          javaScriptEnabled: true,
          domStorageEnabled: true,
        ),
        onWebViewCreated: (controller) {
          _webViewController = controller;
        },
        onLoadStart: (controller, url) {
          setState(() {
            _isLoading = true;
            if (url != null) {
              _currentUrl = url.toString();
            }
          });
        },
        onLoadStop: (controller, url) async {
          setState(() {
            _isLoading = false;
          });

          if (url != null) {
            setState(() {
              _currentUrl = url.toString();
            });
          }

          // Get page title
          final title = await controller.getTitle();
          if (title != null) {
            setState(() {
              _currentTitle = title;
            });
          }

          // Update navigation state
          final canGoBack = await controller.canGoBack();
          final canGoForward = await controller.canGoForward();
          setState(() {
            _canGoBack = canGoBack;
            _canGoForward = canGoForward;
          });
        },
        onProgressChanged: (controller, progress) {
          setState(() {
            _progress = progress / 100;
          });
        },
        onTitleChanged: (controller, title) {
          if (title != null) {
            setState(() {
              _currentTitle = title;
            });
          }
        },
      ),
    );
  }

  String _getDomain(String url) {
    try {
      final uri = Uri.parse(url);
      return uri.host;
    } catch (e) {
      return url;
    }
  }

  void _handleMenuAction(String action) async {
    switch (action) {
      case 'copy':
        await Clipboard.setData(ClipboardData(text: _currentUrl));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Link copied to clipboard'),
              duration: Duration(seconds: 2),
            ),
          );
        }
        break;
      case 'share':
        await SharePlus.instance.share(ShareParams(text: '$_currentTitle\n$_currentUrl'));
        break;
      case 'external':
        final uri = Uri.parse(_currentUrl);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
        break;
    }
  }
}
