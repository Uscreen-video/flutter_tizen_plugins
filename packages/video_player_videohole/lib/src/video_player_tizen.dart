// Copyright 2023 Samsung Electronics Co., Ltd. All rights reserved.
// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'package:video_player_platform_interface/video_player_platform_interface.dart' hide AudioTrack;
import 'messages.g.dart';
import 'tracks.dart';

/// An implementation of [VideoPlayerPlatform] that uses the
/// Pigeon-generated [VideoPlayerVideoholeApi].
class VideoPlayerTizen extends VideoPlayerPlatform {
  final VideoPlayerVideoholeApi _api = VideoPlayerVideoholeApi();

  /// Registers this class as the default platform instance.
  static void register() {
    VideoPlayerPlatform.instance = VideoPlayerTizen();
  }

  @override
  Future<void> init() {
    return _api.initialize();
  }

  @override
  Future<void> dispose(int textureId) {
    return _api.dispose(PlayerMessage(playerId: textureId));
  }

  @override
  Future<int?> create(DataSource dataSource, {dynamic drmOptions}) async {
    final CreateMessage message = CreateMessage();

    switch (dataSource.sourceType) {
      case DataSourceType.asset:
        message.asset = dataSource.asset;
        message.packageName = dataSource.package;
      case DataSourceType.network:
        message.uri = dataSource.uri;
        message.formatHint = _videoFormatStringMap[dataSource.formatHint];
        message.httpHeaders = dataSource.httpHeaders;
      // message.drmConfigs = dataSource.drmConfigs?.toMap();
      // message.playerOptions = dataSource.playerOptions;
      case DataSourceType.file:
        message.uri = dataSource.uri;
      case DataSourceType.contentUri:
        message.uri = dataSource.uri;
    }

    final PlayerMessage response = await _api.create(message);
    return response.playerId;
  }

  @override
  Future<void> setLooping(int textureId, bool looping) {
    return _api.setLooping(LoopingMessage(playerId: textureId, isLooping: looping));
  }

  @override
  Future<void> play(int textureId) {
    return _api.play(PlayerMessage(playerId: textureId));
  }

  @override
  Future<void> pause(int textureId) async {
    try {
      await _api.pause(PlayerMessage(playerId: textureId));
    } catch (e) {
      return;
    }
  }

  @override
  Future<void> setVolume(int textureId, double volume) async {
    try {
      await _api.setVolume(VolumeMessage(playerId: textureId, volume: volume));
    } catch (e) {
      return;
    }
  }

  @override
  Future<void> setPlaybackSpeed(int textureId, double speed) {
    assert(speed > 0);

    return _api.setPlaybackSpeed(PlaybackSpeedMessage(playerId: textureId, speed: speed));
  }

  @override
  Future<void> seekTo(int textureId, Duration position) {
    return _api.seekTo(PositionMessage(playerId: textureId, position: position.inMilliseconds));
  }

  /// List of video tracks

  Future<List<VideoTrack>> getVideoTracks(int textureId) async {
    final TrackMessage response = await _api.track(TrackTypeMessage(
      playerId: textureId,
      trackType: TrackType.video.name,
    ));

    final List<VideoTrack> videoTracks = <VideoTrack>[];
    for (final Map<Object?, Object?>? trackMap in response.tracks) {
      final int trackId = trackMap!['trackId']! as int;
      final int bitrate = trackMap['bitrate']! as int;
      final int width = trackMap['width']! as int;
      final int height = trackMap['height']! as int;

      videoTracks.add(VideoTrack(
        trackId: trackId,
        width: width,
        height: height,
        bitrate: bitrate,
      ));
    }

    return videoTracks;
  }

  /// List of audio tracks
  Future<List<AudioTrack>> getAudioTracks(int playerId) async {
    final TrackMessage response = await _api.track(TrackTypeMessage(
      playerId: playerId,
      trackType: TrackType.audio.name,
    ));

    final List<AudioTrack> audioTracks = <AudioTrack>[];
    for (final Map<Object?, Object?>? trackMap in response.tracks) {
      final int trackId = trackMap!['trackId']! as int;
      final String language = trackMap['language']! as String;
      final AudioTrackChannelType channelType = _intChannelTypeMap[trackMap['channel']]!;
      final int bitrate = trackMap['bitrate']! as int;

      audioTracks.add(AudioTrack(
        trackId: trackId,
        language: language,
        channel: channelType,
        bitrate: bitrate,
      ));
    }

    return audioTracks;
  }
  @override
  Future<Duration> getPosition(int textureId) async {
    final PositionMessage response = await _api.position(PlayerMessage(playerId: textureId));
    return Duration(milliseconds: response.position);
  }

  @override
  Stream<VideoEvent> videoEventsFor(int textureId) {
    return _eventChannelFor(textureId).receiveBroadcastStream().map((dynamic event) {
      final Map<dynamic, dynamic> map = event as Map<dynamic, dynamic>;
      switch (map['event']) {
        case 'initialized':
          final List<dynamic>? durationVal = map['duration'] as List<dynamic>?;
          final Duration duration = Duration(milliseconds: durationVal?[1] as int);

          return VideoEvent(
            eventType: VideoEventType.initialized,
            duration: duration,
            size: Size((map['width'] as num?)?.toDouble() ?? 0.0,
                (map['height'] as num?)?.toDouble() ?? 0.0),
          );
        case 'completed':
          return VideoEvent(
            eventType: VideoEventType.completed,
          );
        case 'bufferingUpdate':
          // Buffering event receives percents as buffered value
          // When event is received, there is no duration received yet, so no easy way to calculate buffered duration
          // Leaving empty for now, as we don't use it
          // TODO: calculate it

          // final int percentBuffered = map['value']! as int;
          // final int secondsBuffered = (_duration.inSeconds * percentBuffered / 100.0).round();
          // final DurationRange rangeBuffered = DurationRange(Duration.zero, Duration(seconds: secondsBuffered));

          return VideoEvent(
            buffered: const <DurationRange>[],
            eventType: VideoEventType.bufferingUpdate,
          );
        case 'bufferingStart':
          return VideoEvent(eventType: VideoEventType.bufferingStart);
        case 'bufferingEnd':
          return VideoEvent(eventType: VideoEventType.bufferingEnd);
        case 'subtitleUpdate':
          final int offsetMs = map['duration']! as int;
          return VideoEvent(
            eventType: VideoEventType.caption,
            caption: VideoCaption(value: map['text']! as String, offset: offsetMs / 1000.0),
          );
        default:
          return VideoEvent(eventType: VideoEventType.unknown);
      }
    });
  }

  @override
  Widget buildView(int textureId) {
    return Texture(textureId: textureId);
  }

  @override
  Future<void> setMixWithOthers(bool mixWithOthers) {
    return _api.setMixWithOthers(MixWithOthersMessage(mixWithOthers: mixWithOthers));
  }

  Future<void> setDisplayGeometry(
    int playerId,
    int x,
    int y,
    int width,
    int height,
  ) {
    return _api.setDisplayGeometry(GeometryMessage(
      playerId: playerId,
      x: x,
      y: y,
      width: width,
      height: height,
    ));
  }

  EventChannel _eventChannelFor(int playerId) {
    return EventChannel('tizen/video_player/video_events_$playerId');
  }

  static const Map<VideoFormat, String> _videoFormatStringMap = <VideoFormat, String>{
    VideoFormat.ss: 'ss',
    VideoFormat.hls: 'hls',
    VideoFormat.dash: 'dash',
    VideoFormat.other: 'other',
  };

  static const Map<int, AudioTrackChannelType> _intChannelTypeMap = <int, AudioTrackChannelType>{
    1: AudioTrackChannelType.mono,
    2: AudioTrackChannelType.stereo,
    3: AudioTrackChannelType.surround,
  };

  @override
  Future<void> setCurrentPlayingInfo(int textureId,
      {String? title, String? artist, String? artwork, String? album}) {
    return Future<void>.value();
  }

  @override
  Future<void> setMuxData(int textureId,
      {required String environmentKey,
      required String userId,
      required int videoId,
      required int videoVariantId,
      required String videoTitle}) {
    return Future<void>.value();
  }

  @override
  Future<void> startPictureInPicture(int textureId,
      {required double top, required double left, required double width, required double height}) {
    return Future<void>.value();
  }

  @override
  Future<void> stopPictureInPicture(int textureId) {
    return Future<void>.value();
  }

  @override
  Future<bool> isPictureInPictureSupported(int textureId) {
    return Future<bool>.value(false);
  }

  @override
  Future<void> enterFullscreen(int textureId) {
    return Future<void>.value();
  }

  @override
  Future<void> exitFullscreen(int textureId) {
    return Future<void>.value();
  }

  @override
  Future<void> selectClosedCaptionLocale(int textureId, String localeIdentifier) {
    return Future<void>.value();
  }

  @override
  Future<void> clearClosedCaptionLocaleSelection(int textureId) {
    return Future<void>.value();
  }

  @override
  Future<void> setVideoChapters(int textureId, List<Chapter> chapters) {
    return Future<void>.value();
  }

  Future<bool> isAutoPictureInPictureSupported() async {
    return false;
  }
}
