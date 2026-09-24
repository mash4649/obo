import { pushPayload, reconcilePush, submitPush } from '../src/push/expo';

const token = 'ExpoPushToken[synthetic_token_1234567890]';
const ref = '91111111-1111-4111-8111-222222222222';

function fakeResponse(body: unknown, ok = true): Response {
  return { ok, json: async () => body } as Response;
}

test('Push payload contains only generic text and opaque reference', async () => {
  const payload = pushPayload(token, ref);
  expect(JSON.stringify(payload)).toBe(JSON.stringify({
    to: token,
    title: 'OBO',
    body: '確認待ちの件があります。アプリで確認してください。',
    data: { ref },
  }));
  const fetcher = jest.fn(async () => fakeResponse({ data: { status: 'ok', id: 'ticket-1' } })) as unknown as typeof fetch;
  expect(await submitPush(fetcher, token, ref, 'synthetic-secret')).toEqual({
    ticketId: 'ticket-1', deviceNotRegistered: false,
  });
  expect(fetcher).toHaveBeenCalledTimes(1);
  expect(JSON.parse((fetcher as jest.Mock).mock.calls[0][1].body)).toEqual(payload);
});

test('missing ticket and receipt fail closed; DeviceNotRegistered is reported', async () => {
  const noTicket = jest.fn(async () => fakeResponse({ data: { status: 'error' } })) as unknown as typeof fetch;
  expect(await submitPush(noTicket, token, ref, 'synthetic-secret')).toEqual({
    ticketId: null, deviceNotRegistered: false,
  });
  const missing = jest.fn(async () => fakeResponse({ data: {} })) as unknown as typeof fetch;
  expect(await reconcilePush(missing, 'ticket-1', 'synthetic-secret')).toEqual({
    ok: false, deviceNotRegistered: false,
  });
  const invalid = jest.fn(async () => fakeResponse({
    data: { 'ticket-1': { status: 'error', details: { error: 'DeviceNotRegistered' } } },
  })) as unknown as typeof fetch;
  expect(await reconcilePush(invalid, 'ticket-1', 'synthetic-secret')).toEqual({
    ok: false, deviceNotRegistered: true,
  });
});
