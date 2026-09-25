import * as Crypto from 'expo-crypto';
import { getSupabase } from './supabase';

export type AuthState = {
  account: { status: 'ACTIVE' | 'DELETION_PENDING' | 'DELETED' } | null;
  consent: { status: 'ACCEPTED' | 'WITHDRAWN'; version: string } | null;
  consentDocumentUrl: string | null;
  participant: boolean;
  requiredConsentVersion: string | null;
};

type DestructiveAction = 'WITHDRAW_CONSENT' | 'DELETE_ACCOUNT';

export class CommandError extends Error {}

function idempotencyKey(): string {
  try {
    return Crypto.randomUUID();
  } catch {
    throw new CommandError('安全な操作を開始できません。');
  }
}

async function invoke<T>(body: Record<string, unknown>): Promise<T> {
  const supabase = getSupabase();
  if (!supabase) {
    throw new CommandError('認証設定がまだありません。');
  }

  const { data, error } = await supabase.functions.invoke<T>('command', { body });
  if (error || data === null) {
    throw new CommandError('操作を完了できませんでした。');
  }

  return data;
}

export async function getAuthState(): Promise<AuthState> {
  return invoke<AuthState>({ command: 'AUTH_STATE' });
}

export async function acceptConsent(timezone: string, adultDeclared: boolean): Promise<void> {
  if (!adultDeclared) {
    throw new CommandError('18歳以上であることの自己申告が必要です。');
  }

  await invoke({
    adultDeclared,
    command: 'ACCEPT_CONSENT',
    idempotencyKey: idempotencyKey(),
    timezone,
  });
}

export async function captureText(text: string): Promise<{ captureId: string; status: 'STORED' | 'FAILED_SAFE' }> {
  if (!text.trim()) {
    throw new CommandError('保存する内容を入力してください。');
  }

  const result = await invoke<{ captureId?: unknown; status?: unknown }>({
    command: 'CAPTURE_TEXT',
    idempotencyKey: idempotencyKey(),
    scope: 'UNCATEGORIZED',
    text,
  });

  if ((result.status !== 'STORED' && result.status !== 'FAILED_SAFE') || typeof result.captureId !== 'string') {
    throw new CommandError('保存を完了できませんでした。');
  }

  return { captureId: result.captureId, status: result.status };
}

export type OpenLoop = {
  id: string;
  capture_id: string;
  title: string;
  expected_state_text: string;
  due_at: string | null;
  next_evaluation_at: string | null;
  confirmation_question: string | null;
  revision: number;
  activated_at: string | null;
  effective_state: 'UNKNOWN' | 'UNSATISFIED' | 'SATISFIED' | 'CONFLICT' | 'NO_LONGER_REQUIRED';
  status: 'ACTIVE' | 'ENDING' | 'CLOSED';
};

export type CaptureSummary = { id: string; status: string; created_at: string };

export async function listCaptures(): Promise<CaptureSummary[]> {
  const supabase = getSupabase();
  if (!supabase) throw new CommandError('認証設定がまだありません。');
  const { data, error } = await supabase.from('captures')
    .select('id,status,created_at').order('created_at', { ascending: false });
  if (error) throw new CommandError('保存済みの内容を読み込めませんでした。');
  return (data ?? []) as CaptureSummary[];
}

export async function listOpenLoops(): Promise<OpenLoop[]> {
  const supabase = getSupabase();
  if (!supabase) throw new CommandError('認証設定がまだありません。');
  const { data, error } = await supabase.from('open_loops')
    .select('id,capture_id,title,expected_state_text,due_at,next_evaluation_at,confirmation_question,revision,activated_at,effective_state,status')
    .order('created_at', { ascending: false });
  if (error) throw new CommandError('追跡中の件を読み込めませんでした。');
  return (data ?? []) as OpenLoop[];
}

export type InAppDelivery = { id: string; loop_id: string; basis_revision: number };

export async function listInAppDeliveries(): Promise<InAppDelivery[]> {
  const supabase = getSupabase();
  if (!supabase) throw new CommandError('認証設定がまだありません。');
  const { data, error } = await supabase.from('deliveries')
    .select('id,loop_id,basis_revision').eq('channel', 'IN_APP').eq('status', 'PENDING');
  if (error) throw new CommandError('確認待ちの件を読み込めませんでした。');
  return (data ?? []) as InAppDelivery[];
}

export async function listOutcomeFlags(): Promise<{ socLoopIds: string[]; measuredLoopIds: string[] }> {
  const supabase = getSupabase();
  if (!supabase) throw new CommandError('認証設定がまだありません。');
  const { data, error } = await supabase.from('loop_events')
    .select('loop_id,event_type,basis_revision')
    .in('event_type', ['SOC_RECORDED', 'OWNERSHIP_MEASURED']);
  if (error) throw new CommandError('結果を読み込めませんでした。');
  return {
    socLoopIds: (data ?? []).filter((event) => event.event_type === 'SOC_RECORDED').map((event) => `${event.loop_id}:${event.basis_revision}`),
    measuredLoopIds: (data ?? []).filter((event) => event.event_type === 'OWNERSHIP_MEASURED').map((event) => `${event.loop_id}:${event.basis_revision}`),
  };
}

export type LoopAction = 'MARK_DONE' | 'MARK_NOT_YET' | 'END_CONTEXT' | 'REOPEN_CONTEXT';

export async function actOnLoop(loopId: string, command: LoopAction): Promise<void> {
  await invoke({ command, loopId });
}

export async function recordOwnership(loopId: string, result: 'OWNED' | 'PARALLEL' | 'UNKNOWN'): Promise<void> {
  await invoke({ command: 'RECORD_OWNERSHIP_MEASUREMENT', loopId, ownershipResult: result });
}

export async function deleteRawCapture(captureId: string): Promise<'DELETED' | 'DELETION_PENDING'> {
  const result = await invoke<{ status?: unknown }>({
    action: 'DELETE_RAW_CAPTURE', command: 'DELETE_RAW_CAPTURE', captureId,
  });
  if (result.status !== 'DELETED' && result.status !== 'DELETION_PENDING') throw new CommandError('削除を開始できませんでした。');
  return result.status;
}

export async function deleteAccount(proofId: string): Promise<'DELETED' | 'DELETION_PENDING'> {
  const result = await invoke<{ status?: unknown }>({
    action: 'DELETE_ACCOUNT', command: 'DELETE_ACCOUNT', proofId,
  });
  if (result.status !== 'DELETED' && result.status !== 'DELETION_PENDING') throw new CommandError('削除を開始できませんでした。');
  return result.status;
}

export async function registerPush(installationId: string, expoToken: string): Promise<void> {
  await invoke({ command: 'REGISTER_PUSH', installationId, expoToken });
}

export async function revokePush(installationId: string): Promise<void> {
  await invoke({ command: 'REVOKE_PUSH', installationId });
}

export async function requestInterpretation(captureId: string): Promise<void> {
  const result = await invoke<{ status?: unknown }>({ command: 'INTERPRET_CAPTURE', captureId });
  if (result.status !== 'OFFLOAD_READY' && result.status !== 'NEEDS_CONFIRMATION') {
    throw new CommandError('内容を解釈できませんでした。必要なら入力し直してください。');
  }
}

export async function correctLoop(loopId: string, expectedState: string, dueAt: string | null, nextEvaluationAt: string | null): Promise<void> {
  await invoke({ command: 'CORRECT_LOOP', loopId, expectedState, dueAt, nextEvaluationAt });
}

export function localEvaluationDate(value: string): string {
  const match = /^(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2})$/.exec(value);
  if (!match) throw new CommandError('次回確認日時は YYYY-MM-DD HH:mm で入力してください。');
  const [year, month, day, hour, minute] = match.slice(1).map(Number);
  const date = new Date(year, month - 1, day, hour, minute);
  if (date.getFullYear() !== year || date.getMonth() + 1 !== month || date.getDate() !== day ||
      date.getHours() !== hour || date.getMinutes() !== minute || date.getTime() <= Date.now()) {
    throw new CommandError('未来の有効な日時を入力してください。');
  }
  return date.toISOString();
}

export function formatLocalEvaluationDate(value: string | null): string {
  if (!value) return '';
  const date = new Date(value);
  const two = (number: number) => String(number).padStart(2, '0');
  return `${date.getFullYear()}-${two(date.getMonth() + 1)}-${two(date.getDate())} ${two(date.getHours())}:${two(date.getMinutes())}`;
}

export async function ackOffloadReceipt(loopId: string, basisRevision: number): Promise<'ACKED' | 'STALE'> {
  const result = await invoke<{ status?: unknown }>({ command: 'ACK_OFFLOAD_RECEIPT', loopId, basisRevision });
  if (result.status !== 'ACKED' && result.status !== 'STALE') throw new CommandError('確認を保存できませんでした。');
  return result.status;
}

export async function startRecentAuth(action: DestructiveAction): Promise<void> {
  const result = await invoke<{ status?: unknown }>({ action, command: 'START_RECENT_AUTH' });
  if (result.status === 'RETRY_LATER') {
    throw new CommandError('認証メールは1分間隔で送れます。少し待ってからもう一度お試しください。');
  }
  if (result.status !== 'OTP_SENT') throw new CommandError('再認証を開始できませんでした。');
}

export async function verifyRecentAuth(action: DestructiveAction, code: string): Promise<string> {
  if (!/^\d{6}$/.test(code)) {
    throw new CommandError('6桁の認証コードを入力してください。');
  }

  const result = await invoke<{ proofId?: unknown }>({ action, code, command: 'VERIFY_RECENT_AUTH' });
  if (typeof result.proofId !== 'string') {
    throw new CommandError('再認証を確認できませんでした。');
  }

  return result.proofId;
}

export async function withdrawConsent(proofId: string): Promise<void> {
  await invoke({
    action: 'WITHDRAW_CONSENT',
    command: 'WITHDRAW_CONSENT',
    idempotencyKey: idempotencyKey(),
    proofId,
  });
}
