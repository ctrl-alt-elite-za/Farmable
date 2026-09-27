import 'package:almanac/data/mapping/recorded_walks.dart';
import 'package:almanac/domain/mapping/geometry.dart';
import 'package:almanac/domain/mapping/walk.dart';
import 'package:flutter_test/flutter_test.dart';

WalkRecording record(List<WalkSample> samples) {
  final r = WalkRecording();
  samples.forEach(r.add);
  return r;
}

void main() {
  group('recorded field walk (AR + GPS)', () {
    final recording = record(recordedWalk(RecordedWalk.field));
    final result = recording.finish();

    test('review shape is the true area to within 1%', () {
      final area = geodesicArea(result.ring);
      expect(disagreement(area, recordedFieldAreaM2), lessThan(0.01));
      expect(result.ring.length, inInclusiveRange(4, 6));
    });

    test('AR and GPS agree, so there is no warning', () {
      expect(
        disagreement(result.arAreaM2!, recordedFieldAreaM2),
        lessThan(0.01),
      );
      expect(result.gpsAreaM2, isNotNull);
      expect(result.disagreementFraction, lessThan(0.15));
      expect(result.agreementWarning, isFalse);
    });

    test('AR drawing paused while tracking was lost; GPS carried on', () {
      expect(recording.trackingLosses, 1);
      final samples = recordedWalk(RecordedWalk.field);
      expect(recording.gpsPath, hasLength(samples.length));
      expect(recording.arPath.length, lessThan(samples.length));
    });
  });

  test('drifting GPS disagrees with AR by more than 15%', () {
    final result = record(recordedWalk(RecordedWalk.drift)).finish();
    expect(result.disagreementFraction, greaterThan(0.15));
    expect(result.agreementWarning, isTrue);
    // The shape to review still comes from AR, which did not drift.
    expect(
      disagreement(geodesicArea(result.ring), recordedFieldAreaM2),
      lessThan(0.01),
    );
  });

  test('a GPS-only walk measures without AR and gives no agreement', () {
    final recording = record(recordedWalk(RecordedWalk.gpsOnly));
    final result = recording.finish();
    expect(recording.arPath, isEmpty);
    expect(result.arAreaM2, isNull);
    expect(result.disagreementFraction, isNull);
    expect(result.agreementWarning, isFalse);
    expect(
      disagreement(geodesicArea(result.ring), recordedFieldAreaM2),
      lessThan(0.08),
    );
  });

  test('fixes worse than 20 m are dropped and counted', () {
    final recording = record([
      ...recordedWalk(RecordedWalk.gpsOnly),
      const WalkSample(
        at: Duration(minutes: 5),
        gps: GpsPoint(-25.7, 28.2, accuracyMetres: 60),
      ),
    ]);
    expect(recording.poorFixesDropped, 1);
    expect(recording.finish().poorFixesDropped, 1);
  });

  test('marked corners become the shape', () {
    final samples = recordedWalk(RecordedWalk.gpsOnly);
    final r = WalkRecording();
    // Mark at the four corners: samples 0, 67, 117, 183 (40, 30, 40 m apart).
    for (final (i, s) in samples.indexed) {
      r.add(s);
      if (i == 0 || i == 67 || i == 117 || i == 183) r.markCorner();
    }
    final result = r.finish();
    expect(result.fromMarkedCorners, isTrue);
    expect(result.ring, hasLength(4));
    expect(
      disagreement(geodesicArea(result.ring), recordedFieldAreaM2),
      lessThan(0.08),
    );
  });

  test('a corner marked twice in one spot is one corner, not a crossing', () {
    final samples = recordedWalk(RecordedWalk.gpsOnly);
    final r = WalkRecording();
    for (final (i, s) in samples.indexed) {
      r.add(s);
      if (i == 0 || i == 67 || i == 117 || i == 183) r.markCorner();
      // A second tap before the next fix arrives.
      if (i == 67) r.markCorner();
    }
    final result = r.finish();
    expect(result.ring, hasLength(4));
    final flat = [
      for (final p in result.ring) projectGps(p, result.ring.first),
    ];
    expect(firstCrossing(flat), isNull);
  });

  test('a walk that encloses nothing cannot be finished', () {
    final r = WalkRecording()
      ..add(const WalkSample(at: Duration.zero, gps: GpsPoint(-25.7, 28.2)));
    expect(r.liveAreaM2, isNull);
    expect(r.finish, throwsA(isA<GeometryException>()));
    expect(WalkRecording().markCorner(), isFalse);
  });

  test('replay source plays every sample then closes', () async {
    final samples = recordedWalk(RecordedWalk.field);
    final source = ReplayWalkSource(samples, speed: 0);
    expect(source.hasAr, isTrue);
    expect(await source.start().toList(), hasLength(samples.length));
    expect(ReplayWalkSource(recordedWalk(RecordedWalk.gpsOnly)).hasAr, isFalse);
  });

  test('stopping a playback and starting another never adds to a closed '
      'stream', () async {
    final source = ReplayWalkSource(recordedWalk(RecordedWalk.field), speed: 8);
    final first = source.start().listen((_) {});
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await source.stop();
    final second = source.start().listen((_) {});
    // Long enough for the first playback's pending wait to wake up.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await source.stop();
    await first.cancel();
    await second.cancel();
  });

  test('samples round-trip through JSON', () {
    for (final s in recordedWalk(RecordedWalk.field).take(100)) {
      final back = WalkSample.fromJson(s.toJson());
      expect(back.at, s.at);
      expect(back.ar, s.ar);
      expect(back.gps, s.gps);
      expect(back.tracking, s.tracking);
    }
  });

  test('GeoJSON is closed [lon, lat] and areas read naturally', () {
    const ring = [
      GpsPoint(-25.0, 28.0),
      GpsPoint(-25.0, 28.001),
      GpsPoint(-25.001, 28.001),
    ];
    final json = ringToGeoJson(ring);
    final coords = (json['coordinates']! as List).first as List;
    expect(coords.first, [28.0, -25.0]);
    expect(coords.last, coords.first);
    expect(formatArea(1200.4), '1 200 m²');
    expect(formatArea(25000), '2.50 ha');
    expect(areaM2String(1199.996), '1200.00');
  });
}
