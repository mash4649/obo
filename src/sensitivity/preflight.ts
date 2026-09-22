export const captureScopes = ['SCHEDULE', 'HOUSEHOLD', 'SHOPPING', 'GENERAL_ADMIN'] as const;

export type CaptureScope = typeof captureScopes[number];
export type SensitivityClass = 'PRIVATE' | 'SENSITIVE' | 'SECRET' | 'UNCLASSIFIED';
export type PreflightResult = {
  sensitivityClass: SensitivityClass;
  externalAiCandidate: boolean;
  userState: 'READY_FOR_SERVER_REVIEW' | 'HOLD_REENTER' | 'REJECT_REENTER';
};

const secretSignal = /\b(?:password|otp|one[- ]time(?:\s+passcode)?|passcode|recovery\s*code|api[_ -]?key|auth(?:entication)?\s*token)\b|パスワード|ワンタイム(?:パス)?コード|リカバリーコード/i;
const sensitiveSignal = /\b(?:medical|diagnosis|medical history|passport|driver'?s license|national id|bank account|credit card|cvv)\b|診断|病歴|マイナンバー|運転免許|パスポート|口座番号|クレジットカード|セキュリティコード/i;

export function preflightCapture(input: { scope?: unknown; text?: unknown }): PreflightResult {
  if (typeof input.scope !== 'string' || !captureScopes.includes(input.scope as CaptureScope) || typeof input.text !== 'string') {
    return { sensitivityClass: 'UNCLASSIFIED', externalAiCandidate: false, userState: 'HOLD_REENTER' };
  }

  const text = input.text.trim();

  if (!text || [...text].length > 2000) {
    return { sensitivityClass: 'UNCLASSIFIED', externalAiCandidate: false, userState: 'HOLD_REENTER' };
  }

  if (secretSignal.test(text)) {
    return { sensitivityClass: 'SECRET', externalAiCandidate: false, userState: 'REJECT_REENTER' };
  }

  if (sensitiveSignal.test(text)) {
    return { sensitivityClass: 'SENSITIVE', externalAiCandidate: false, userState: 'HOLD_REENTER' };
  }

  return { sensitivityClass: 'PRIVATE', externalAiCandidate: true, userState: 'READY_FOR_SERVER_REVIEW' };
}
