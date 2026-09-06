import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../did_webrtc_service.dart';
import '../theme/app_theme.dart';
import '../theme/phone_layout.dart';
import '../widgets/atmosphere.dart';
import '../widgets/brand_logo.dart';
import 'welcome_screen.dart';

enum _SessionPhase {
  idle,
  listening,
  sending,
  teacherSpeaking,
}

class ClassroomScreen extends StatefulWidget {
  const ClassroomScreen({
    super.key,
    required this.service,
    this.connectOnStart = false,
  });

  final DidWebRtcService service;
  final bool connectOnStart;

  @override
  State<ClassroomScreen> createState() => _ClassroomScreenState();
}

class _ClassroomScreenState extends State<ClassroomScreen> {
  final SpeechToText _speech = SpeechToText();
  final List<String> _sttLogs = <String>[];

  bool _streamAttached = false;
  bool _videoFrames = false;
  String _connectionNote = 'Connecting…';
  bool _speechAvailable = false;
  bool _submitting = false;
  bool _showSttLog = true;
  _SessionPhase _phase = _SessionPhase.idle;
  String _heard = '';
  String? _hint;
  String? _localeId;

  void _sttLog(String message) {
    final line = '${DateTime.now().toIso8601String().substring(11, 19)}  $message';
    debugPrint('[STT] $line');
    if (!mounted) return;
    setState(() {
      _sttLogs.add(line);
      if (_sttLogs.length > 40) {
        _sttLogs.removeRange(0, _sttLogs.length - 40);
      }
    });
  }

  /// WebRTC often sets iOS audio to playback-only. STT needs the mic.
  Future<void> _prepareAudioForListening() async {
    try {
      if (!kIsWeb &&
          (defaultTargetPlatform == TargetPlatform.iOS ||
              defaultTargetPlatform == TargetPlatform.macOS)) {
        await Helper.setAppleAudioIOMode(
          AppleAudioIOMode.localAndRemote,
          preferSpeakerOutput: true,
        );
        _sttLog('Apple audio -> localAndRemote (mic+speaker)');
      }
      await Helper.setSpeakerphoneOn(true);
    } catch (error) {
      _sttLog('prepareAudio failed: $error');
    }
  }

  /// After STT, hand the audio session back so D-ID teacher audio can play.
  Future<void> _restoreAudioForTeacher() async {
    try {
      // Make sure speech recognition has fully released the mic/session.
      if (_speech.isListening) {
        await _speech.stop();
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));

      final stream = widget.service.renderer.srcObject;
      if (stream != null) {
        for (final track in [
          ...stream.getAudioTracks(),
          ...stream.getVideoTracks(),
        ]) {
          track.enabled = true;
        }
        _sttLog(
          'Tracks enabled '
          '(audio=${stream.getAudioTracks().length}, '
          'video=${stream.getVideoTracks().length})',
        );
      }

      if (!kIsWeb &&
          (defaultTargetPlatform == TargetPlatform.iOS ||
              defaultTargetPlatform == TargetPlatform.macOS)) {
        // Playback-focused session so the teacher stream can be heard clearly.
        await Helper.setAppleAudioIOMode(
          AppleAudioIOMode.remoteOnly,
          preferSpeakerOutput: true,
        );
        _sttLog('Apple audio -> remoteOnly (teacher playback)');
      }

      await Helper.setSpeakerphoneOn(true);
      _sttLog('Speakerphone on for teacher reply');
    } catch (error) {
      _sttLog('restoreAudio failed: $error');
    }
  }

  bool _isSoftSttError(String errorMsg) {
    final msg = errorMsg.toLowerCase();
    return msg.contains('no_match') ||
        msg.contains('speech_timeout') ||
        msg.contains('timeout') ||
        msg.contains('error_no_match') ||
        msg.contains('error_speech_timeout');
  }

  @override
  void initState() {
    super.initState();
    widget.service.onRemoteStream = () {
      if (!mounted) return;
      setState(() {
        _streamAttached = true;
        _connectionNote = 'Stream attached — waiting for video frames…';
      });
    };
    widget.service.onConnectionState = (state) {
      if (!mounted) return;
      setState(() {
        if (state.startsWith('video:') && state != 'video:none') {
          _videoFrames = true;
          _connectionNote = 'Video $state';
        } else if (state == 'video:none') {
          _connectionNote =
              'Connected, but no video frames yet. Check network / try again.';
        } else if (state.startsWith('ice:')) {
          _connectionNote = state;
        } else {
          _connectionNote = state;
        }
      });
    };

    widget.service.renderer.onFirstFrameRendered = () {
      if (!mounted) return;
      setState(() {
        _videoFrames = true;
        _connectionNote = 'Video ready';
      });
    };

    if (widget.service.renderer.srcObject != null) {
      _streamAttached = true;
    }

    unawaited(_initSpeech());

    if (widget.connectOnStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_connectTeacher());
      });
    }
  }

  Future<void> _connectTeacher() async {
    setState(() => _connectionNote = 'Connecting to teacher…');
    try {
      // Ensure the native RTCVideoView texture exists before tracks arrive.
      await Future<void>.delayed(const Duration(milliseconds: 400));
      if (!mounted) return;
      await widget.service.connectTeacher();
      if (!mounted) return;
      setState(() {}); // rebuild with latest videoViewGeneration
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.service.rebindRendererForView();
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _connectionNote = 'Could not connect: $error';
      });
      debugPrint('Classroom connect error: $error');
    }
  }

  Future<void> _initSpeech() async {
    _sttLog('Initializing speech… platform=$defaultTargetPlatform web=$kIsWeb');

    if (!kIsWeb) {
      final statuses = await [
        Permission.microphone,
        Permission.speech,
      ].request();

      final mic = statuses[Permission.microphone] ?? PermissionStatus.denied;
      final speech = statuses[Permission.speech] ?? PermissionStatus.denied;
      _sttLog('Permission mic=$mic speech=$speech');

      if (!mic.isGranted || !speech.isGranted) {
        if (!mounted) return;
        final blocked = mic.isPermanentlyDenied || speech.isPermanentlyDenied;
        setState(() {
          _hint = blocked
              ? 'Microphone access is off. Open Settings to allow it.'
              : 'Allow microphone & speech so you can ask questions.';
        });
        _sttLog('Permissions not granted — blocked=$blocked');
        return;
      }
    }

    final available = await _speech.initialize(
      onError: (error) {
        _sttLog(
          'ERROR errorMsg=${error.errorMsg} '
          'permanent=${error.permanent}',
        );
        if (!mounted) return;

        // Soft errors are common (silence / no match). Keep the session usable.
        if (_isSoftSttError(error.errorMsg)) {
          setState(() {
            _phase = _SessionPhase.idle;
            _hint =
                'Didn’t catch that. Tap the mic and try again, or type below.';
          });
          unawaited(_restoreAudioForTeacher());
          return;
        }

        setState(() {
          _phase = _SessionPhase.idle;
          _hint =
              'STT error: ${error.errorMsg}${error.permanent ? ' (permanent)' : ''}';
        });
        unawaited(_restoreAudioForTeacher());
      },
      onStatus: (status) {
        _sttLog('status=$status listening=${_speech.isListening} heard="$_heard"');
        if (!mounted) return;
        if (status == 'done' || status == 'notListening') {
          if (_phase == _SessionPhase.listening && _heard.trim().isNotEmpty) {
            unawaited(_submitHeard());
          } else if (_phase == _SessionPhase.listening) {
            setState(() => _phase = _SessionPhase.idle);
            unawaited(_restoreAudioForTeacher());
          }
        }
      },
    );

    final locales = await _speech.locales();
    final systemLocale = await _speech.systemLocale();
    _localeId = systemLocale?.localeId;
    // Prefer an English locale when available — more reliable for this demo.
    final english = locales.where(
      (l) => l.localeId.toLowerCase().startsWith('en'),
    );
    if (english.isNotEmpty) {
      _localeId = english.first.localeId;
    }

    _sttLog(
      'initialize available=$available '
      'locales=${locales.length} '
      'system=${systemLocale?.localeId} '
      'using=$_localeId',
    );
    for (final locale in locales.take(8)) {
      _sttLog('  locale ${locale.localeId} (${locale.name})');
    }

    if (!mounted) return;
    setState(() {
      _speechAvailable = available;
      _hint = available
          ? null
          : 'Speech recognition is not available on this device.';
    });
  }

  Future<void> _toggleTalk() async {
    if (_phase == _SessionPhase.sending ||
        _phase == _SessionPhase.teacherSpeaking) {
      return;
    }

    if (_phase == _SessionPhase.listening) {
      _sttLog('Stop tapped. final heard="$_heard"');
      await _speech.stop();
      await _restoreAudioForTeacher();
      if (_heard.trim().isNotEmpty) {
        await _submitHeard();
      } else {
        setState(() => _phase = _SessionPhase.idle);
      }
      return;
    }

    if (!_speechAvailable) {
      _sttLog('Speech not ready — re-initializing');
      await _initSpeech();
      if (!_speechAvailable) return;
    }

    setState(() {
      _phase = _SessionPhase.listening;
      _heard = '';
      _hint = null;
    });

    await _prepareAudioForListening();
    // Give the audio session a moment to settle before STT grabs the mic.
    await Future<void>.delayed(const Duration(milliseconds: 350));
    _sttLog('listen() starting locale=$_localeId');

    final started = await _speech.listen(
      onResult: (result) {
        _sttLog(
          'result final=${result.finalResult} '
          'conf=${result.confidence.toStringAsFixed(2)} '
          'words="${result.recognizedWords}"',
        );
        if (!mounted) return;
        setState(() {
          _heard = result.recognizedWords;
          if (_heard.isNotEmpty) {
            _hint = null;
          }
        });
      },
      listenOptions: SpeechListenOptions(
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 5),
        partialResults: true,
        cancelOnError: false,
        listenMode: ListenMode.dictation,
        localeId: _localeId,
      ),
    );
    _sttLog(
      'listen() returned started=$started isListening=${_speech.isListening}',
    );
    if (!started && mounted) {
      await _restoreAudioForTeacher();
      setState(() {
        _phase = _SessionPhase.idle;
        _hint = 'Could not start the microphone. Try again.';
      });
    }
  }

  Future<void> _submitHeard() async {
    if (_submitting) return;
    final question = _heard.trim();
    _sttLog('submit heard="$question"');
    if (question.isEmpty) {
      setState(() => _phase = _SessionPhase.idle);
      await _restoreAudioForTeacher();
      return;
    }

    _submitting = true;
    setState(() {
      _phase = _SessionPhase.sending;
      _hint = null;
    });

    // Release mic / STT session BEFORE calling D-ID speak.
    if (_speech.isListening) {
      await _speech.stop();
    }
    await _restoreAudioForTeacher();
    await Future<void>.delayed(const Duration(milliseconds: 400));

    try {
      final reply = await widget.service.askTeacher(question);
      _sttLog(
        'ask-and-speak OK '
        'replyChars=${reply.length} '
        'viwo=${widget.service.viwoSessionId}',
      );

      if (!mounted) return;

      // Keep speaker routing active while D-ID plays the clip.
      await Helper.setSpeakerphoneOn(true);

      // Rough wait so the avatar can finish speaking before returning to idle.
      final waitSeconds = (reply.split(RegExp(r'\s+')).length / 2.2)
          .clamp(6, 28)
          .round();

      setState(() {
        _phase = _SessionPhase.teacherSpeaking;
        _hint = null;
      });

      await Future<void>.delayed(Duration(seconds: waitSeconds));
      if (!mounted) return;
      setState(() {
        _phase = _SessionPhase.idle;
        _heard = '';
      });
    } catch (error) {
      _sttLog('askTeacher failed: $error');
      if (!mounted) return;
      setState(() {
        _phase = _SessionPhase.idle;
        _hint = 'Ask failed. Please try again.';
      });
    } finally {
      _submitting = false;
    }
  }

  Future<void> _leave() async {
    await _speech.stop();
    await _restoreAudioForTeacher();
    await widget.service.dispose();
    await widget.service.renderer.dispose();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 450),
        pageBuilder: (context, animation, secondaryAnimation) => FadeTransition(
          opacity: animation,
          child: const WelcomeScreen(),
        ),
      ),
    );
  }

  String get _statusLabel {
    switch (_phase) {
      case _SessionPhase.idle:
        return _videoFrames
            ? 'Tap the mic and ask your question'
            : (_streamAttached
                ? _connectionNote
                : 'Teacher is joining…');
      case _SessionPhase.listening:
        return 'Listening…';
      case _SessionPhase.sending:
        return 'Asking your teacher…';
      case _SessionPhase.teacherSpeaking:
        return 'Your teacher is answering…';
    }
  }

  @override
  void dispose() {
    unawaited(_speech.stop());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final layout = PhoneLayout.of(context);
    final bottomInset = layout.padding.bottom;
    final phone = layout.isPhone;

    // On tall phones, cover crops faces; contain keeps the teacher fully visible.
    final videoFit = phone
        ? RTCVideoViewObjectFit.RTCVideoViewObjectFitContain
        : RTCVideoViewObjectFit.RTCVideoViewObjectFitCover;

    return Scaffold(
      backgroundColor: AppColors.ink,
      body: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(
            color: const Color(0xFF0A2A30),
            // Key forces Android to recreate the SurfaceTexture when the
            // remote stream generation changes (black-screen workaround).
            child: RTCVideoView(
              widget.service.renderer,
              key: ValueKey(
                'did-video-${widget.service.videoViewGeneration}',
              ),
              objectFit: videoFit,
              mirror: false,
              filterQuality: FilterQuality.medium,
            ),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x990A2A30),
                  Color(0x000A2A30),
                  Color(0x000A2A30),
                  Color(0xE60A2A30),
                ],
                stops: [0, 0.22, 0.48, 1],
              ),
            ),
          ),
          SafeArea(
            minimum: EdgeInsets.only(bottom: phone ? 4 : 8),
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                layout.horizontalPadding,
                phone ? 8 : 12,
                layout.horizontalPadding,
                phone ? 4 : 8,
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      BrandLogo(height: phone ? 34 : 40),
                      const Spacer(),
                      TextButton(
                        onPressed: () {
                          setState(() => _showSttLog = !_showSttLog);
                        },
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white.withValues(alpha: 0.95),
                          backgroundColor: Colors.white.withValues(alpha: 0.14),
                          minimumSize: const Size(44, 44),
                          padding: EdgeInsets.symmetric(
                            horizontal: phone ? 10 : 12,
                            vertical: 10,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          _showSttLog ? 'Hide STT' : 'STT log',
                          style: GoogleFonts.plusJakartaSans(
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: _leave,
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white.withValues(alpha: 0.95),
                          backgroundColor: Colors.white.withValues(alpha: 0.14),
                          minimumSize: const Size(44, 44),
                          padding: EdgeInsets.symmetric(
                            horizontal: phone ? 12 : 14,
                            vertical: 10,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          'Leave',
                          style: GoogleFonts.plusJakartaSans(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (_showSttLog) ...[
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      height: phone ? 140 : 160,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.72),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: _sttLogs.isEmpty
                          ? Text(
                              'STT log will appear here…',
                              style: GoogleFonts.plusJakartaSans(
                                color: Colors.white54,
                                fontSize: 11,
                              ),
                            )
                          : ListView.builder(
                              itemCount: _sttLogs.length,
                              itemBuilder: (context, index) {
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 4),
                                  child: SelectableText(
                                    _sttLogs[index],
                                    style: GoogleFonts.robotoMono(
                                      color: const Color(0xFFB9F6CA),
                                      fontSize: 10,
                                      height: 1.25,
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                  const Spacer(),
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: phone ? double.infinity : 520,
                    ),
                    child: Column(
                      children: [
                        PulseRing(
                          active: _phase == _SessionPhase.listening,
                          diameter: phone ? 118 : 108,
                          child: _TalkMicButton(
                            phase: _phase,
                            size: phone ? 92 : 84,
                            onPressed: _toggleTalk,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _phase == _SessionPhase.listening
                              ? 'Tap again when you finish'
                              : 'Ask your teacher',
                          style: GoogleFonts.plusJakartaSans(
                            color: Colors.white.withValues(alpha: 0.72),
                            fontWeight: FontWeight.w500,
                            fontSize: 13,
                          ),
                        ),
                        SizedBox(height: phone ? 14 : 16),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 280),
                          child: Container(
                            key: ValueKey(
                              _phase == _SessionPhase.listening &&
                                      _heard.isNotEmpty
                                  ? 'heard-$_heard'
                                  : _statusLabel,
                            ),
                            width: double.infinity,
                            padding: EdgeInsets.symmetric(
                              horizontal: phone ? 16 : 18,
                              vertical: phone ? 12 : 14,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.28),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Text(
                              _phase == _SessionPhase.listening &&
                                      _heard.isNotEmpty
                                  ? _heard
                                  : _statusLabel,
                              textAlign: TextAlign.center,
                              maxLines: phone ? 5 : 4,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.plusJakartaSans(
                                color: Colors.white.withValues(alpha: 0.95),
                                fontSize: phone ? 15 : 16,
                                fontWeight: FontWeight.w600,
                                height: 1.35,
                              ),
                            ),
                          ),
                        ),
                        if (_hint != null) ...[
                          const SizedBox(height: 10),
                          Text(
                            _hint!,
                            textAlign: TextAlign.center,
                            style: GoogleFonts.plusJakartaSans(
                              color: AppColors.chalk,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                          if (_hint!.contains('Settings')) ...[
                            const SizedBox(height: 8),
                            TextButton(
                              onPressed: openAppSettings,
                              style: TextButton.styleFrom(
                                foregroundColor: AppColors.ink,
                                backgroundColor: AppColors.chalk,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 10,
                                ),
                              ),
                              child: Text(
                                'Open Settings',
                                style: GoogleFonts.plusJakartaSans(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ],
                    ),
                  ),
                  SizedBox(height: phone ? 10 + bottomInset * 0.35 : 8),
                ],
              ),
            ),
          ),
          if (!_videoFrames)
            ColoredBox(
              color: const Color(0x990A2A30),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!_streamAttached ||
                          !_connectionNote.contains('emulator'))
                        const ConnectingDots(),
                      const SizedBox(height: 16),
                      Text(
                        _connectionNote,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.plusJakartaSans(
                          color: Colors.white.withValues(alpha: 0.9),
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TalkMicButton extends StatelessWidget {
  const _TalkMicButton({
    required this.phase,
    required this.onPressed,
    this.size = 84,
  });

  final _SessionPhase phase;
  final VoidCallback onPressed;
  final double size;

  @override
  Widget build(BuildContext context) {
    final busy = phase == _SessionPhase.sending ||
        phase == _SessionPhase.teacherSpeaking;
    final listening = phase == _SessionPhase.listening;

    final bg = listening ? AppColors.chalk : AppColors.deepTeal;
    final fg = listening ? AppColors.ink : Colors.white;

    return Material(
      color: bg,
      shape: const CircleBorder(),
      elevation: 0,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: busy ? null : onPressed,
        child: SizedBox(
          width: size,
          height: size,
          child: Center(
            child: busy
                ? const SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.6,
                      color: Colors.white,
                    ),
                  )
                : Icon(
                    listening ? Icons.stop_rounded : Icons.mic_rounded,
                    color: fg,
                    size: size * 0.42,
                  ),
          ),
        ),
      ),
    );
  }
}
