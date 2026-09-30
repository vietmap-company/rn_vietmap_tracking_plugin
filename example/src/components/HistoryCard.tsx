import { useTrackingStore } from '../store/trackingStore';
import { Button, Card, Note, Row } from './ui';

export function HistoryCard() {
  const rows = useTrackingStore((s) => s.serverHistory);
  const isFetching = useTrackingStore((s) => s.isFetchingHistory);
  const hasMore = useTrackingStore((s) => s.hasMoreHistory);
  const userId = useTrackingStore((s) => s.userId);
  const isInitialized = useTrackingStore((s) => s.isInitialized);
  const fetchServerHistory = useTrackingStore((s) => s.fetchServerHistory);

  return (
    <Card title="Stored on server">
      <Row label="Rows" value={String(rows.length)} />
      <Button
        title={isFetching ? 'Loading…' : 'Load last 24h'}
        disabled={isFetching || !isInitialized || userId.trim().length === 0}
        onPress={() => fetchServerHistory(true)}
      />
      {rows.slice(0, 10).map((row, index) => (
        <Row
          key={`${row.timestamp}-${index}`}
          label={new Date(row.timestamp).toLocaleTimeString()}
          value={`${row.latitude?.toFixed(5)}, ${row.longitude?.toFixed(5)}`}
          mono
        />
      ))}
      {rows.length > 0 && hasMore && (
        <Button
          title={isFetching ? 'Loading…' : 'Load more'}
          tone="neutral"
          disabled={isFetching}
          onPress={() => fetchServerHistory(false)}
        />
      )}
      <Note>
        What actually reached the backend, across sessions and devices. Compare
        it with "Received on device": fixes there but not here means the upload
        path is failing, not the GPS.
      </Note>
      {userId.trim().length === 0 && <Note>Set a User ID to query history.</Note>}
    </Card>
  );
}
