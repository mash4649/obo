const mockInvoke = jest.fn();

jest.mock('../src/auth/supabase', () => ({
  getSupabase: () => ({ functions: { invoke: mockInvoke } }),
}));

import { CommandError, acceptConsent, getAuthState, verifyRecentAuth } from '../src/auth/command';

describe('command boundary', () => {
  beforeEach(() => {
    mockInvoke.mockReset();
  });

  it('does not request consent without an adult self-declaration', async () => {
    await expect(acceptConsent('Asia/Tokyo', false)).rejects.toBeInstanceOf(CommandError);

    expect(mockInvoke).not.toHaveBeenCalled();
  });

  it('uses the single server command boundary for account state', async () => {
    mockInvoke.mockResolvedValue({ data: { account: null, consent: null, participant: true }, error: null });

    await getAuthState();

    expect(mockInvoke).toHaveBeenCalledWith('command', { body: { command: 'AUTH_STATE' } });
  });

  it('rejects a malformed recent-auth OTP before it leaves the device', async () => {
    await expect(verifyRecentAuth('WITHDRAW_CONSENT', 'not-a-code')).rejects.toBeInstanceOf(CommandError);

    expect(mockInvoke).not.toHaveBeenCalled();
  });
});
