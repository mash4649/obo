const mockInvoke = jest.fn();

jest.mock('../src/auth/supabase', () => ({
  getSupabase: () => ({ functions: { invoke: mockInvoke } }),
}));

import { captureText, CommandError, acceptConsent, getAuthState, localEvaluationDate, verifyRecentAuth } from '../src/auth/command';

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

  it('keeps an empty capture on device', async () => {
    await expect(captureText('  ')).rejects.toBeInstanceOf(CommandError);

    expect(mockInvoke).not.toHaveBeenCalled();
  });

  it('sends a capture only through the server command boundary', async () => {
    mockInvoke.mockResolvedValue({ data: { captureId: 'capture-id', status: 'STORED' }, error: null });

    await expect(captureText('buy paper')).resolves.toEqual({ captureId: 'capture-id', status: 'STORED' });

    expect(mockInvoke).toHaveBeenCalledWith('command', {
      body: expect.objectContaining({ command: 'CAPTURE_TEXT', scope: 'UNCATEGORIZED', text: 'buy paper' }),
    });
  });

  it('rejects an invalid local evaluation date before a correction is sent', () => {
    expect(() => localEvaluationDate('2026-02-30 09:00')).toThrow(CommandError);
    expect(mockInvoke).not.toHaveBeenCalled();
  });
});
