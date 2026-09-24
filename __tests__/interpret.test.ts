import { interpretCapture, redactForAi } from '../src/interpretation/interpret';
import { aiCostUsd, callOpenAi } from '../src/interpretation/openai';

const input = { scope: 'UNCATEGORIZED', text: 'buy paper', consentActive: true };
const usage = { inputTokens: 20, outputTokens: 15, model: 'gpt-5.6-luna' };
const interpretation = {
  title: 'Buy paper', expectedState: 'Paper is bought', dueAt: null,
  nextEvaluationAt: '2026-10-01T09:00:00Z', question: null,
};

describe('L05 interpretation boundary', () => {
  it('redacts supported synthetic identifiers deterministically', () => {
    const raw = 'contact test@example.invalid or +1 202 555 0101 for obo_abcdefghijklmnop';
    const first = redactForAi(raw);
    expect(first).toEqual(redactForAi(raw));
    expect(first?.redactedText).toContain('<EMAIL_1>');
    expect(first?.redactedText).toContain('<PHONE_1>');
    expect(first?.redactedText).toContain('<ID_1>');
    expect(first?.redactedText).not.toContain('example.invalid');
  });

  it.each([
    { ...input, consentActive: false },
    { ...input, text: 'password: synthetic' },
    { ...input, text: '山田さんに連絡' },
    { ...input, text: 'contact Joe' },
    { ...input, text: 'visit 123 Main Street' },
    { ...input, text: 'account ABC123def456ghi789' },
    { ...input, text: 'send to unknown@' },
  ])('makes no provider call for denied input', async (denied) => {
    const adapter = jest.fn();
    expect(await interpretCapture(denied, adapter)).toEqual({ status: 'FAILED_SAFE' });
    expect(adapter).not.toHaveBeenCalled();
  });

  it('removes identifier-bearing URLs and absolute paths from a synthetic request', () => {
    const approved = redactForAi('open https://example.invalid/u/obo_abcdefghijklmnop and /Users/test/file.txt');
    expect(approved?.redactedText).toContain('<URL_TOKEN_1>');
    expect(approved?.redactedText).toContain('<PATH_1>');
    expect(approved?.redactedText).not.toContain('example.invalid');
    expect(approved?.redactedText).not.toContain('/Users/test');
  });

  it('returns offload ready without granting completion authority', async () => {
    const adapter = jest.fn().mockResolvedValue({ interpretation, usage });
    const result = await interpretCapture(input, adapter);
    expect(result.status).toBe('OFFLOAD_READY');
    expect(result.interpretation).toEqual(interpretation);
    expect(adapter).toHaveBeenCalledWith({ status: 'ALLOW', redactedText: 'buy paper', policyVersion: 'd07-r/1' });
  });

  it('asks exactly one material question when interpretation needs confirmation', async () => {
    const adapter = jest.fn().mockResolvedValue({ interpretation: { ...interpretation, question: 'By when?' }, usage });
    expect((await interpretCapture(input, adapter)).status).toBe('NEEDS_CONFIRMATION');
  });

  it('holds interpretation until a next evaluation time exists', async () => {
    const adapter = jest.fn().mockResolvedValue({ interpretation: { ...interpretation, nextEvaluationAt: null }, usage });
    const result = await interpretCapture(input, adapter);
    expect(result.status).toBe('NEEDS_CONFIRMATION');
    expect(result.interpretation?.question).toBe('次にいつ確認しますか？');
  });

  it('retries the same redacted request and keeps storage disabled', async () => {
    const request = jest.fn()
      .mockResolvedValueOnce({ ok: false, status: 503 })
      .mockResolvedValueOnce({ ok: true, json: async () => ({
        choices: [{ message: { content: JSON.stringify(interpretation) } }],
        usage: { prompt_tokens: 20, completion_tokens: 15 },
      }) });
    const approved = redactForAi('contact test@example.invalid');
    expect(approved).not.toBeNull();
    const result = await callOpenAi(approved!, 'synthetic-key', request);
    const calls = request.mock.calls;
    expect(calls).toHaveLength(2);
    expect(calls[0][1].body).toBe(calls[1][1].body);
    expect(calls[0][1].body).toContain('"store":false');
    expect(calls[0][1].body).not.toContain('test@example.invalid');
    expect(result.usage.model).toBe('gpt-5.6-luna');
    expect(aiCostUsd(20, 15)).toBeCloseTo(0.000022);
  });
});
