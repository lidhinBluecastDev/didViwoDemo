import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:google_fonts/google_fonts.dart';

import '../app_config.dart';
import '../did_webrtc_service.dart';
import '../theme/app_theme.dart';
import '../theme/phone_layout.dart';
import '../widgets/atmosphere.dart';
import '../widgets/brand_logo.dart';
import 'classroom_screen.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  bool _connecting = false;
  bool _loadingUrl = true;
  String _baseUrl = AppConfig.defaultBaseUrl;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadBaseUrl();
  }

  Future<void> _loadBaseUrl() async {
    final url = await AppConfig.loadBaseUrl();
    if (!mounted) return;
    setState(() {
      _baseUrl = url;
      _loadingUrl = false;
    });
  }

  Future<void> _openSettings() async {
    final saved = await showDialog<String>(
      context: context,
      builder: (context) => _ColabUrlDialog(initialUrl: _baseUrl),
    );

    if (saved == null || !mounted) return;

    await AppConfig.saveBaseUrl(saved);
    if (!mounted) return;
    final normalized = await AppConfig.loadBaseUrl();
    if (!mounted) return;
    setState(() {
      _baseUrl = normalized;
      _error = null;
    });
  }

  Future<void> _talkToTeacher() async {
    if (_connecting || _loadingUrl) return;
    setState(() {
      _connecting = true;
      _error = null;
    });

    final renderer = RTCVideoRenderer();

    try {
      await renderer.initialize();
      final service = DidWebRtcService(baseUrl: _baseUrl, renderer: renderer);

      if (!mounted) {
        await service.dispose();
        await renderer.dispose();
        return;
      }

      // Open the classroom first so RTCVideoView exists, then connect.
      // Setting srcObject before the native view mounts often yields a black
      // screen (0x0 frames) on Android devices.
      await Navigator.of(context).pushReplacement(
        PageRouteBuilder<void>(
          transitionDuration: const Duration(milliseconds: 650),
          pageBuilder: (context, animation, secondaryAnimation) {
            return FadeTransition(
              opacity: animation,
              child: ClassroomScreen(service: service, connectOnStart: true),
            );
          },
        ),
      );
    } catch (error) {
      await renderer.dispose();
      if (!mounted) return;
      setState(() {
        _connecting = false;
        _error = 'Could not start class. Please try again.';
      });
      debugPrint('Connect error: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final layout = PhoneLayout.of(context);
    final compact = layout.isCompactHeight;

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.network(
            'https://images.unsplash.com/photo-1509062522246-3755977927d7?auto=format&fit=crop&w=1600&q=80',
            fit: BoxFit.cover,
            alignment: Alignment.center,
            errorBuilder: (context, error, stackTrace) {
              return const ClassroomBackdrop();
            },
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x8812323A),
                  Color(0x4412323A),
                  Color(0xCC0E4A56),
                  Color(0xF50E4A56),
                ],
                stops: [0, 0.32, 0.68, 1],
              ),
            ),
          ),
          // Soft black veil at the top so the logo wordmark stays readable.
          const Align(
            alignment: Alignment.topCenter,
            child: IgnorePointer(
              child: SizedBox(
                height: 160,
                width: double.infinity,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color(0xCC000000),
                        Color(0x66000000),
                        Color(0x00000000),
                      ],
                      stops: [0, 0.55, 1],
                    ),
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            minimum: const EdgeInsets.only(bottom: 8),
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                layout.horizontalPadding,
                compact ? 12 : 20,
                layout.horizontalPadding,
                compact ? 12 : 20,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FadeSlideIn(
                    child: Row(
                      children: [
                        Expanded(
                          child: BrandLogo(
                            height: layout.isPhone ? 52 : 64,
                            width: double.infinity,
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          tooltip: 'Server settings',
                          onPressed: _connecting ? null : _openSettings,
                          style: IconButton.styleFrom(
                            foregroundColor: Colors.white,
                            backgroundColor: Colors.white.withValues(
                              alpha: 0.14,
                            ),
                            minimumSize: const Size(44, 44),
                          ),
                          icon: const Icon(Icons.settings_rounded),
                        ),
                      ],
                    ),
                  ),
                  Spacer(flex: compact ? 1 : 2),
                  FadeSlideIn(
                    delay: const Duration(milliseconds: 120),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 520),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Meet your\nteacher',
                            style: GoogleFonts.fraunces(
                              fontSize: layout.headlineSize(
                                compact ? 30 : 34,
                                48,
                              ),
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                              height: 1.1,
                              letterSpacing: -0.8,
                            ),
                          ),
                          SizedBox(height: compact ? 12 : 16),
                          Text(
                            'Ask questions out loud and learn together — '
                            'just like sitting in class.',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: layout.isPhone ? 16 : 17,
                              height: 1.45,
                              color: Colors.white.withValues(alpha: 0.88),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Spacer(flex: compact ? 2 : 3),
                  FadeSlideIn(
                    delay: const Duration(milliseconds: 240),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _TalkButton(
                          busy: _connecting || _loadingUrl,
                          fullWidth: layout.isPhone,
                          onPressed: _talkToTeacher,
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 14),
                          Text(
                            _error!,
                            style: GoogleFonts.plusJakartaSans(
                              color: AppColors.chalk,
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ColabUrlDialog extends StatefulWidget {
  const _ColabUrlDialog({required this.initialUrl});

  final String initialUrl;

  @override
  State<_ColabUrlDialog> createState() => _ColabUrlDialogState();
}

class _ColabUrlDialogState extends State<_ColabUrlDialog> {
  late final TextEditingController _controller;
  String? _fieldError;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialUrl);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final error = AppConfig.validateBaseUrl(_controller.text);
    if (error != null) {
      setState(() => _fieldError = error);
      return;
    }
    Navigator.of(context).pop(_controller.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.viewInsetsOf(context);

    return AnimatedPadding(
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: viewInsets.bottom),
      child: AlertDialog(
        backgroundColor: const Color(0xFF12323A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(
          'Colab server URL',
          style: GoogleFonts.plusJakartaSans(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 18,
          ),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Paste your current ngrok / Colab backend URL. '
                'It is saved on this device.',
                style: GoogleFonts.plusJakartaSans(
                  color: Colors.white70,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _controller,
                autofocus: true,
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.done,
                style: GoogleFonts.plusJakartaSans(
                  color: Colors.white,
                  fontSize: 14,
                ),
                decoration: InputDecoration(
                  hintText: 'https://xxxx.ngrok-free.app',
                  hintStyle: GoogleFonts.plusJakartaSans(
                    color: Colors.white38,
                    fontSize: 14,
                  ),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.08),
                  errorText: _fieldError,
                  errorStyle: GoogleFonts.plusJakartaSans(
                    color: AppColors.chalk,
                    fontSize: 12,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                ),
                onSubmitted: (_) => _submit(),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              'Cancel',
              style: GoogleFonts.plusJakartaSans(
                color: Colors.white70,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          TextButton(
            onPressed: _submit,
            child: Text(
              'Save',
              style: GoogleFonts.plusJakartaSans(
                color: AppColors.chalk,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TalkButton extends StatelessWidget {
  const _TalkButton({
    required this.busy,
    required this.onPressed,
    this.fullWidth = false,
  });

  final bool busy;
  final VoidCallback onPressed;
  final bool fullWidth;

  @override
  Widget build(BuildContext context) {
    final button = Material(
      color: AppColors.chalk,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: busy ? null : onPressed,
        borderRadius: BorderRadius.circular(18),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
            child: Row(
              mainAxisAlignment: fullWidth
                  ? MainAxisAlignment.center
                  : MainAxisAlignment.start,
              mainAxisSize: fullWidth ? MainAxisSize.max : MainAxisSize.min,
              children: [
                if (busy) ...[
                  const ConnectingDots(color: AppColors.ink),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      'Opening classroom…',
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.plusJakartaSans(
                        color: AppColors.ink,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ] else ...[
                  Flexible(
                    child: Text(
                      'Talk to teacher',
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.plusJakartaSans(
                        color: AppColors.ink,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    width: 36,
                    height: 36,
                    decoration: const BoxDecoration(
                      color: AppColors.deepTeal,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.arrow_forward_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );

    if (!fullWidth) return button;
    return SizedBox(width: double.infinity, child: button);
  }
}
