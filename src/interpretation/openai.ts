import type { AiResult, ApprovedAdapterInput } from './interpret.ts';

const MODEL = 'gpt-5.6-luna';
const ENDPOINT = 'https://api.openai.com/v1/chat/completions';
const SYSTEM = 'Extract an everyday task. Return JSON only. Do not mark completion. Ask one question only when expectedState or nextEvaluationAt is missing, never both. Use null when a date or question is unknown.';

export async function callOpenAi(
  approved: ApprovedAdapterInput,
  apiKey: string,
  request: typeof fetch = fetch,
): Promise<AiResult> {
  if (!apiKey || approved.status !== 'ALLOW' || approved.policyVersion !== 'd07-r/1') throw new Error('AI_DENIED');
  const prompt = `${SYSTEM}\n${approved.redactedText}`;
  if (new TextEncoder().encode(prompt).length > 2500) throw new Error('AI_INPUT_LIMIT');
  const body = JSON.stringify({
    model: MODEL, store: false, max_completion_tokens: 256,
    messages: [{ role: 'system', content: SYSTEM }, { role: 'user', content: approved.redactedText }],
    response_format: {
      type: 'json_schema',
      json_schema: {
        name: 'obo_interpretation', strict: true,
        schema: {
          type: 'object', additionalProperties: false,
          required: ['title', 'expectedState', 'dueAt', 'nextEvaluationAt', 'question'],
          properties: {
            title: { type: 'string' }, expectedState: { type: 'string' },
            dueAt: { type: ['string', 'null'] }, nextEvaluationAt: { type: ['string', 'null'] },
            question: { type: ['string', 'null'] },
          },
        },
      },
    },
  });

  const deadline = Date.now() + 15000;
  for (let attempt = 0; attempt < 2; attempt++) {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), Math.min(8000, Math.max(1, deadline - Date.now())));
    try {
      const response = await request(ENDPOINT, {
        method: 'POST', headers: { Authorization: `Bearer ${apiKey}`, 'Content-Type': 'application/json' },
        body, signal: controller.signal,
      });
      if (!response.ok) {
        if (attempt === 0 && (response.status === 408 || response.status === 429 || response.status >= 500)) {
          await new Promise((resolve) => setTimeout(resolve, 250 + Math.floor(Math.random() * 751)));
          continue;
        }
        throw new Error('AI_PROVIDER_ERROR');
      }
      const data = await response.json() as {
        model?: unknown; usage?: { prompt_tokens?: unknown; completion_tokens?: unknown };
        choices?: { message?: { content?: unknown } }[];
      };
      if (typeof data.choices?.[0]?.message?.content !== 'string' ||
          !Number.isInteger(data.usage?.prompt_tokens) || !Number.isInteger(data.usage?.completion_tokens)) {
        throw new Error('AI_INVALID_RESPONSE');
      }
      return {
        interpretation: JSON.parse(data.choices[0].message.content),
        usage: {
          model: MODEL,
          inputTokens: data.usage!.prompt_tokens as number,
          outputTokens: data.usage!.completion_tokens as number,
        },
      };
    } catch (error) {
      if (attempt === 0 && error instanceof Error && error.name === 'AbortError' && Date.now() < deadline) {
        await new Promise((resolve) => setTimeout(resolve, 250 + Math.floor(Math.random() * 751)));
        continue;
      }
      throw new Error('AI_PROVIDER_ERROR');
    } finally {
      clearTimeout(timeout);
    }
  }
  throw new Error('AI_PROVIDER_ERROR');
}

export function aiCostUsd(inputTokens: number, outputTokens: number): number {
  return (inputTokens * 0.2 + outputTokens * 1.2) / 1_000_000;
}
