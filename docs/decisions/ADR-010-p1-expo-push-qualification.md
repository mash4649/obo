# ADR-010: P1 Expo Pushの資格条件と失敗時UX

## Status

Accepted（2026-09-14。L08のfixture・実機証跡はrelease gate）

## Context

P1の通知は、通知許可やPush providerの状態に依存して確認経路を失ってはならない。L08はIn-app確認を必須経路とし、Pushを補助経路として扱う必要がある。また、Push openやprovider受付をSOC・Activation・完了の証拠に昇格させてはならない。

## Decision

### 経路と資格条件

- すべての`ACT`に対してIn-app確認を必ず作成する。Pushを使わない参加者にも同じ確認経路を提供する。
- Pushは補助経路であり、同一`ACT`についてIn-appとPushの二重delivery行を作らない。既存のD08 semantic keyを共有する。
- Push providerはExpo Push Service、クライアント登録は`expo-notifications`とする。
- Pushは、明示的なアプリ内Push opt-in、iOSの`authorized` permission、ACTIVEなdevice installation token、active consent、送信時のLoop/revision再検証をすべて満たす場合だけ有効にする。
- iOSのprovisional/ephemeral permissionはP1資格として扱わない。資格を満たさない場合はIn-appのみとする。
- Expo credentialとprovider secretはserver-side secretとして保持し、クライアントへ渡さない。実Pushはcredential・device・permissionの証跡が揃うまで無効とする。

### Payloadと状態

- Push payloadにはRaw、本文、個人名、詳細なSensitive情報を含めない。汎用文言とopaqueな内部参照だけを許可する。
- Push open、ticket受付、receipt成功、時間経過はSOC、Activation、completionの証拠ではない。
- `DeviceNotRegistered` receiptは対象installationを`INVALID`にする。token失敗をSilent Successとして扱わない。

### Provider failureと再試行

- Push submission自体はretryしない。returned Expo ticketは15分後に1回だけreconcileする。
- ticketがない、receiptがmissing、receiptがerror、reconcileが失敗した場合は`RECEIPT_ERROR`とする。成功扱いにせず、In-app確認は維持する。
- provider障害はOpen Loop、decision、SOCを変更しない。ユーザーにはgenericな再確認導線を表示し、Rawやprovider詳細を返さない。
- 数値のPush成功率を新たな合格条件にはしない。Raw/PII漏洩、stale送信、PushだけによるSOC生成、In-app fallback不能、Critical trust incidentは各0件を必須条件とする。

### 送信直前の安全確認

delivery作成・送信直前に、D08/D09のLoop status、current revision、新しいdecision、active consent、Push opt-in、iOS permission、ACTIVE tokenを再検証する。stale、closed、satisfied、retired、資格不成立の対象は送信しない。

## Verification

- payload snapshotでRaw/PIIが存在しないことを確認する。
- stale-send fixtureでLoopまたはrevisionが変わった送信が抑止されることを確認する。
- provider fakeでticket受付、15分後の単回reconcile、missing/error receipt、`DeviceNotRegistered`の状態遷移を確認する。
- Push opt-in拒否、permission拒否、token未登録、provider障害のすべてでIn-app確認が残ることを確認する。
- 実機でauthorized permissionとACTIVE tokenを確認するまで、実参加者へのPushを有効化しない。

## Implementation gate

D10の意思決定契約は確定した。L08のpayload/stale/provider fake fixture、iOS実機のpermission・token・credential証跡が揃うまで、実Pushと参加者運用は開始しない。
