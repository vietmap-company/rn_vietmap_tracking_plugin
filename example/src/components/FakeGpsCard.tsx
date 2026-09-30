import type { FakeGpsPolicy } from '@vietmap/rn_vietmap_tracking_plugin';
import { useTrackingStore } from '../store/trackingStore';
import { Button, Card, Note, Row, Segmented } from './ui';

const POLICIES: { key: FakeGpsPolicy; label: string }[] = [
  { key: 'skip', label: 'Skip' },
  { key: 'warn', label: 'Warn' },
  { key: 'stopTracking', label: 'Stop' },
  { key: 'logToServer', label: 'Log' },
];

export function FakeGpsCard() {
  const policy = useTrackingStore((s) => s.fakeGpsPolicy);
  const events = useTrackingStore((s) => s.fakeGpsEvents);
  const allowMockLocation = useTrackingStore((s) => s.allowMockLocation);
  const notificationsAllowed = useTrackingStore((s) => s.hasNotificationPermission);
  const setPolicy = useTrackingStore((s) => s.setFakeGpsPolicyValue);
  const requestNotifications = useTrackingStore((s) => s.requestNotificationPermissionValue);
  const clearEvents = useTrackingStore((s) => s.clearFakeGpsEvents);

  return (
    <Card title="Fake GPS">
      <Segmented options={POLICIES} value={policy} onChange={setPolicy} />
      <Note>
        {allowMockLocation
          ? 'Detection is off — mock locations pass through, so this policy is not consulted and no detections will appear. Turn off "Allow mock locations" in Configuration to enable it.'
          : 'Detection is on. The policy above decides what happens when a simulated fix arrives.'}
      </Note>

      <Row
        label="Notifications"
        value={notificationsAllowed ? 'allowed' : 'not allowed'}
      />
      {!notificationsAllowed && (
        <Button title="Allow notifications" onPress={requestNotifications} />
      )}
      {policy === 'warn' && !notificationsAllowed && (
        <Note>
          The SDK accepts "warn" either way, but it posts the notification
          through the system — with permission denied the post is dropped and
          nothing appears. That silence is otherwise unexplained.
        </Note>
      )}
      {policy === 'warn' && notificationsAllowed && (
        <Note>
          One banner per 30 seconds at most. The SDK debounces so a continuous
          stream of mock fixes cannot flood the tray — that cadence is working
          as intended, not a fault.
        </Note>
      )}

      {events.length === 0 ? (
        <Row label="Detections" value="none" />
      ) : (
        <>
          {events.map((event, index) => (
            <Row
              key={`${event.timestamp}-${index}`}
              label={new Date(event.timestamp).toLocaleTimeString()}
              value={`${event.lat.toFixed(5)}, ${event.lng.toFixed(5)}${event.reason ? ` (${event.reason})` : ''}`}
              mono
            />
          ))}
          <Button title="Clear detections" tone="neutral" onPress={clearEvents} />
        </>
      )}
      <Note>
        The same 30s debounce gates this list, not just the notification: the
        SDK reports one detection per window, so a steady stream of mock fixes
        adds one row every 30s. The event fires under every policy; only "warn"
        also raises a notification. Android reports position only — the reason
        is iOS-only, from CLLocationSourceInformation.
      </Note>
    </Card>
  );
}
