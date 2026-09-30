import { useState } from 'react';
import { useTrackingStore } from '../store/trackingStore';
import { Button, Card, Field, Note, Row } from './ui';

export function PackagesCard() {
  const packages = useTrackingStore((s) => s.packages);
  const appliedPackages = useTrackingStore((s) => s.appliedPackages);
  const isInitialized = useTrackingStore((s) => s.isInitialized);
  const addPackages = useTrackingStore((s) => s.addPackages);
  const removePackage = useTrackingStore((s) => s.removePackage);
  const applyPackages = useTrackingStore((s) => s.applyPackages);

  const [draft, setDraft] = useState('');

  // Compared by content, not reference: the applied list is a copy.
  const dirty =
    packages.length !== appliedPackages.length ||
    packages.some((code, i) => code !== appliedPackages[i]);

  return (
    <Card title="Packages and metadata">
      <Field
        label="Add package codes"
        value={draft}
        onChangeText={setDraft}
        placeholder="PKG001, PKG002"
        hint="Separated by spaces, commas or semicolons."
      />
      <Button
        title="Add"
        tone="neutral"
        disabled={draft.trim().length === 0}
        onPress={() => {
          addPackages(draft);
          setDraft('');
        }}
      />

      {packages.map((code) => (
        <Row key={code} label={code} value="tap Remove below" />
      ))}
      {packages.map((code) => (
        <Button
          key={`rm-${code}`}
          title={`Remove ${code}`}
          tone="neutral"
          onPress={() => removePackage(code)}
        />
      ))}

      <Button
        title={dirty ? 'Apply packages *' : 'Apply packages'}
        disabled={!isInitialized}
        onPress={applyPackages}
      />
      <Note>
        Applying also sends metadata, so both reach the SDK in one action. Both
        ride on every upload afterwards.
      </Note>
    </Card>
  );
}
