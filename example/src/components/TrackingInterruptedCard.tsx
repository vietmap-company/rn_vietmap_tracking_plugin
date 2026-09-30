import { useTrackingStore } from '../store/trackingStore';
import { Button, Card, Note, Row } from './ui';

export function TrackingInterruptedCard() {
  const events = useTrackingStore((s) => s.interruptedEvents);
  const clearEvents = useTrackingStore((s) => s.clearInterruptedEvents);

  return (
    <Card title="Tracking interruptions">
      {events.length === 0 ? (
        <Row label="Events" value="none" />
      ) : (
        <>
          {events.map((event, index) => (
            <Row
              key={`${event.reason}-${index}`}
              label={event.recovered ? `recovered: ${event.reason}` : event.reason}
              value={`${Math.round(event.secondsSinceLastFix)}s${event.isInBackground ? ' · bg' : ''}`}
            />
          ))}
          <Button title="Clear events" tone="neutral" onPress={clearEvents} />
        </>
      )}
      <Note>
        The demo only records these. Do not stop and restart tracking in
        response: the SDK raises them from GPS silence, so a restart costs a
        fresh first fix and can loop.
      </Note>
    </Card>
  );
}
