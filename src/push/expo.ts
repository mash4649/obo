export type PushResult = { ticketId: string | null; deviceNotRegistered: boolean };
export type ReceiptResult = { ok: boolean; deviceNotRegistered: boolean };

export function pushPayload(token: string, ref: string) {
  return {
    to: token,
    title: 'OBO',
    body: '確認待ちの件があります。アプリで確認してください。',
    data: { ref },
  };
}

export async function submitPush(
  fetcher: typeof fetch, token: string, ref: string, accessToken: string,
): Promise<PushResult> {
  try {
    const response = await fetcher('https://exp.host/--/api/v2/push/send', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${accessToken}` },
      body: JSON.stringify(pushPayload(token, ref)),
    });
    if (!response.ok) return { ticketId: null, deviceNotRegistered: false };
    const result = await response.json();
    const ticket = result?.data;
    return {
      ticketId: ticket?.status === 'ok' && typeof ticket.id === 'string' ? ticket.id : null,
      deviceNotRegistered: ticket?.details?.error === 'DeviceNotRegistered',
    };
  } catch {
    return { ticketId: null, deviceNotRegistered: false };
  }
}

export async function reconcilePush(
  fetcher: typeof fetch, ticketId: string, accessToken: string,
): Promise<ReceiptResult> {
  try {
    const response = await fetcher('https://exp.host/--/api/v2/push/getReceipts', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${accessToken}` },
      body: JSON.stringify({ ids: [ticketId] }),
    });
    if (!response.ok) return { ok: false, deviceNotRegistered: false };
    const result = await response.json();
    const receipt = result?.data?.[ticketId];
    return {
      ok: receipt?.status === 'ok',
      deviceNotRegistered: receipt?.details?.error === 'DeviceNotRegistered',
    };
  } catch {
    return { ok: false, deviceNotRegistered: false };
  }
}
