import { useEffect, useRef, useState } from 'react';
import { useTrackingStore } from '../store/trackingStore';
import { GpxReplay, parseGpx, SAMPLE_GPX } from '../gpxReplay';
import { Button, Card, Field, Note, Row } from './ui';

export function GpxReplayCard() {
  const isInitialized = useTrackingStore((s) => s.isInitialized);
  const isTracking = useTrackingStore((s) => s.isTracking);

  const [gpx, setGpx] = useState('');
  const [sent, setSent] = useState(0);
  const [total, setTotal] = useState(0);
  const [running, setRunning] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const replayRef = useRef<GpxReplay | null>(null);

  // A replay left running would keep feeding the SDK after this screen is gone.
  useEffect(() => () => replayRef.current?.stop(), []);

  const start = () => {
    setError(null);
    const waypoints = parseGpx(gpx.trim() || SAMPLE_GPX);
    if (waypoints.length < 2) {
      setError('Need at least two <trkpt> points to derive speed and heading.');
      return;
    }

    replayRef.current?.stop();
    const replay = new GpxReplay(waypoints, {
      fixedIntervalMs: 2000,
      onProgress: (done, count) => {
        setSent(done);
        setTotal(count);
      },
      onDone: () => setRunning(false),
      onError: (message) => {
        setError(message);
        setRunning(false);
      },
    });
    replayRef.current = replay;
    setSent(0);
    setTotal(waypoints.length);
    setRunning(true);
    replay.start();
  };

  const stop = () => {
    replayRef.current?.stop();
    setRunning(false);
  };

  return (
    <Card title="GPX replay">
      <Field
        label="GPX"
        value={gpx}
        onChangeText={setGpx}
        placeholder="Paste a GPX track, or leave blank for the sample route"
      />
      <Row label="Progress" value={total > 0 ? `${sent} / ${total}` : '—'} />
      {error ? <Note>{error}</Note> : null}

      {running ? (
        <Button title="Stop replay" tone="danger" onPress={stop} />
      ) : (
        <Button title="Replay route" disabled={!isInitialized} onPress={start} />
      )}

      <Note>
        Points are fed through processExternalLocation, which the SDK routes into
        the real tracking pipeline — replayed fixes are recorded and uploaded
        like device ones. Start tracking first, or they have nothing to join.
        {!isTracking && ' Tracking is currently stopped.'}
      </Note>
      <Note>
        Speed and heading are derived from consecutive points, so the first point
        reports zero for both. Speed is capped at 30 m/s: above that the SDK
        reads the value as km/h instead, and a motorway track would land about
        3.6x too slow.
      </Note>
    </Card>
  );
}
