const mockSignInWithOtp = jest.fn();
const mockVerifyOtp = jest.fn();

jest.mock('../src/auth/supabase', () => ({
  getSupabase: () => ({ auth: { signInWithOtp: mockSignInWithOtp, verifyOtp: mockVerifyOtp } }),
}));

import { AuthError, requestEmailOtp, verifyEmailOtp } from '../src/auth/emailOtp';

describe('Email OTP', () => {
  beforeEach(() => {
    mockSignInWithOtp.mockReset();
    mockVerifyOtp.mockReset();
  });

  it('does not create an account for an unregistered email address', async () => {
    mockSignInWithOtp.mockResolvedValue({ error: null });

    await requestEmailOtp('Participant@Example.com ');

    expect(mockSignInWithOtp).toHaveBeenCalledWith({
      email: 'participant@example.com',
      options: { shouldCreateUser: false },
    });
  });

  it('rejects a malformed OTP before sending it to the auth provider', async () => {
    await expect(verifyEmailOtp('participant@example.com', '123')).rejects.toBeInstanceOf(AuthError);

    expect(mockVerifyOtp).not.toHaveBeenCalled();
  });

  it('requires Supabase to issue a session after OTP verification', async () => {
    mockVerifyOtp.mockResolvedValue({ data: { session: null }, error: null });

    await expect(verifyEmailOtp('participant@example.com', '123456')).rejects.toBeInstanceOf(AuthError);
  });
});
