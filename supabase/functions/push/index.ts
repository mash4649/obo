import { createClient } from 'npm:@supabase/supabase-js@2';
import { reconcilePush, submitPush } from '../../../src/push/expo.ts';

const url = Deno.env.get('SUPABASE_URL') ?? '';
const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
const jobSecret = Deno.env.get('PUSH_JOB_SECRET') ?? '';
const expoAccessToken = Deno.env.get('EXPO_ACCESS_TOKEN') ?? '';

Deno.serve(async (request) => {
  if (request.method !== 'POST' || !jobSecret ||
      request.headers.get('x-push-job-secret') !== jobSecret) {
    return Response.json({ error: 'REQUEST_DENIED' }, { status: 403 });
  }
  if (Deno.env.get('P1_PUSH_ENABLED') !== 'true' || !url || !serviceKey || !expoAccessToken) {
    return Response.json({ status: 'DISABLED' });
  }

  const db = createClient(url, serviceKey);
  const { error: expiryError } = await db.rpc('command_expire_push_claims');
  if (expiryError) return Response.json({ error: 'JOB_FAILED' }, { status: 503 });
  let sent = 0;
  let reconciled = 0;

  for (let index = 0; index < 25; index++) {
    const { data, error } = await db.rpc('command_claim_push');
    if (error) return Response.json({ error: 'JOB_FAILED' }, { status: 503 });
    const claim = data?.[0];
    if (!claim) break;

    const { data: allowed, error: checkError } = await db.rpc('command_push_still_allowed', {
      p_delivery_id: claim.delivery_id,
      p_installation_id: claim.installation_id,
      p_expo_token: claim.expo_token,
    });
    if (checkError) return Response.json({ error: 'JOB_FAILED' }, { status: 503 });
    const result = allowed
      ? await submitPush(fetch, claim.expo_token, claim.delivery_id, expoAccessToken)
      : { ticketId: null, deviceNotRegistered: false };
    const { error: recordError } = await db.rpc('command_record_push_ticket', {
      p_delivery_id: claim.delivery_id, p_ticket_id: result.ticketId,
    });
    if (recordError) return Response.json({ error: 'JOB_FAILED' }, { status: 503 });
    if (result.deviceNotRegistered) {
      await db.rpc('command_invalidate_push_installation', { p_installation_id: claim.installation_id });
    }
    if (result.ticketId) sent++;
  }

  for (let index = 0; index < 25; index++) {
    const { data, error } = await db.rpc('command_claim_push_receipt');
    if (error) return Response.json({ error: 'JOB_FAILED' }, { status: 503 });
    const claim = data?.[0];
    if (!claim) break;

    const result = await reconcilePush(fetch, claim.ticket_id, expoAccessToken);
    const { error: finishError } = await db.rpc('command_finish_push_receipt', {
      p_delivery_id: claim.delivery_id,
      p_ok: result.ok,
      p_device_not_registered: result.deviceNotRegistered,
    });
    if (finishError) return Response.json({ error: 'JOB_FAILED' }, { status: 503 });
    reconciled++;
  }

  return Response.json({ sent, reconciled });
});
