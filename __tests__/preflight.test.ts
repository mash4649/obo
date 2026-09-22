import { preflightCapture } from '../src/sensitivity/preflight';

describe('preflightCapture', () => {
  it.each([
    ['SECRET', { scope: 'SCHEDULE', text: 'password: example' }],
    ['SENSITIVE', { scope: 'HOUSEHOLD', text: '診断内容を確認する' }],
    ['UNCLASSIFIED', { scope: 'UNKNOWN', text: 'buy paper' }],
    ['UNCLASSIFIED', { scope: 'SHOPPING', text: 'あ'.repeat(2001) }],
  ])('keeps %s input away from an external adapter', (expected, input) => {
    const adapter = jest.fn();
    const result = preflightCapture(input);

    if (result.externalAiCandidate) {
      adapter();
    }

    expect(result.sensitivityClass).toBe(expected);
    expect(adapter).not.toHaveBeenCalled();
  });

  it('accepts only a bounded low-risk input as a server-review candidate', () => {
    expect(preflightCapture({ scope: 'GENERAL_ADMIN', text: 'renew the library card' })).toEqual({
      sensitivityClass: 'PRIVATE',
      externalAiCandidate: true,
      userState: 'READY_FOR_SERVER_REVIEW',
    });
  });

  it('counts Unicode code points rather than UTF-16 code units', () => {
    expect(preflightCapture({ scope: 'SHOPPING', text: '😀'.repeat(2000) }).sensitivityClass).toBe('PRIVATE');
  });
});
