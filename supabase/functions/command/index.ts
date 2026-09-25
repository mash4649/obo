import { createClient } from 'npm:@supabase/supabase-js@2';
import { preflightCapture } from '../../../src/sensitivity/preflight.ts';
import { interpretCapture } from '../../../src/interpretation/interpret.ts';
import { aiCostUsd, callOpenAi } from '../../../src/interpretation/openai.ts';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL') ?? '';
const SUPABASE_ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY') ?? '';
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
const OTP = /^\d{6}$/;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const ACTIONS = new Set(['WITHDRAW_CONSENT', 'DELETE_RAW_CAPTURE', 'DELETE_ACCOUNT']);

type Command =
  | 'AUTH_STATE'
  | 'ACCEPT_CONSENT'
  | 'CAPTURE_TEXT'
  | 'INTERPRET_CAPTURE'
  | 'REGISTER_PUSH'
  | 'REVOKE_PUSH'
  | 'CORRECT_LOOP'
  | 'ACK_OFFLOAD_RECEIPT'
  | 'MARK_DONE'
  | 'MARK_NOT_YET'
  | 'END_CONTEXT'
  | 'REOPEN_CONTEXT'
  | 'RECORD_OWNERSHIP_MEASUREMENT'
  | 'DELETE_RAW_CAPTURE'
  | 'DELETE_ACCOUNT'
  | 'START_RECENT_AUTH'
  | 'VERIFY_RECENT_AUTH'
  | 'WITHDRAW_CONSENT';

type CommandRequest = {
  command?: Command;
  adultDeclared?: boolean;
  code?: string;
  idempotencyKey?: string;
  proofId?: string;
  timezone?: string;
  action?: string;
  scope?: string;
  text?: string;
  captureId?: string;
  loopId?: string;
  basisRevision?: number;
  expectedState?: string;
  dueAt?: string | null;
  nextEvaluationAt?: string | null;
  ownershipResult?: string;
  installationId?: string;
  expoToken?: string;
};

function response(body: unknown, status = 200) {
  return Response.json(body, { status });
}

function sessionId(authorization: string): string | null {
  const token = authorization.replace(/^Bearer\s+/i, '');
  const payload = token.split('.')[1];

  if (!payload) {
    return null;
  }

  try {
    const json = atob(payload.replace(/-/g, '+').replace(/_/g, '/'));
    const value = JSON.parse(json) as { session_id?: unknown };
    return typeof value.session_id === 'string' ? value.session_id : null;
  } catch {
    return null;
  }
}

async function request(req: Request): Promise<CommandRequest | null> {
  try {
    const body = await req.json();
    return body && typeof body === 'object' ? body as CommandRequest : null;
  } catch {
    return null;
  }
}

Deno.serve(async (req) => {
  const authorization = req.headers.get('Authorization') ?? '';
  const body = await request(req);

  if (!body?.command || !SUPABASE_URL || !SUPABASE_ANON_KEY || !SUPABASE_SERVICE_ROLE_KEY) {
    return response({ error: 'REQUEST_DENIED' }, 400);
  }

  const caller = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    global: { headers: { Authorization: authorization } },
  });
  const admin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
  const { data: { user }, error: userError } = await caller.auth.getUser();

  if (userError || !user) {
    return response({ error: 'REQUEST_DENIED' }, 401);
  }

  const participant = user.app_metadata.p1_participant === true;
  const currentSessionId = sessionId(authorization);

  if (body.command === 'AUTH_STATE') {
    const { data: account, error: accountError } = await caller
      .from('accounts')
      .select('id, status')
      .maybeSingle();

    if (accountError) {
      return response({ error: 'REQUEST_DENIED' }, 403);
    }

    const { data: consent, error: consentError } = account
      ? await caller
        .from('consents')
        .select('status, version')
        .eq('account_id', account.id)
        .eq('consent_type', 'P1_CORE')
        .order('occurred_at', { ascending: false })
        .limit(1)
        .maybeSingle()
      : { data: null, error: null };

    if (consentError) {
      return response({ error: 'REQUEST_DENIED' }, 403);
    }

    return response({
      account: account ? { status: account.status } : null,
      consent: consent ? { status: consent.status, version: consent.version } : null,
      consentDocumentUrl: Deno.env.get('CONSENT_DOCUMENT_URL') ?? null,
      participant,
      requiredConsentVersion: Deno.env.get('CONSENT_VERSION') ?? null,
    });
  }

  if (!participant) {
    return response({ error: 'REQUEST_DENIED' }, 403);
  }

  if (body.command === 'ACCEPT_CONSENT') {
    const version = Deno.env.get('CONSENT_VERSION');

    if (!body.adultDeclared || !version || !Deno.env.get('CONSENT_DOCUMENT_URL') || !body.timezone || !body.idempotencyKey || !UUID.test(body.idempotencyKey)) {
      return response({ error: 'REQUEST_DENIED' }, 400);
    }

    const { error } = await admin.rpc('command_accept_p1_consent', {
      p_auth_user_id: user.id,
      p_consent_version: version,
      p_idempotency_key: body.idempotencyKey,
      p_timezone: body.timezone,
    });

    return error ? response({ error: 'REQUEST_DENIED' }, 403) : response({ status: 'ACTIVE' });
  }

  if (body.command === 'CAPTURE_TEXT') {
    if (!body.idempotencyKey || !UUID.test(body.idempotencyKey)) {
      return response({ error: 'REQUEST_DENIED' }, 400);
    }

    const preflight = preflightCapture({ scope: body.scope, text: body.text });
    if (typeof body.scope !== 'string' || typeof body.text !== 'string') {
      return response({ error: 'REQUEST_DENIED' }, 400);
    }

    const { data: captureId, error } = await admin.rpc('command_capture_text', {
      p_auth_user_id: user.id,
      p_idempotency_key: body.idempotencyKey,
      p_raw_text: body.text,
      p_scope: body.scope,
      p_sensitivity_class: preflight.sensitivityClass,
    });

    return error ? response({ error: 'REQUEST_DENIED' }, 403) : response({
      captureId,
      status: preflight.sensitivityClass === 'PRIVATE' ? 'STORED' : 'FAILED_SAFE',
    });
  }

  if (body.command === 'REGISTER_PUSH' || body.command === 'REVOKE_PUSH') {
    if (!body.installationId || !UUID.test(body.installationId)) {
      return response({ error: 'REQUEST_DENIED' }, 400);
    }
    if (body.command === 'REGISTER_PUSH' && !body.expoToken) {
      return response({ error: 'REQUEST_DENIED' }, 400);
    }
    const { error } = await admin.rpc(
      body.command === 'REGISTER_PUSH' ? 'command_register_push' : 'command_revoke_push',
      body.command === 'REGISTER_PUSH'
        ? { p_auth_user_id: user.id, p_installation_id: body.installationId, p_expo_token: body.expoToken }
        : { p_auth_user_id: user.id, p_installation_id: body.installationId },
    );
    return error ? response({ error: 'REQUEST_DENIED' }, 403) : response({ status: 'OK' });
  }

  if (body.command === 'INTERPRET_CAPTURE') {
    if (!body.captureId || !UUID.test(body.captureId) ||
        Deno.env.get('P1_AI_ZDR_APPROVED') !== 'true' ||
        Deno.env.get('P1_AI_PARTICIPANT_TRAFFIC_APPROVED') !== 'true' ||
        !Deno.env.get('OPENAI_API_KEY')) {
      return response({ error: 'REQUEST_DENIED' }, 403);
    }
    const { data: source, error: sourceError } = await admin.rpc('command_interpretation_source', {
      p_auth_user_id: user.id, p_capture_id: body.captureId,
    });
    if (sourceError || !Array.isArray(source) || source.length !== 1) {
      return response({ error: 'REQUEST_DENIED' }, 403);
    }
    const result = await interpretCapture(
      { scope: source[0].scope, text: source[0].raw_text, consentActive: true },
      (approved) => callOpenAi(approved, Deno.env.get('OPENAI_API_KEY')!),
    );
    if (!result.interpretation || !result.usage || result.status === 'FAILED_SAFE') {
      return response({ status: 'FAILED_SAFE' });
    }
    const cost = aiCostUsd(result.usage.inputTokens, result.usage.outputTokens);
    if (cost > 0.002) return response({ status: 'FAILED_SAFE' });
    const { data: loopId, error } = await admin.rpc('command_record_interpretation', {
      p_auth_user_id: user.id, p_capture_id: body.captureId,
      p_title: result.interpretation.title,
      p_expected_state: result.interpretation.expectedState,
      p_due_at: result.interpretation.dueAt,
      p_next_evaluation_at: result.interpretation.nextEvaluationAt,
      p_question: result.interpretation.question,
      p_model: result.usage.model,
      p_input_tokens: result.usage.inputTokens,
      p_output_tokens: result.usage.outputTokens,
      p_cost_usd: cost,
    });
    return error ? response({ status: 'FAILED_SAFE' }) : response({ loopId, status: result.status });
  }

  if (body.command === 'CORRECT_LOOP') {
    if (!body.loopId || !UUID.test(body.loopId) || !body.expectedState ||
        typeof body.expectedState !== 'string' || body.expectedState.length > 300) {
      return response({ error: 'REQUEST_DENIED' }, 400);
    }
    const { data: basisRevision, error } = await admin.rpc('command_correct_loop', {
      p_auth_user_id: user.id, p_loop_id: body.loopId,
      p_expected_state: body.expectedState,
      p_due_at: body.dueAt ?? null,
      p_next_evaluation_at: body.nextEvaluationAt ?? null,
    });
    return error ? response({ error: 'REQUEST_DENIED' }, 403) : response({ basisRevision });
  }

  if (body.command === 'ACK_OFFLOAD_RECEIPT') {
    if (Deno.env.get('P1_TRACKING_ENABLED') !== 'true') {
      return response({ error: 'REQUEST_DENIED' }, 403);
    }
    if (!body.loopId || !UUID.test(body.loopId) || !Number.isInteger(body.basisRevision) || body.basisRevision! < 1) {
      return response({ error: 'REQUEST_DENIED' }, 400);
    }
    const { data: status, error } = await admin.rpc('command_ack_offload_receipt', {
      p_auth_user_id: user.id, p_loop_id: body.loopId, p_basis_revision: body.basisRevision,
    });
    return error ? response({ error: 'REQUEST_DENIED' }, 403) : response({ status });
  }

  if (body.command === 'MARK_DONE' || body.command === 'MARK_NOT_YET' ||
      body.command === 'END_CONTEXT' || body.command === 'REOPEN_CONTEXT') {
    if (!body.loopId || !UUID.test(body.loopId)) return response({ error: 'REQUEST_DENIED' }, 400);
    const { data: status, error } = await admin.rpc('command_loop_action', {
      p_auth_user_id: user.id, p_loop_id: body.loopId, p_action: body.command,
    });
    return error ? response({ error: 'REQUEST_DENIED' }, 403) : response({ status });
  }

  if (body.command === 'RECORD_OWNERSHIP_MEASUREMENT') {
    if (!body.loopId || !UUID.test(body.loopId) ||
        !['OWNED', 'PARALLEL', 'UNKNOWN'].includes(body.ownershipResult ?? '')) {
      return response({ error: 'REQUEST_DENIED' }, 400);
    }
    const { data: status, error } = await admin.rpc('command_record_ownership', {
      p_auth_user_id: user.id, p_loop_id: body.loopId, p_result: body.ownershipResult,
    });
    return error ? response({ error: 'REQUEST_DENIED' }, 403) : response({ status });
  }

  if (!currentSessionId || !body.action || !ACTIONS.has(body.action)) {
    return response({ error: 'REQUEST_DENIED' }, 400);
  }

  if (body.command === 'START_RECENT_AUTH') {
    const { error: challengeError } = await admin.rpc('command_start_recent_auth', {
      p_action_kind: body.action,
      p_auth_user_id: user.id,
      p_session_id: currentSessionId,
    });

    if (challengeError?.code === '42901') return response({ status: 'RETRY_LATER' });
    if (challengeError || !user.email) {
      return response({ error: 'REQUEST_DENIED' }, 403);
    }

    const { error: otpError } = await admin.auth.signInWithOtp({
      email: user.email,
      options: { shouldCreateUser: false },
    });

    if (otpError?.code === 'over_email_send_rate_limit') return response({ status: 'RETRY_LATER' });
    return otpError ? response({ error: 'REQUEST_DENIED' }, 503) : response({ status: 'OTP_SENT' });
  }

  if (body.command === 'VERIFY_RECENT_AUTH') {
    if (!body.code || !OTP.test(body.code) || !user.email) {
      return response({ error: 'REQUEST_DENIED' }, 400);
    }

    const { error: otpError } = await caller.auth.verifyOtp({
      email: user.email,
      token: body.code,
      type: 'email',
    });

    if (otpError) {
      return response({ error: 'REQUEST_DENIED' }, 403);
    }

    const { data: proofId, error: proofError } = await admin.rpc('command_verify_recent_auth', {
      p_action_kind: body.action,
      p_auth_user_id: user.id,
      p_session_id: currentSessionId,
    });

    return proofError ? response({ error: 'REQUEST_DENIED' }, 403) : response({ proofId });
  }

  if (body.command === 'DELETE_RAW_CAPTURE') {
    if (body.action !== 'DELETE_RAW_CAPTURE' || !body.captureId || !UUID.test(body.captureId) ||
        !body.proofId || !UUID.test(body.proofId)) {
      return response({ error: 'REQUEST_DENIED' }, 400);
    }
    const { error: beginError } = await admin.rpc('command_begin_raw_deletion', {
      p_auth_user_id: user.id, p_capture_id: body.captureId,
      p_session_id: currentSessionId, p_proof_id: body.proofId,
    });
    if (beginError) return response({ error: 'REQUEST_DENIED' }, 403);
    const { error: finishError } = await admin.rpc('command_finish_raw_deletion', {
      p_capture_id: body.captureId,
    });
    return response({ status: finishError ? 'DELETION_PENDING' : 'DELETED' });
  }

  if (body.command === 'DELETE_ACCOUNT') {
    if (body.action !== 'DELETE_ACCOUNT' || !body.proofId || !UUID.test(body.proofId)) {
      return response({ error: 'REQUEST_DENIED' }, 400);
    }
    const { error: beginError } = await admin.rpc('command_begin_account_deletion', {
      p_auth_user_id: user.id, p_session_id: currentSessionId, p_proof_id: body.proofId,
    });
    if (beginError) return response({ error: 'REQUEST_DENIED' }, 403);
    const { error: authDeleteError } = await admin.auth.admin.deleteUser(user.id);
    if (authDeleteError) return response({ status: 'DELETION_PENDING' });
    const { error: finishError } = await admin.rpc('command_finish_account_deletion', {
      p_auth_user_id: user.id,
    });
    return response({ status: finishError ? 'DELETION_PENDING' : 'DELETED' });
  }

  if (body.command === 'WITHDRAW_CONSENT') {
    if (!body.proofId || !body.idempotencyKey || !UUID.test(body.proofId) || !UUID.test(body.idempotencyKey)) {
      return response({ error: 'REQUEST_DENIED' }, 400);
    }

    const { error } = await admin.rpc('command_withdraw_p1_consent', {
      p_auth_user_id: user.id,
      p_idempotency_key: body.idempotencyKey,
      p_proof_id: body.proofId,
      p_session_id: currentSessionId,
    });

    if (error) {
      return response({ error: 'REQUEST_DENIED' }, 403);
    }

    await caller.auth.signOut({ scope: 'global' });
    return response({ status: 'DELETION_PENDING' });
  }

  return response({ error: 'REQUEST_DENIED' }, 400);
});
