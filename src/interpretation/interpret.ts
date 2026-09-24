import { preflightCapture } from '../sensitivity/preflight.ts';

export type ApprovedAdapterInput = {
  status: 'ALLOW';
  redactedText: string;
  policyVersion: 'd07-r/1';
};

export type Interpretation = {
  title: string;
  expectedState: string;
  dueAt: string | null;
  nextEvaluationAt: string | null;
  question: string | null;
};

export type AiUsage = { inputTokens: number; outputTokens: number; model: string };
export type AiResult = { interpretation: unknown; usage: AiUsage };

const email = /[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}/gi;
const phone = /(?<![\w])(?:\+|0)[\d\s()-]{9,22}\d(?![\w])/g;
const id = /\b(?:[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}|obo_[a-z0-9]{16,64})\b/gi;
const url = /https?:\/\/[^\s<>]+/gi;
const path = /(?:[A-Za-z]:\\|\\\\|\/)[^\s<>]+/g;

// This narrow grammar is for synthetic fixtures. Participant traffic remains gated externally.
export function redactForAi(text: string): ApprovedAdapterInput | null {
  if (!text.trim() || [...text].length > 2000) return null;

  let result = text.trim();
  const counters = { EMAIL: 0, PHONE: 0, ID: 0, URL_TOKEN: 0, PATH: 0 };
  const replacement = (kind: keyof typeof counters) => `<${kind}_${++counters[kind]}>`;

  result = result.replace(url, (value) => {
    try {
      const parsed = new URL(value);
      if (!['http:', 'https:'].includes(parsed.protocol)) return '\u0000';
      return replacement('URL_TOKEN');
    } catch { return '\u0000'; }
  });
  result = result.replace(path, () => replacement('PATH'));
  result = result.replace(email, () => replacement('EMAIL'));
  result = result.replace(phone, (value) => {
    const digits = value.replace(/\D/g, '');
    return digits.length >= 10 && digits.length <= 15 ? replacement('PHONE') : '\u0000';
  });
  result = result.replace(id, () => replacement('ID'));

  // Unknown identifier syntax, names and addresses cannot be proved safe by this parser.
  if (/\b[A-Z][a-z]+\b/.test(result) ||
      /\b\d{1,6}\s+[A-Za-z]+\s+(?:Street|St|Road|Rd|Avenue|Ave)\b/i.test(result)) return null;
  if (/\u0000|@|https?:|\\|\bobo_|\b[A-Za-z0-9_-]{16,}\b|\b\w+\.[A-Za-z0-9]{2,5}\b|[\u3040-\u30ff\u3400-\u9fff]/i.test(result)) return null;
  if (!/^[A-Za-z0-9\s.,!?;:'"()<>_/-]+$/.test(result)) return null;
  return { status: 'ALLOW', redactedText: result, policyVersion: 'd07-r/1' };
}

export function validateInterpretation(value: unknown): Interpretation | null {
  if (!value || typeof value !== 'object') return null;
  const item = value as Record<string, unknown>;
  if (typeof item.title !== 'string' || !item.title.trim() || item.title.length > 100 ||
    typeof item.expectedState !== 'string' || item.expectedState.length > 300 ||
    !(item.question === null || (typeof item.question === 'string' && item.question.length <= 200 && !!item.question.trim())) ||
    !(item.dueAt === null || (typeof item.dueAt === 'string' && !Number.isNaN(Date.parse(item.dueAt)))) ||
    !(item.nextEvaluationAt === null || (typeof item.nextEvaluationAt === 'string' && !Number.isNaN(Date.parse(item.nextEvaluationAt))))) return null;
  if (!item.expectedState.trim() && !item.question) return null;
  return item as Interpretation;
}

export async function interpretCapture(
  input: { scope: unknown; text: unknown; consentActive: boolean },
  adapter: (approved: ApprovedAdapterInput) => Promise<AiResult>,
): Promise<{ status: 'OFFLOAD_READY' | 'NEEDS_CONFIRMATION' | 'FAILED_SAFE'; interpretation?: Interpretation; usage?: AiUsage }> {
  if (!input.consentActive || !preflightCapture(input).externalAiCandidate) return { status: 'FAILED_SAFE' };
  const approved = redactForAi(input.text as string);
  if (!approved) return { status: 'FAILED_SAFE' };
  try {
    const { interpretation: raw, usage } = await adapter(approved);
    const interpretation = validateInterpretation(raw);
    if (!interpretation || !Number.isInteger(usage.inputTokens) || !Number.isInteger(usage.outputTokens) ||
      usage.inputTokens < 0 || usage.outputTokens < 0 || usage.inputTokens > 2500 || usage.outputTokens > 256) {
      return { status: 'FAILED_SAFE' };
    }
    if (!interpretation.expectedState.trim() && !interpretation.nextEvaluationAt) return { status: 'FAILED_SAFE' };
    if (!interpretation.expectedState.trim()) interpretation.question = '何が済めばこの件は終わりですか？';
    else if (!interpretation.nextEvaluationAt) interpretation.question = '次にいつ確認しますか？';
    else if (interpretation.question) return { status: 'FAILED_SAFE' };
    return { status: interpretation.question ? 'NEEDS_CONFIRMATION' : 'OFFLOAD_READY', interpretation, usage };
  } catch {
    return { status: 'FAILED_SAFE' };
  }
}
