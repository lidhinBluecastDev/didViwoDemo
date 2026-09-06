import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:http/http.dart' as http;

typedef RemoteStreamCallback = void Function();
typedef ConnectionStateCallback = void Function(String state);

class DidWebRtcService {
  DidWebRtcService({
    required this.baseUrl,
    required this.renderer,
    this.onRemoteStream,
    this.onConnectionState,
  });

  String baseUrl;
  final RTCVideoRenderer renderer;
  RemoteStreamCallback? onRemoteStream;
  ConnectionStateCallback? onConnectionState;

  RTCPeerConnection? _peerConnection;
  MediaStream? _remoteStream;
  String? streamId;
  String? sessionId;
  String? viwoSessionId;
  int _attachGeneration = 0;
  bool _watchingFrames = false;

  bool get isConnected => streamId != null && sessionId != null;

  /// Bumped whenever a remote stream is (re)attached — use as RTCVideoView key.
  int get videoViewGeneration => _attachGeneration;

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    'ngrok-skip-browser-warning': 'true',
  };

  Uri _uri(String path) {
    final root = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    return Uri.parse('$root$path');
  }

  void _debug(String message, [Object? detail]) {
    if (kDebugMode) {
      debugPrint('[DID] $message${detail != null ? ' $detail' : ''}');
    }
  }

  Future<Map<String, dynamic>> _postJson(
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    final response = await http.post(
      _uri(path),
      headers: _headers,
      body: body == null ? null : jsonEncode(body),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('HTTP ${response.statusCode} $path: ${response.body}');
    }

    if (response.body.isEmpty) {
      return {'statusCode': response.statusCode};
    }

    final decoded = jsonDecode(response.body);
    if (decoded is Map<String, dynamic>) return decoded;
    return {'data': decoded, 'statusCode': response.statusCode};
  }

  Future<void> connectTeacher() async {
    onConnectionState?.call('connecting');
    _debug('Creating D-ID stream...');

    final data = await _postJson('/did/connect');
    streamId = data['id']?.toString();
    sessionId = data['session_id']?.toString();

    final iceServers = _normalizeIceServers(data['ice_servers']);
    _debug('ICE servers prepared', iceServers);

    await _peerConnection?.close();
    await _peerConnection?.dispose();
    await _remoteStream?.dispose();
    _remoteStream = null;
    renderer.srcObject = null;
    _watchingFrames = false;

    // Answerer must not pre-add transceivers — D-ID's offer defines m-lines.
    _peerConnection = await createPeerConnection({
      'iceServers': iceServers,
      'sdpSemantics': 'unified-plan',
      'bundlePolicy': 'max-bundle',
      'rtcpMuxPolicy': 'require',
    });

    final pc = _peerConnection!;

    pc.onConnectionState = (state) {
      _debug('Connection state: ${state.name}');
      onConnectionState?.call(state.name);
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        onConnectionState?.call('connected');
        _rebindRendererSoft();
      } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        onConnectionState?.call('failed');
      }
    };

    pc.onIceConnectionState = (state) {
      _debug('ICE state: ${state.name}');
      onConnectionState?.call('ice:${state.name}');
      if (state == RTCIceConnectionState.RTCIceConnectionStateConnected ||
          state == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
        _rebindRendererSoft();
      }
    };

    pc.onAddStream = _attachRemoteStream;

    pc.onTrack = (event) async {
      event.track.enabled = true;
      _debug(
        'onTrack kind=${event.track.kind} id=${event.track.id} '
        'muted=${event.track.muted} streams=${event.streams.length}',
      );

      try {
        if (event.streams.isNotEmpty) {
          _attachRemoteStream(event.streams.first);
        } else {
          _remoteStream ??= await createLocalMediaStream('did-remote');
          final alreadyAdded = _remoteStream!.getTracks().any(
            (t) => t.id == event.track.id,
          );
          if (!alreadyAdded) {
            await _remoteStream!.addTrack(event.track);
          }
          _attachRemoteStream(_remoteStream!);
        }
      } catch (error) {
        _debug('Failed to attach remote track: $error');
      }

      if (event.track.kind == 'audio') {
        try {
          await Helper.setSpeakerphoneOn(true);
        } catch (_) {}
      }
    };

    pc.onIceCandidate = (candidate) async {
      if (candidate.candidate == null || candidate.candidate!.isEmpty) return;
      final cand = candidate.candidate!;
      if (cand.contains('127.0.0.1') || cand.contains('::1')) return;

      try {
        await _postJson('/did/ice', {
          'stream_id': streamId,
          'session_id': sessionId,
          'candidate': candidate.toMap(),
        });
      } catch (error) {
        _debug('ICE send error: $error');
      }
    };

    final offer = data['offer'];
    if (offer is! Map) {
      throw Exception('Connect response missing SDP offer.');
    }

    var remoteSdp = offer['sdp']?.toString() ?? '';
    remoteSdp = _normalizeSdp(remoteSdp);
    // D-ID often advertises H.264 without fmtp. WebRTC then assumes
    // profile-level-id=42e029, which Android's encoder factory does not
    // match (42e01f) → "No video codecs in common" → m=video 0.
    remoteSdp = _ensureH264BaselineProfile(remoteSdp);
    _debug('Remote video m-line: ${_videoMLine(remoteSdp) ?? "(missing)"}');
    for (final line in remoteSdp.split('\n')) {
      if (line.contains('H264') ||
          line.contains('profile-level-id') ||
          line.startsWith('a=fmtp:')) {
        _debug('SDP: $line');
      }
    }
    remoteSdp = remoteSdp.replaceAll('\n', '\r\n');

    await pc.setRemoteDescription(
      RTCSessionDescription(remoteSdp, offer['type']?.toString()),
    );

    final answer = await pc.createAnswer();
    var answerSdp = _normalizeSdp(answer.sdp ?? '');

    // Rejected video m-line check (port 0) — fail fast with a clear error.
    if (_isMediaRejected(answerSdp, 'video')) {
      _debug('Answer rejected video m-line. SDP:\n$answerSdp');
      throw Exception(
        'Video codec negotiation failed on this device. '
        'D-ID offer and Android share no common video codec.',
      );
    }

    answerSdp = answerSdp.replaceAll('\n', '\r\n');
    await pc.setLocalDescription(RTCSessionDescription(answerSdp, answer.type));

    await _postJson('/did/sdp', {
      'stream_id': streamId,
      'session_id': sessionId,
      'answer': {'type': answer.type, 'sdp': answerSdp},
    });

    onConnectionState?.call('ready');
  }

  /// Normalize SDP to `\n` lines so munging works across Chrome / native.
  String _normalizeSdp(String sdp) {
    return sdp.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  }

  String? _videoMLine(String sdp) {
    for (final line in sdp.split('\n')) {
      if (line.startsWith('m=video ')) return line;
    }
    return null;
  }

  /// Force H.264 Constrained Baseline (42e01f) so Android can negotiate.
  String _ensureH264BaselineProfile(String sdp) {
    final lines = sdp.split('\n');
    final h264Pts = <String>{};
    final ptsWithFmtp = <String>{};

    for (final line in lines) {
      final rtp = RegExp(
        r'^a=rtpmap:(\d+)\s+H264/',
        caseSensitive: false,
      ).firstMatch(line);
      if (rtp != null) h264Pts.add(rtp.group(1)!);

      final fmtp = RegExp(r'^a=fmtp:(\d+)\s+').firstMatch(line);
      if (fmtp != null) ptsWithFmtp.add(fmtp.group(1)!);
    }

    if (h264Pts.isEmpty) return sdp;

    final out = <String>[];
    for (final line in lines) {
      final fmtp = RegExp(r'^a=fmtp:(\d+)\s+(.*)$').firstMatch(line);
      if (fmtp != null && h264Pts.contains(fmtp.group(1))) {
        var params = fmtp.group(2)!;
        if (RegExp(
          r'profile-level-id=',
          caseSensitive: false,
        ).hasMatch(params)) {
          params = params.replaceAllMapped(
            RegExp(r'profile-level-id=[0-9a-fA-F]+', caseSensitive: false),
            (_) => 'profile-level-id=42e01f',
          );
        } else {
          params = '$params;profile-level-id=42e01f';
        }
        if (!params.contains('packetization-mode=')) {
          params = 'packetization-mode=1;$params';
        }
        if (!params.contains('level-asymmetry-allowed=')) {
          params = 'level-asymmetry-allowed=1;$params';
        }
        out.add('a=fmtp:${fmtp.group(1)} $params');
        continue;
      }

      out.add(line);

      final rtp = RegExp(
        r'^a=rtpmap:(\d+)\s+H264/',
        caseSensitive: false,
      ).firstMatch(line);
      if (rtp != null && !ptsWithFmtp.contains(rtp.group(1))) {
        out.add(
          'a=fmtp:${rtp.group(1)} '
          'level-asymmetry-allowed=1;packetization-mode=1;profile-level-id=42e01f',
        );
      }
    }

    return out.join('\n');
  }

  bool _isMediaRejected(String sdp, String kind) {
    for (final line in sdp.split('\n')) {
      if (!line.startsWith('m=$kind ')) continue;
      final parts = line.split(' ');
      return parts.length >= 2 && parts[1] == '0';
    }
    return false;
  }

  void _attachRemoteStream(MediaStream stream) {
    final sameStream =
        identical(_remoteStream, stream) && renderer.srcObject?.id == stream.id;
    _remoteStream = stream;

    for (final track in [
      ...stream.getVideoTracks(),
      ...stream.getAudioTracks(),
    ]) {
      track.enabled = true;
    }

    renderer.srcObject = stream;

    if (!sameStream) {
      _attachGeneration++;
    }

    _debug(
      'Remote stream attached '
      'id=${stream.id} '
      'video=${stream.getVideoTracks().length} '
      'audio=${stream.getAudioTracks().length} '
      'gen=$_attachGeneration',
    );
    onRemoteStream?.call();
    _watchVideoFrames();
  }

  void _rebindRendererSoft() {
    final stream = _remoteStream;
    if (stream == null) return;
    renderer.srcObject = null;
    renderer.srcObject = stream;
  }

  /// Hard rebind used by the UI after RTCVideoView mounts.
  void rebindRendererForView() {
    final stream = _remoteStream ?? renderer.srcObject;
    if (stream == null) return;
    _attachGeneration++;
    renderer.srcObject = null;
    renderer.srcObject = stream;
    onRemoteStream?.call();
  }

  void _watchVideoFrames() {
    if (_watchingFrames) return;
    _watchingFrames = true;

    Future<void>(() async {
      for (var i = 0; i < 60; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        final w = renderer.videoWidth;
        final h = renderer.videoHeight;
        if (w > 0 && h > 0) {
          _debug('Video frames flowing ${w.toInt()}x${h.toInt()}');
          onConnectionState?.call('video:${w.toInt()}x${h.toInt()}');
          _watchingFrames = false;
          return;
        }

        if (i == 5 || i == 15 || i == 30) {
          await _logInboundStats();
          _rebindRendererSoft();
        }
      }
      _debug('WARNING: no video frames after 30s.');
      onConnectionState?.call('video:none');
      _watchingFrames = false;
    });
  }

  Future<void> _logInboundStats() async {
    final pc = _peerConnection;
    if (pc == null) return;
    try {
      final report = await pc.getStats();
      for (final stat in report) {
        final values = stat.values;
        final type = values['type']?.toString() ?? stat.type;
        if (type != 'inbound-rtp' && type != 'track') continue;
        final kind =
            values['kind']?.toString() ?? values['mediaType']?.toString() ?? '';
        if (kind.isNotEmpty && kind != 'video') continue;
        final decoded = values['framesDecoded'];
        final received = values['bytesReceived'];
        final packets = values['packetsReceived'];
        final frames = values['framesReceived'];
        if (decoded == null && packets == null && frames == null) continue;
        _debug(
          'Stats $type kind=$kind '
          'framesDecoded=$decoded framesReceived=$frames '
          'packetsReceived=$packets bytesReceived=$received',
        );
        if ((decoded is num && decoded > 0) || (frames is num && frames > 0)) {
          _attachGeneration++;
          onRemoteStream?.call();
        }
      }
    } catch (error) {
      _debug('getStats failed: $error');
    }
  }

  /// Sends a student question and returns the teacher reply text.
  Future<String> askTeacher(String question) async {
    final trimmed = question.trim();
    if (trimmed.isEmpty) {
      throw Exception('Say something first.');
    }
    if (!isConnected) {
      throw Exception('Teacher is not connected yet.');
    }

    final result = await _postJson('/ask-and-speak', {
      'message': trimmed,
      'viwo_session_id': viwoSessionId,
      'stream_id': streamId,
      'session_id': sessionId,
    });

    _debug('ask-and-speak response', result);

    if (result['error'] != null) {
      throw Exception(result['error'].toString());
    }

    viwoSessionId = result['viwo_session_id']?.toString();
    final teacherText = result['teacher_text']?.toString() ?? '';
    if (teacherText.isEmpty) {
      throw Exception('Server returned an empty teacher reply.');
    }
    return teacherText;
  }

  Future<void> dispose() async {
    renderer.srcObject = null;
    await _remoteStream?.dispose();
    _remoteStream = null;
    await _peerConnection?.close();
    await _peerConnection?.dispose();
    _peerConnection = null;
  }

  List<Map<String, dynamic>> _normalizeIceServers(dynamic raw) {
    if (raw is! List) {
      return [
        {'urls': 'stun:stun.l.google.com:19302'},
      ];
    }

    return raw.map<Map<String, dynamic>>((server) {
      if (server is! Map) return {'urls': server.toString()};
      final map = Map<String, dynamic>.from(server);
      if (map['urls'] == null && map['url'] != null) {
        map['urls'] = map['url'];
      }
      if (map['credential'] == null && map['password'] != null) {
        map['credential'] = map['password'];
      }
      return map;
    }).toList();
  }
}
