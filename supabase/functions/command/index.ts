import { createClient } from 'npm:@supabase/supabase-js@2';
import { preflightCapture } from '../../../src/sensitivity/preflight.ts';

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

  if (!currentSessionId || !body.action || !ACTIONS.has(body.action)) {
    return response({ error: 'REQUEST_DENIED' }, 400);
  }

  if (body.command === 'START_RECENT_AUTH') {
    const { error: challengeError } = await admin.rpc('command_start_recent_auth', {
      p_action_kind: body.action,
      p_auth_user_id: user.id,
      p_session_id: currentSessionId,
    });

    if (challengeError || !user.email) {
      return response({ error: 'REQUEST_DENIED' }, 403);
    }

    const { error: otpError } = await admin.auth.signInWithOtp({
      email: user.email,
      options: { shouldCreateUser: false },
    });

    return otpError ? response({ error: 'REQUEST_DENIED' }, 503) : response({ status: 'OTP_SENT' });
  }

  if (body.command === 'VERIFY_RECENT_AUTH') {
    if (!body.code || !OTP.test(body.code) || !user.email) {
      return response({ error: 'REQUEST_DENIED' }, 400);
    }

    const { error: otpError } = await admin.auth.verifyOtp({
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
