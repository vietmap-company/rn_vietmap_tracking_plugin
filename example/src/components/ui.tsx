import React, { useState } from 'react';
import {
  Text,
  View,
  TouchableOpacity,
  TextInput,
  Switch,
  StyleSheet,
  Modal,
  Pressable,
  ScrollView,
  type ViewStyle,
} from 'react-native';

/**
 * The shared shell every card sits in, so a new card is a title and its body
 * rather than another copy of the same padding and shadow.
 */
export function Card({
  title,
  children,
  style,
}: {
  title: string;
  children: React.ReactNode;
  style?: ViewStyle;
}) {
  return (
    <View style={[styles.card, style]}>
      <Text style={styles.cardTitle}>{title}</Text>
      {children}
    </View>
  );
}

export function Row({
  label,
  value,
  mono,
}: {
  label: string;
  value: string;
  mono?: boolean;
}) {
  return (
    <View style={styles.row}>
      <Text style={styles.rowLabel}>{label}</Text>
      <Text style={[styles.rowValue, mono && styles.mono]} numberOfLines={1}>
        {value}
      </Text>
    </View>
  );
}

export function Button({
  title,
  onPress,
  disabled,
  tone = 'primary',
}: {
  title: string;
  onPress: () => void;
  disabled?: boolean;
  tone?: 'primary' | 'danger' | 'neutral';
}) {
  return (
    <TouchableOpacity
      style={[
        styles.button,
        tone === 'danger' && styles.buttonDanger,
        tone === 'neutral' && styles.buttonNeutral,
        disabled && styles.buttonDisabled,
      ]}
      onPress={onPress}
      disabled={disabled}
    >
      <Text style={styles.buttonText}>{title}</Text>
    </TouchableOpacity>
  );
}

export function Field({
  label,
  value,
  onChangeText,
  placeholder,
  keyboardType,
  hint,
}: {
  label: string;
  value: string;
  onChangeText: (text: string) => void;
  placeholder?: string;
  keyboardType?: 'default' | 'numeric';
  hint?: string;
}) {
  return (
    <View style={styles.field}>
      <Text style={styles.fieldLabel}>{label}</Text>
      <TextInput
        style={styles.input}
        value={value}
        onChangeText={onChangeText}
        placeholder={placeholder}
        placeholderTextColor="#9aa0a6"
        keyboardType={keyboardType ?? 'default'}
        autoCapitalize="none"
        autoCorrect={false}
      />
      {hint ? <Text style={styles.hint}>{hint}</Text> : null}
    </View>
  );
}

export function Toggle({
  label,
  value,
  onValueChange,
  hint,
}: {
  label: string;
  value: boolean;
  onValueChange: (value: boolean) => void;
  hint?: string;
}) {
  return (
    <View style={styles.toggleWrap}>
      <View style={styles.toggleRow}>
        <Text style={styles.toggleLabel}>{label}</Text>
        <Switch value={value} onValueChange={onValueChange} />
      </View>
      {hint ? <Text style={styles.hint}>{hint}</Text> : null}
    </View>
  );
}

export function Segmented<T extends string>({
  options,
  value,
  onChange,
}: {
  options: { key: T; label: string }[];
  value: T;
  onChange: (value: T) => void;
}) {
  return (
    <View style={styles.segmented}>
      {options.map((option) => (
        <TouchableOpacity
          key={option.key}
          style={[
            styles.segment,
            value === option.key && styles.segmentActive,
          ]}
          onPress={() => onChange(option.key)}
        >
          <Text
            style={[
              styles.segmentText,
              value === option.key && styles.segmentTextActive,
            ]}
          >
            {option.label}
          </Text>
        </TouchableOpacity>
      ))}
    </View>
  );
}

export function Dropdown<T extends string>({
  label,
  options,
  value,
  placeholder,
  onChange,
}: {
  label?: string;
  options: { key: T; label: string; detail?: string }[];
  value: T | null;
  placeholder?: string;
  onChange: (value: T) => void;
}) {
  const [open, setOpen] = useState(false);
  const selected = options.find((option) => option.key === value);

  return (
    <View style={styles.field}>
      {label ? <Text style={styles.fieldLabel}>{label}</Text> : null}
      <TouchableOpacity style={styles.dropdown} onPress={() => setOpen(true)}>
        <Text style={[styles.dropdownText, !selected && styles.dropdownPlaceholder]}>
          {selected?.label ?? placeholder ?? 'Select…'}
        </Text>
        <Text style={styles.dropdownChevron}>▾</Text>
      </TouchableOpacity>

      <Modal visible={open} transparent animationType="fade" onRequestClose={() => setOpen(false)}>
        {/* The backdrop is the dismiss target, so there is no close button to miss. */}
        <Pressable style={styles.backdrop} onPress={() => setOpen(false)}>
          <Pressable style={styles.sheet}>
            {label ? <Text style={styles.sheetTitle}>{label}</Text> : null}
            <ScrollView>
              {options.map((option) => (
                <TouchableOpacity
                  key={option.key}
                  style={[styles.option, option.key === value && styles.optionActive]}
                  onPress={() => {
                    onChange(option.key);
                    setOpen(false);
                  }}
                >
                  <Text
                    style={[
                      styles.optionLabel,
                      option.key === value && styles.optionLabelActive,
                    ]}
                  >
                    {option.label}
                  </Text>
                  {option.detail ? (
                    <Text style={styles.optionDetail}>{option.detail}</Text>
                  ) : null}
                </TouchableOpacity>
              ))}
            </ScrollView>
          </Pressable>
        </Pressable>
      </Modal>
    </View>
  );
}

export function Note({ children }: { children: React.ReactNode }) {
  return <Text style={styles.note}>{children}</Text>;
}

export function Banner({ tone, children }: { tone: 'error' | 'warn'; children: React.ReactNode }) {
  return (
    <View style={[styles.banner, tone === 'warn' && styles.bannerWarn]}>
      <Text style={styles.bannerText}>{children}</Text>
    </View>
  );
}

export const styles = StyleSheet.create({
  card: {
    backgroundColor: '#ffffff',
    borderRadius: 12,
    padding: 16,
    marginHorizontal: 16,
    marginBottom: 12,
    shadowColor: '#000',
    shadowOpacity: 0.06,
    shadowRadius: 8,
    shadowOffset: { width: 0, height: 2 },
    elevation: 2,
  },
  cardTitle: {
    fontSize: 16,
    fontWeight: '600',
    color: '#1f2328',
    marginBottom: 12,
  },
  row: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingVertical: 4,
  },
  rowLabel: { fontSize: 14, color: '#57606a', flexShrink: 0, marginRight: 12 },
  rowValue: { fontSize: 14, color: '#1f2328', flexShrink: 1, textAlign: 'right' },
  mono: { fontFamily: 'Courier', fontSize: 12 },
  button: {
    backgroundColor: '#0969da',
    borderRadius: 8,
    paddingVertical: 12,
    paddingHorizontal: 16,
    alignItems: 'center',
    marginTop: 8,
  },
  buttonDanger: { backgroundColor: '#cf222e' },
  buttonNeutral: { backgroundColor: '#57606a' },
  buttonDisabled: { backgroundColor: '#c7cdd4' },
  buttonText: { color: '#ffffff', fontSize: 15, fontWeight: '600' },
  field: { marginBottom: 12 },
  fieldLabel: { fontSize: 13, color: '#57606a', marginBottom: 6 },
  input: {
    borderWidth: 1,
    borderColor: '#d0d7de',
    borderRadius: 8,
    paddingHorizontal: 12,
    paddingVertical: 10,
    fontSize: 15,
    color: '#1f2328',
    backgroundColor: '#f6f8fa',
  },
  hint: { fontSize: 12, color: '#8b949e', marginTop: 6, lineHeight: 16 },
  toggleWrap: { marginBottom: 12 },
  toggleRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
  },
  toggleLabel: { fontSize: 15, color: '#1f2328' },
  segmented: {
    flexDirection: 'row',
    backgroundColor: '#eaeef2',
    borderRadius: 8,
    padding: 3,
    marginBottom: 12,
  },
  segment: {
    flex: 1,
    paddingVertical: 8,
    borderRadius: 6,
    alignItems: 'center',
  },
  segmentActive: { backgroundColor: '#ffffff' },
  segmentText: { fontSize: 13, color: '#57606a', fontWeight: '500' },
  segmentTextActive: { color: '#0969da', fontWeight: '600' },
  dropdown: {
    borderWidth: 1,
    borderColor: '#d0d7de',
    borderRadius: 8,
    paddingHorizontal: 12,
    paddingVertical: 12,
    backgroundColor: '#f6f8fa',
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
  },
  dropdownText: { fontSize: 15, color: '#1f2328', flexShrink: 1 },
  dropdownPlaceholder: { color: '#9aa0a6' },
  dropdownChevron: { fontSize: 14, color: '#57606a', marginLeft: 8 },
  backdrop: {
    flex: 1,
    backgroundColor: 'rgba(0,0,0,0.35)',
    justifyContent: 'center',
    paddingHorizontal: 24,
  },
  sheet: {
    backgroundColor: '#ffffff',
    borderRadius: 12,
    paddingVertical: 8,
    maxHeight: '70%',
  },
  sheetTitle: {
    fontSize: 13,
    fontWeight: '600',
    color: '#57606a',
    paddingHorizontal: 16,
    paddingTop: 8,
    paddingBottom: 4,
  },
  option: { paddingHorizontal: 16, paddingVertical: 12 },
  optionActive: { backgroundColor: '#ddf4ff' },
  optionLabel: { fontSize: 15, color: '#1f2328' },
  optionLabelActive: { color: '#0969da', fontWeight: '600' },
  optionDetail: { fontSize: 12, color: '#8b949e', marginTop: 2 },
  note: { fontSize: 12, color: '#8b949e', marginTop: 8, lineHeight: 17 },
  banner: {
    backgroundColor: '#ffebe9',
    borderColor: '#cf222e',
    borderWidth: 1,
    borderRadius: 8,
    padding: 12,
    marginHorizontal: 16,
    marginBottom: 12,
  },
  bannerWarn: { backgroundColor: '#fff8c5', borderColor: '#d4a72c' },
  bannerText: { fontSize: 13, color: '#1f2328', lineHeight: 18 },
});
