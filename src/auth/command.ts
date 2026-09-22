import { getSupabase } from './supabase';

export type AuthState = {
  account: { status: 'ACTIVE' | 'DELETION_PENDING' | 'DELETED' } | null;
  consent: { status: 'ACCEPTED' | 'WITHDRAWN'; version: string } | null;
  consentDocumentUrl: string | null;
  participant: boolean;
  requiredConsentVersion: string | null;
};

type DestructiveAction = 'WITHDRAW_CONSENT' | 'DELETE_RAW_CAPTURE' | 'DELETE_ACCOUNT';

export class CommandError extends Error {}

function idempotencyKey(): string {
  const key = globalThis.crypto?.randomUUID?.();

  if (!key) {
    throw new CommandError('安全な操作を開始できません。');
  }

  return key;
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

export async function startRecentAuth(action: DestructiveAction): Promise<void> {
  await invoke({ action, command: 'START_RECENT_AUTH' });
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
