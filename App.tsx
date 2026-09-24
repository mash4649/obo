import { StatusBar } from 'expo-status-bar';
import * as ScreenCapture from 'expo-screen-capture';
import { useEffect, useState } from 'react';
import { ActivityIndicator, AppState, Button, Linking, Platform, ScrollView, StyleSheet, Switch, Text, TextInput, View } from 'react-native';

import { acceptConsent, ackOffloadReceipt, actOnLoop, captureText, correctLoop, type AuthState, type CaptureSummary, CommandError, deleteAccount, deleteRawCapture, formatLocalEvaluationDate, getAuthState, listCaptures, listInAppDeliveries, listOpenLoops, listOutcomeFlags, localEvaluationDate, type OpenLoop, recordOwnership, requestInterpretation, startRecentAuth, verifyRecentAuth, withdrawConsent } from './src/auth/command';
import { AuthError, requestEmailOtp, verifyEmailOtp } from './src/auth/emailOtp';
import { getSupabase } from './src/auth/supabase';
import { checkPushPermission, clearPushPreference, disablePush, enablePush, isPushOptedIn } from './src/push/registration';

export default function App() {
  const [email, setEmail] = useState('');
  const [code, setCode] = useState('');
  const [codeSentTo, setCodeSentTo] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [page, setPage] = useState<'home' | 'capture' | 'receipt' | 'tracking' | 'context' | 'settings'>('home');
  const [selectedLoopId, setSelectedLoopId] = useState<string | null>(null);
  const [verified, setVerified] = useState(false);
  const [authState, setAuthState] = useState<AuthState | null>(null);
  const [adultDeclared, setAdultDeclared] = useState(false);
  const [recentAuthCode, setRecentAuthCode] = useState<string | null>(null);
  const [withdrawalProof, setWithdrawalProof] = useState<string | null>(null);
  const [destructiveAction, setDestructiveAction] = useState<'WITHDRAW_CONSENT' | 'DELETE_RAW_CAPTURE' | 'DELETE_ACCOUNT'>('WITHDRAW_CONSENT');
  const [captureToDelete, setCaptureToDelete] = useState<string | null>(null);
  const [captures, setCaptures] = useState<CaptureSummary[]>([]);
  const [captureBody, setCaptureBody] = useState('');
  const [openLoops, setOpenLoops] = useState<OpenLoop[]>([]);
  const [correctingLoopId, setCorrectingLoopId] = useState<string | null>(null);
  const [correctedState, setCorrectedState] = useState('');
  const [correctedNextEvaluation, setCorrectedNextEvaluation] = useState('');
  const [confirmationAnswer, setConfirmationAnswer] = useState('');
  const [attentionLoopIds, setAttentionLoopIds] = useState<string[]>([]);
  const [socLoopIds, setSocLoopIds] = useState<string[]>([]);
  const [measuredLoopIds, setMeasuredLoopIds] = useState<string[]>([]);
  const [foreground, setForeground] = useState(AppState.currentState === 'active');
  const [snapshotReady, setSnapshotReady] = useState(Platform.OS !== 'ios' && Platform.OS !== 'android');
  const [pushOptedIn, setPushOptedIn] = useState(false);

  useEffect(() => {
    const protection = Platform.OS === 'ios'
      ? ScreenCapture.enableAppSwitcherProtectionAsync(1)
      : Platform.OS === 'android'
        ? ScreenCapture.preventScreenCaptureAsync()
        : Promise.resolve();
    protection
      .then(() => setSnapshotReady(true))
      .catch(() => setMessage('安全な表示を開始できませんでした。'));
  }, []);

  useEffect(() => {
    const change = AppState.addEventListener('change', (state) => setForeground(state === 'active'));
    const blur = AppState.addEventListener('blur', () => setForeground(false));
    const focus = AppState.addEventListener('focus', () => setForeground(true));
    return () => { change.remove(); blur.remove(); focus.remove(); };
  }, []);

  useEffect(() => {
    if (!foreground || !verified || !pushOptedIn) return;
    checkPushPermission()
      .then(() => isPushOptedIn())
      .then(setPushOptedIn)
      .catch(() => {});
  }, [foreground, verified, pushOptedIn]);

  async function togglePush() {
    setBusy(true);
    setMessage(null);
    try {
      if (pushOptedIn) await disablePush();
      else await enablePush();
      setPushOptedIn(await isPushOptedIn());
    } catch {
      setMessage('Push を設定できませんでした。アプリ内で確認できます。');
    } finally {
      setBusy(false);
    }
  }

  async function signOut() {
    setBusy(true);
    setMessage(null);
    try {
      await disablePush();
      const { error } = await getSupabase()!.auth.signOut();
      if (error) throw error;
      setPushOptedIn(false);
      setVerified(false);
      setAuthState(null);
      setOpenLoops([]);
      setCaptures([]);
      setAttentionLoopIds([]);
      setSocLoopIds([]);
      setMeasuredLoopIds([]);
      setCaptureBody('');
      setConfirmationAnswer('');
      setNotice(null);
      setPage('home');
      setSelectedLoopId(null);
      setEmail('');
      setCode('');
      setCodeSentTo(null);
    } catch {
      setMessage('ログアウトを完了できませんでした。');
    } finally {
      setBusy(false);
    }
  }

  async function refreshLoops(): Promise<OpenLoop[]> {
    const [loops, deliveries, flags, savedCaptures] = await Promise.all([listOpenLoops(), listInAppDeliveries(), listOutcomeFlags(), listCaptures()]);
    setOpenLoops(loops);
    setAttentionLoopIds(deliveries.map((delivery) => delivery.loop_id));
    setSocLoopIds(flags.socLoopIds);
    setMeasuredLoopIds(flags.measuredLoopIds);
    setCaptures(savedCaptures);
    return loops;
  }

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
      setPushOptedIn(await isPushOptedIn());
      await refreshLoops();
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
      await refreshLoops();
    } catch (error) {
      setMessage(error instanceof CommandError ? error.message : '同意を記録できませんでした。');
    } finally {
      setBusy(false);
    }
  }

  async function requestDestructiveAuth(action: 'WITHDRAW_CONSENT' | 'DELETE_RAW_CAPTURE' | 'DELETE_ACCOUNT', captureId: string | null = null) {
    setBusy(true);
    setMessage(null);

    try {
      await startRecentAuth(action);
      setDestructiveAction(action);
      setCaptureToDelete(captureId);
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
      setWithdrawalProof(await verifyRecentAuth(destructiveAction, recentAuthCode));
      setRecentAuthCode(null);
    } catch (error) {
      setMessage(error instanceof CommandError ? error.message : '再認証を確認できませんでした。');
    } finally {
      setBusy(false);
    }
  }

  async function confirmDestructiveAction() {
    if (!withdrawalProof) {
      return;
    }

    setBusy(true);
    setMessage(null);
    setNotice(null);

    try {
      if (destructiveAction === 'DELETE_RAW_CAPTURE' && captureToDelete) {
        const status = await deleteRawCapture(captureToDelete, withdrawalProof);
        setNotice(status === 'DELETED' ? '入力のRawを削除しました。' : 'Rawの削除を続けています。');
        await refreshLoops();
      } else {
        if (destructiveAction === 'DELETE_RAW_CAPTURE') throw new CommandError('削除対象を確認できませんでした。');
        let status: 'DELETED' | 'DELETION_PENDING' = 'DELETION_PENDING';
        if (destructiveAction === 'DELETE_ACCOUNT') {
          status = await deleteAccount(withdrawalProof);
        } else {
          await withdrawConsent(withdrawalProof);
        }
        await clearPushPreference();
        setPushOptedIn(false);
        setAuthState(null);
        setEmail('');
        setCode('');
        setCodeSentTo(null);
        setCaptureBody('');
        setCorrectedState('');
        setCorrectedNextEvaluation('');
        setCorrectingLoopId(null);
        setVerified(false);
        setOpenLoops([]);
        setCaptures([]);
        setAttentionLoopIds([]);
        setSocLoopIds([]);
        setMeasuredLoopIds([]);
        setMessage(status === 'DELETED' ? 'アカウントを削除しました。' : '削除を続けています。');
      }
      setRecentAuthCode(null);
      setWithdrawalProof(null);
      setCaptureToDelete(null);
    } catch (error) {
      setMessage(error instanceof CommandError ? error.message : '操作を完了できませんでした。');
    } finally {
      setBusy(false);
    }
  }

  async function submitCapture() {
    setBusy(true);
    setMessage(null);
    setNotice(null);

    try {
      const { captureId, status } = await captureText(captureBody);
      setCaptureBody('');
      if (status !== 'STORED') {
        await refreshLoops().catch(() => {});
        setMessage('この内容は処理できません。危険情報を除いて、必要なら入力し直してください。');
        return;
      }
      setNotice('預かりました。内容は保存されています。');
      setPage('receipt');
      await refreshLoops().catch(() => setMessage('保存しましたが、表示を更新できませんでした。'));
      if (process.env.EXPO_PUBLIC_P1_AI_ENABLED === 'true') {
        try {
          await requestInterpretation(captureId);
          const loops = await refreshLoops();
          const loop = loops.find((item) => item.capture_id === captureId);
          if (loop) {
            setSelectedLoopId(loop.id);
            setPage('context');
          }
        } catch {
          setMessage('内容を整理できませんでした。追跡は始まっていません。');
        }
      }
    } catch (error) {
      setMessage(error instanceof CommandError ? error.message : '保存を完了できませんでした。');
    } finally {
      setBusy(false);
    }
  }

  async function submitCorrection(loop: OpenLoop) {
    setBusy(true);
    setMessage(null);
    try {
      await correctLoop(loop.id, correctedState.trim(), loop.due_at, localEvaluationDate(correctedNextEvaluation));
      setCorrectingLoopId(null);
      setCorrectedState('');
      setCorrectedNextEvaluation('');
      await refreshLoops();
    } catch (error) {
      setMessage(error instanceof CommandError ? error.message : '訂正を保存できませんでした。');
    } finally { setBusy(false); }
  }

  async function submitConfirmation(loop: OpenLoop) {
    setBusy(true);
    setMessage(null);
    setNotice(null);
    try {
      if (Boolean(loop.expected_state_text) === Boolean(loop.next_evaluation_at)) {
        throw new CommandError('この確認には直接回答できません。内容を訂正してください。');
      }
      const expectedState = loop.expected_state_text || confirmationAnswer.trim();
      const nextEvaluation = loop.next_evaluation_at || localEvaluationDate(confirmationAnswer.trim());
      await correctLoop(loop.id, expectedState, loop.due_at, nextEvaluation);
      setConfirmationAnswer('');
      await refreshLoops();
      setNotice('内容を更新しました。追跡内容を確認してください。');
    } catch (error) {
      setMessage(error instanceof CommandError ? error.message : '回答を保存できませんでした。');
    } finally { setBusy(false); }
  }

  async function confirmReceipt(loop: OpenLoop) {
    setBusy(true);
    setMessage(null);
    setNotice(null);
    try {
      const status = await ackOffloadReceipt(loop.id, loop.revision);
      await refreshLoops();
      if (status === 'ACKED') setNotice('この件はOBOが覚えておきます。');
      else setMessage('内容が更新されました。新しい内容を確認してください。');
    } catch (error) {
      setMessage(error instanceof CommandError ? error.message : '確認を保存できませんでした。');
    } finally { setBusy(false); }
  }

  async function submitLoopAction(loop: OpenLoop, action: 'MARK_DONE' | 'MARK_NOT_YET' | 'END_CONTEXT' | 'REOPEN_CONTEXT') {
    setBusy(true);
    setMessage(null);
    try {
      await actOnLoop(loop.id, action);
      await refreshLoops();
    } catch (error) {
      setMessage(error instanceof CommandError ? error.message : '状態を更新できませんでした。');
    } finally { setBusy(false); }
  }

  async function submitOwnership(loop: OpenLoop, result: 'OWNED' | 'PARALLEL' | 'UNKNOWN') {
    setBusy(true);
    setMessage(null);
    try {
      await recordOwnership(loop.id, result);
      await refreshLoops();
    } catch (error) {
      setMessage(error instanceof CommandError ? error.message : '回答を保存できませんでした。');
    } finally { setBusy(false); }
  }

  const consentIsCurrent = authState?.consent?.status === 'ACCEPTED'
    && authState.consent.version === authState.requiredConsentVersion;
  const selectedLoop = openLoops.find((loop) => loop.id === selectedLoopId);
  const nextLoop = openLoops.find((loop) => loop.status === 'ACTIVE' && attentionLoopIds.includes(loop.id))
    ?? openLoops.find((loop) => loop.status === 'ACTIVE' && !!loop.confirmation_question)
    ?? openLoops.find((loop) => loop.status === 'ACTIVE' && !loop.activated_at);

  return (
    <View style={styles.screen}>
    <ScrollView contentContainerStyle={styles.container}>
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
              {page === 'home' ? (
                <>
                  <Text style={styles.copy}>{nextLoop
                    ? '確認が必要な件があります。'
                    : captures.some((capture) => capture.status === 'STORED')
                      ? '保存された入力があります。追跡はまだ始まっていません。'
                      : captures.some((capture) => capture.status === 'FAILED_SAFE')
                        ? '処理できなかった入力があります。必要なら預け直してください。'
                        : captures.length === 0 && openLoops.length === 0
                          ? 'まず、覚えておいてほしいことを預けてください。'
                          : '今、確認が必要なことはありません。'}</Text>
                  {nextLoop ? <Button onPress={() => { setSelectedLoopId(nextLoop.id); setPage('context'); }} title="次の確認を見る" /> : null}
                  <Button onPress={() => setPage('capture')} title="預ける" />
                  <Button disabled={busy} onPress={() => refreshLoops().catch(() => setMessage('件を読み込めませんでした。'))} title="表示を更新" />
                  <Button onPress={() => setPage('tracking')} title="OBOが追っていること" />
                  <Button onPress={() => setPage('settings')} title="設定・プライバシー" />
                </>
              ) : null}
              {page === 'capture' ? (
                <>
                  <Text style={styles.heading}>預ける</Text>
                  <TextInput
                    accessibilityLabel="預ける内容"
                    maxLength={2000}
                    multiline
                    onChangeText={setCaptureBody}
                    placeholder="予定や用事を入力"
                    style={styles.input}
                    value={captureBody}
                  />
                  <Button disabled={busy || !captureBody.trim()} onPress={submitCapture} title="預ける" />
                  <Button onPress={() => setPage('home')} title="Homeへ戻る" />
                </>
              ) : null}
              {page === 'receipt' ? (
                <>
                  <Text style={styles.heading}>預かりました</Text>
                  <Text style={styles.copy}>内容は保存されています。追跡はまだ始まっていません。</Text>
                  {process.env.EXPO_PUBLIC_P1_AI_ENABLED !== 'true' ? (
                    <Text style={styles.copy}>このプレビューでは内容の整理と追跡開始を利用できません。</Text>
                  ) : null}
                  <Button onPress={() => setPage('home')} title="Homeへ戻る" />
                </>
              ) : null}
              {page === 'tracking' ? (
                <>
                  <Text style={styles.heading}>OBOが追っていること</Text>
                  {openLoops.filter((loop) => loop.status === 'ACTIVE' && !!loop.activated_at).length === 0
                    ? <Text style={styles.copy}>追跡中の件はありません。</Text> : null}
                  {openLoops.map((loop) => (
                    <Button key={loop.id} onPress={() => { setSelectedLoopId(loop.id); setPage('context'); }}
                      title={`${loop.title}：${loop.status === 'CLOSED' ? 'これまで' : loop.activated_at ? '追跡中' : '確認待ち'}`} />
                  ))}
                  <Button disabled={busy} onPress={() => refreshLoops().catch(() => setMessage('件を読み込めませんでした。'))} title="表示を更新" />
                  <Button onPress={() => setPage('home')} title="Homeへ戻る" />
                </>
              ) : null}
              {page === 'context' && selectedLoop ? (
                <>
                  <Button onPress={() => setPage('tracking')} title="追跡内容へ戻る" />
                  <Text style={styles.heading}>{selectedLoop.title}</Text>
                  {openLoops.filter((loop) => loop.id === selectedLoopId).map((loop) => (
                  <View key={loop.id}>
                  {attentionLoopIds.includes(loop.id) && loop.status === 'ACTIVE' ? <Text style={styles.copy}>確認待ちの件があります。</Text> : null}
                  <Text style={styles.copy}>実現を待つ状態: {loop.expected_state_text || '確認が必要です'}</Text>
                  <Text style={styles.copy}>日付: {loop.due_at ? new Date(loop.due_at).toLocaleString('ja-JP') : '未設定'}</Text>
                  <Text style={styles.copy}>次の確認: {loop.next_evaluation_at ? new Date(loop.next_evaluation_at).toLocaleString('ja-JP') : '確認が必要です'}</Text>
                  <Text style={styles.copy}>OBO が確認すること: 状態が変わったかを次の評価時に確認します。</Text>
                  <Text style={styles.copy}>今必要なこと: {loop.confirmation_question ?? (loop.activated_at ? '今はありません。' : 'この内容で追跡を始めるか確認してください。')}</Text>
                  {loop.confirmation_question && Boolean(loop.expected_state_text) !== Boolean(loop.next_evaluation_at) ? (
                    <>
                      <TextInput accessibilityLabel="確認への回答" onChangeText={setConfirmationAnswer}
                        placeholder={loop.next_evaluation_at ? '済んだと判断できる状態' : 'YYYY-MM-DD HH:mm'}
                        style={styles.input} value={confirmationAnswer} />
                      <Button disabled={busy || !confirmationAnswer.trim()} onPress={() => submitConfirmation(loop)} title="回答を保存" />
                    </>
                  ) : null}
                  {loop.confirmation_question && Boolean(loop.expected_state_text) === Boolean(loop.next_evaluation_at) ? (
                    <Text style={styles.copy}>この確認には直接回答できません。内容を訂正してください。</Text>
                  ) : null}
                  {loop.confirmation_question || loop.status !== 'ACTIVE' ? null : (
                    <>
                      {!loop.activated_at && process.env.EXPO_PUBLIC_P1_TRACKING_ENABLED !== 'true'
                        ? <Text style={styles.copy}>このプレビューでは追跡を開始できません。</Text> : null}
                      <Button disabled={busy || !!loop.activated_at || process.env.EXPO_PUBLIC_P1_TRACKING_ENABLED !== 'true'} onPress={() => confirmReceipt(loop)} title={loop.activated_at ? '追跡中' : 'この内容で追跡を始める'} />
                    </>
                  )}
                  {loop.status === 'ACTIVE' && correctingLoopId === loop.id ? (
                    <>
                      <TextInput accessibilityLabel="期待する状態を訂正" onChangeText={setCorrectedState} style={styles.input} value={correctedState} />
                      <TextInput accessibilityLabel="次回確認日時" onChangeText={setCorrectedNextEvaluation} placeholder="YYYY-MM-DD HH:mm" style={styles.input} value={correctedNextEvaluation} />
                      <Button disabled={busy || !correctedState.trim() || !correctedNextEvaluation.trim()} onPress={() => submitCorrection(loop)} title="訂正を保存" />
                    </>
                  ) : loop.status === 'ACTIVE' ? <Button disabled={busy} onPress={() => { setCorrectingLoopId(loop.id); setCorrectedState(loop.expected_state_text); setCorrectedNextEvaluation(formatLocalEvaluationDate(loop.next_evaluation_at)); }} title="内容を訂正" /> : null}
                  {loop.status === 'ACTIVE' && loop.activated_at ? (
                    <>
                      <Button disabled={busy} onPress={() => submitLoopAction(loop, 'MARK_DONE')} title="済んだ" />
                      <Button disabled={busy} onPress={() => submitLoopAction(loop, 'MARK_NOT_YET')} title="まだ" />
                    </>
                  ) : null}
                  {loop.status === 'ACTIVE' ? <Button disabled={busy} onPress={() => submitLoopAction(loop, 'END_CONTEXT')} title="この件を終える" /> : null}
                  {loop.status === 'CLOSED' ? <Button disabled={busy} onPress={() => submitLoopAction(loop, 'REOPEN_CONTEXT')} title="この件を再開する" /> : null}
                  {socLoopIds.includes(`${loop.id}:${loop.revision}`) && !measuredLoopIds.includes(`${loop.id}:${loop.revision}`) ? (
                    <>
                      <Text style={styles.copy}>この件の確認は、主にどの方法で行いましたか？</Text>
                      <Button disabled={busy} onPress={() => submitOwnership(loop, 'PARALLEL')} title="他の方法と併用した" />
                      <Button disabled={busy} onPress={() => submitOwnership(loop, 'OWNED')} title="OBOを主に使った" />
                      <Button disabled={busy} onPress={() => submitOwnership(loop, 'UNKNOWN')} title="わからない" />
                    </>
                  ) : null}
                  </View>))}
                </>
              ) : null}
              {page === 'context' && !selectedLoop ? <Button onPress={() => setPage('tracking')} title="追跡内容へ戻る" /> : null}
              {page === 'settings' ? (
                <>
                  <Text style={styles.heading}>設定・プライバシー</Text>
                  <Text style={styles.copy}>入力のRawだけを削除しても、追跡中の件は残ります。</Text>
                  {captures.filter((capture) => capture.status !== 'DELETED').map((capture) => (
                    <Button key={capture.id} disabled={busy}
                      onPress={() => requestDestructiveAuth('DELETE_RAW_CAPTURE', capture.id)}
                      title={`Rawを削除: ${new Date(capture.created_at).toLocaleString('ja-JP')}`} />
                  ))}
                  {process.env.EXPO_PUBLIC_P1_PUSH_CLIENT_ENABLED === 'true' ? (
                    <Button disabled={busy} onPress={togglePush}
                      title={pushOptedIn ? 'Push 通知を無効にする' : 'Push 通知を有効にする'} />
                  ) : null}
                  <Button disabled={busy} onPress={signOut} title="ログアウト" />
                  <Button disabled={busy} onPress={() => requestDestructiveAuth('WITHDRAW_CONSENT')} title="同意を撤回する" />
                  <Button disabled={busy} onPress={() => requestDestructiveAuth('DELETE_ACCOUNT')} title="アカウントを削除する" />
                  <Button onPress={() => setPage('home')} title="Homeへ戻る" />
                </>
              ) : null}
            </>
          ) : null}
          {recentAuthCode !== null ? (
            <>
              <Text style={styles.copy}>操作を続けるには、届いた6桁の認証コードを入力してください。</Text>
              <TextInput
                accessibilityLabel="操作の認証コード"
                autoComplete="one-time-code"
                keyboardType="number-pad"
                maxLength={6}
                onChangeText={setRecentAuthCode}
                placeholder="6桁の認証コード"
                style={styles.input}
                value={recentAuthCode}
              />
              <Button disabled={busy} onPress={submitRecentAuth} title="再認証を確認する" />
              <Button disabled={busy} onPress={() => { setRecentAuthCode(null); setWithdrawalProof(null); setCaptureToDelete(null); }} title="操作をやめる" />
            </>
          ) : null}
          {withdrawalProof ? (
            <>
              <Text style={styles.copy}>{destructiveAction === 'DELETE_RAW_CAPTURE'
                ? '入力のRawだけを削除します。追跡中の件は残ります。'
                : destructiveAction === 'DELETE_ACCOUNT'
                  ? 'アカウントと関連データを削除します。'
                  : '同意を撤回すると、以後の保存・処理・配信を停止します。'}</Text>
              <Button disabled={busy} onPress={confirmDestructiveAction} title="操作を確定する" />
              <Button disabled={busy} onPress={() => { setWithdrawalProof(null); setCaptureToDelete(null); }} title="操作をやめる" />
            </>
          ) : null}
          {notice ? <Text accessibilityLiveRegion="polite" style={styles.notice}>{notice}</Text> : null}
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
    </ScrollView>
    {!foreground || !snapshotReady ? <View accessibilityLabel="非表示中" style={styles.mask} /> : null}
    </View>
  );
}

const styles = StyleSheet.create({
  screen: { flex: 1 },
  mask: { ...StyleSheet.absoluteFill, backgroundColor: '#fff' },
  container: {
    alignItems: 'stretch',
    backgroundColor: '#fff',
    flexGrow: 1,
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
  heading: {
    fontSize: 22,
    fontWeight: '600',
    marginBottom: 16,
    textAlign: 'center',
  },
  notice: {
    color: '#205d3a',
    marginTop: 16,
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
});
