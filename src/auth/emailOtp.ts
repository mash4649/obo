import { getSupabase } from './supabase';

const EMAIL = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const OTP = /^\d{6}$/;

export class AuthError extends Error {}

export async function requestEmailOtp(input: string): Promise<string> {
  const email = input.trim().toLowerCase();

  if (!EMAIL.test(email)) {
    throw new AuthError('メールアドレスを確認してください。');
  }

  const supabase = getSupabase();
  if (!supabase) {
    throw new AuthError('認証設定がまだありません。');
  }

  const { error } = await supabase.auth.signInWithOtp({
    email,
    options: { shouldCreateUser: false },
  });

  if (error) {
    throw new AuthError('認証コードを送れませんでした。しばらくしてからもう一度お試しください。');
  }

  return email;
}

export async function verifyEmailOtp(email: string, code: string): Promise<void> {
  if (!OTP.test(code)) {
    throw new AuthError('6桁の認証コードを入力してください。');
  }

  const supabase = getSupabase();
  if (!supabase) {
    throw new AuthError('認証設定がまだありません。');
  }

  const { data, error } = await supabase.auth.verifyOtp({
    email,
    token: code,
    type: 'email',
  });

  if (error || !data.session) {
    throw new AuthError('認証コードを確認できませんでした。');
  }
}
