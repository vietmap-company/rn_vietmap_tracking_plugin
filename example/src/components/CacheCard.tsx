import { useEffect } from 'react';
import { useTrackingStore } from '../store/trackingStore';
import { Button, Card, Field, Note, Row } from './ui';

function formatBytes(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(2)} MB`;
}

export function CacheCard() {
  const cachedCount = useTrackingStore((s) => s.cachedCount);
  const dbSizeBytes = useTrackingStore((s) => s.dbSizeBytes);
  const isOnline = useTrackingStore((s) => s.isOnline);
  const isInitialized = useTrackingStore((s) => s.isInitialized);
  const maxRecords = useTrackingStore((s) => s.maxRecords);
  const maxDbSizeMb = useTrackingStore((s) => s.maxDbSizeMb);
  const batchSize = useTrackingStore((s) => s.batchSize);

  const refreshCacheStats = useTrackingStore((s) => s.refreshCacheStats);
  const applyCacheLimits = useTrackingStore((s) => s.applyCacheLimits);
  const uploadCache = useTrackingStore((s) => s.uploadCache);
  const clearCache = useTrackingStore((s) => s.clearCache);

  useEffect(() => {
    if (!isInitialized) return;
    // Polled rather than pushed: the SDK has no event for the queue draining.
    const timer = setInterval(refreshCacheStats, 5000);
    return () => clearInterval(timer);
  }, [isInitialized, refreshCacheStats]);

  return (
    <Card title="Offline cache">
      <Row label="Pending uploads" value={String(cachedCount)} />
      <Row label="Database size" value={formatBytes(dbSizeBytes)} />
      <Row label="Network (SDK)" value={isOnline ? 'online' : 'offline'} />

      <Button
        title="Upload now"
        disabled={!isInitialized || cachedCount === 0}
        onPress={uploadCache}
      />
      <Note>
        Android reports success once the request starts, not once it lands, so
        the pending count above is the real answer.
      </Note>

      <Button
        title="Clear cache"
        tone="danger"
        disabled={!isInitialized || cachedCount === 0}
        onPress={clearCache}
      />

      <Field
        label="Max records"
        value={maxRecords}
        onChangeText={(v) => useTrackingStore.setState({ maxRecords: v })}
        keyboardType="numeric"
        placeholder="SDK default"
        hint="Blank keeps the SDK's own limit, which differs per platform: 5000 on Android, 10000 on iOS."
      />
      <Field
        label="Max database size (MB)"
        value={maxDbSizeMb}
        onChangeText={(v) => useTrackingStore.setState({ maxDbSizeMb: v })}
        keyboardType="numeric"
        placeholder="SDK default (50)"
      />
      <Field
        label="Batch size"
        value={batchSize}
        onChangeText={(v) => useTrackingStore.setState({ batchSize: v })}
        keyboardType="numeric"
        placeholder="SDK default (50)"
      />
      <Button
        title="Apply limits"
        tone="neutral"
        disabled={!isInitialized}
        onPress={applyCacheLimits}
      />
    </Card>
  );
}
