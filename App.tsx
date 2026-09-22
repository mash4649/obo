import { StatusBar } from 'expo-status-bar';
import { useState } from 'react';
import { ActivityIndicator, Button, Linking, StyleSheet, Switch, Text, TextInput, View } from 'react-native';

import { acceptConsent, captureText, type AuthState, CommandError, getAuthState, startRecentAuth, verifyRecentAuth, withdrawConsent } from './src/auth/command';
import { AuthError, requestEmailOtp, verifyEmailOtp } from './src/auth/emailOtp';
import { type CaptureScope } from './src/sensitivity/preflight';

export default function App() {
  const [email, setEmail] = useState('');
  const [code, setCode] = useState('');
  const [codeSentTo, setCodeSentTo] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState<string | null>(null);
  const [verified, setVerified] = useState(false);
  const [authState, setAuthState] = useState<AuthState | null>(null);
  const [adultDeclared, setAdultDeclared] = useState(false);
  const [recentAuthCode, setRecentAuthCode] = useState<string | null>(null);
  const [withdrawalProof, setWithdrawalProof] = useState<string | null>(null);
  const [captureScope, setCaptureScope] = useState<CaptureScope>('GENERAL_ADMIN');
  const [captureBody, setCaptureBody] = useState('');

  async function sendCode() {
    setBusy(true);
    setMessage(null);

    try {
      setCodeSentTo(await requestEmailOtp(email));
      setCode('');
    } catch (error) {
      setMessage(error instanceof AuthError ? error.message : '認証を開始できませんでした。');
    } finally {
      setBusy(false);
    }
  }

  async function verifyCode() {
    if (!codeSentTo) {
      return;
    }

    setBusy(true);
    setMessage(null);

    try {
      await verifyEmailOtp(codeSentTo, code);
      setAuthState(await getAuthState());
      setVerified(true);
    } catch (error) {
      setMessage(error instanceof AuthError ? error.message : '認証を完了できませんでした。');
    } finally {
      setBusy(false);
    }
  }

  async function submitConsent() {
    const timezone = Intl.DateTimeFormat().resolvedOptions().timeZone;
    if (!timezone) {
      setMessage('タイムゾーンを確認できませんでした。');
      return;
    }

    setBusy(true);
    setMessage(null);

    try {
      await acceptConsent(timezone, adultDeclared);
      setAuthState(await getAuthState());
    } catch (error) {
      setMessage(error instanceof CommandError ? error.message : '同意を記録できませんでした。');
    } finally {
      setBusy(false);
    }
  }

  async function requestWithdrawalAuth() {
    setBusy(true);
    setMessage(null);

    try {
      await startRecentAuth('WITHDRAW_CONSENT');
      setRecentAuthCode('');
    } catch (error) {
      setMessage(error instanceof CommandError ? error.message : '再認証を開始できませんでした。');
    } finally {
      setBusy(false);
    }
  }

  async function submitRecentAuth() {
    if (recentAuthCode === null) {
      return;
    }

    setBusy(true);
    setMessage(null);

    try {
      setWithdrawalProof(await verifyRecentAuth('WITHDRAW_CONSENT', recentAuthCode));
      setRecentAuthCode(null);
    } catch (error) {
      setMessage(error instanceof CommandError ? error.message : '再認証を確認できませんでした。');
    } finally {
      setBusy(false);
    }
  }

  async function confirmWithdrawal() {
    if (!withdrawalProof) {
      return;
    }

    setBusy(true);
    setMessage(null);

    try {
      await withdrawConsent(withdrawalProof);
      setAuthState(null);
      setCode('');
      setCodeSentTo(null);
      setRecentAuthCode(null);
      setVerified(false);
      setWithdrawalProof(null);
    } catch (error) {
      setMessage(error instanceof CommandError ? error.message : '同意を撤回できませんでした。');
    } finally {
      setBusy(false);
    }
  }

  async function submitCapture() {
    setBusy(true);
    setMessage(null);

    try {
      const status = await captureText(captureScope, captureBody);
      setCaptureBody('');
      setMessage(status === 'STORED'
        ? '保存しました。'
        : 'この内容は処理できません。危険情報を除いて、必要なら入力し直してください。');
    } catch (error) {
      setMessage(error instanceof CommandError ? error.message : '保存を完了できませんでした。');
    } finally {
      setBusy(false);
    }
  }

  const consentIsCurrent = authState?.consent?.status === 'ACCEPTED'
    && authState.consent.version === authState.requiredConsentVersion;

  return (
    <View style={styles.container}>
      <Text style={styles.title}>OBO</Text>
      {verified ? (
        <>
          {!authState ? <ActivityIndicator /> : null}
          {authState && !authState.participant ? (
            <Text style={styles.copy}>このアカウントは P1 参加者として登録されていません。</Text>
          ) : null}
          {authState && authState.participant && !consentIsCurrent && !authState.consentDocumentUrl ? (
            <Text style={styles.copy}>同意文書の表示設定が完了していません。OBO は情報を保存しません。</Text>
          ) : null}
          {authState && authState.participant && !consentIsCurrent && authState.consentDocumentUrl ? (
            <>
              <Text style={styles.copy}>同意文書 version: {authState.requiredConsentVersion ?? '未設定'}</Text>
              <Button onPress={() => Linking.openURL(authState.consentDocumentUrl!)} title="同意文書を開く" />
              <View style={styles.switchRow}>
                <Switch onValueChange={setAdultDeclared} value={adultDeclared} />
                <Text style={styles.switchText}>私は18歳以上で、同意文書を確認しました。</Text>
              </View>
              <Button disabled={busy || !adultDeclared || !authState.requiredConsentVersion} onPress={submitConsent} title="同意して開始する" />
            </>
          ) : null}
          {authState && authState.participant && consentIsCurrent && !recentAuthCode && !withdrawalProof ? (
            <>
              <Text style={styles.copy}>同意済みです。OBO は必要な情報だけを保存します。</Text>
              <TextInput
                accessibilityLabel="保存する内容"
                maxLength={2000}
                multiline
                onChangeText={setCaptureBody}
                placeholder="予定や用事を入力"
                style={styles.input}
                value={captureBody}
              />
              <View style={styles.scopeRow}>
                {(['SCHEDULE', 'HOUSEHOLD', 'SHOPPING', 'GENERAL_ADMIN'] as const).map((scope) => (
                  <Button
                    key={scope}
                    color={scope === captureScope ? '#2255aa' : undefined}
                    onPress={() => setCaptureScope(scope)}
                    title={scope}
                  />
                ))}
              </View>
              <Button disabled={busy || !captureBody.trim()} onPress={submitCapture} title="保存する" />
              <Button disabled={busy} onPress={requestWithdrawalAuth} title="同意を撤回する" />
            </>
          ) : null}
          {recentAuthCode !== null ? (
            <>
              <Text style={styles.copy}>撤回を続けるには、届いた6桁の認証コードを入力してください。</Text>
              <TextInput
                accessibilityLabel="撤回の認証コード"
                autoComplete="one-time-code"
                keyboardType="number-pad"
                maxLength={6}
                onChangeText={setRecentAuthCode}
                placeholder="6桁の認証コード"
                style={styles.input}
                value={recentAuthCode}
              />
              <Button disabled={busy} onPress={submitRecentAuth} title="撤回の再認証を確認する" />
            </>
          ) : null}
          {withdrawalProof ? (
            <>
              <Text style={styles.copy}>同意を撤回すると、以後の保存・処理・配信を停止します。</Text>
              <Button disabled={busy} onPress={confirmWithdrawal} title="同意を撤回する" />
            </>
          ) : null}
          {message ? <Text accessibilityRole="alert" style={styles.error}>{message}</Text> : null}
        </>
      ) : (
        <>
          <Text style={styles.copy}>事前登録済みのメールアドレスで認証してください。</Text>
          {codeSentTo ? (
            <>
              <TextInput
                accessibilityLabel="認証コード"
                autoComplete="one-time-code"
                keyboardType="number-pad"
                maxLength={6}
                onChangeText={setCode}
                placeholder="6桁の認証コード"
                style={styles.input}
                value={code}
              />
              <Button disabled={busy} onPress={verifyCode} title="認証する" />
              <Button disabled={busy} onPress={() => setCodeSentTo(null)} title="メールアドレスを変更" />
            </>
          ) : (
            <>
              <TextInput
                accessibilityLabel="メールアドレス"
                autoCapitalize="none"
                autoComplete="email"
                keyboardType="email-address"
                onChangeText={setEmail}
                placeholder="メールアドレス"
                style={styles.input}
                value={email}
              />
              <Button disabled={busy} onPress={sendCode} title="認証コードを送る" />
            </>
          )}
          {busy ? <ActivityIndicator /> : null}
          {message ? <Text accessibilityRole="alert" style={styles.error}>{message}</Text> : null}
        </>
      )}
      <StatusBar style="auto" />
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    alignItems: 'stretch',
    backgroundColor: '#fff',
    flex: 1,
    justifyContent: 'center',
    padding: 24,
  },
  title: {
    alignSelf: 'center',
    fontSize: 24,
    fontWeight: '600',
  },
  copy: {
    marginBottom: 16,
    marginTop: 8,
    textAlign: 'center',
  },
  error: {
    color: '#a30000',
    marginTop: 16,
    textAlign: 'center',
  },
  input: {
    borderColor: '#777',
    borderRadius: 4,
    borderWidth: 1,
    marginBottom: 12,
    padding: 12,
  },
  switchRow: {
    alignItems: 'center',
    flexDirection: 'row',
    marginVertical: 16,
  },
  switchText: {
    flex: 1,
    marginLeft: 8,
  },
  scopeRow: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 8,
    justifyContent: 'center',
    marginBottom: 12,
  },
});
