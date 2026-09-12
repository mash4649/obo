# ADR-002: P1はiPhone向けTestFlight配布に限定する

## Status

Accepted

## Date

2026-09-12

## Context

P1は5人以上の実参加者によるCore Promiseの方向性検証であり、iOS/Androidの同時対応やOS Share Extensionは検証対象ではない。Expo SDK 57はiOS 16.4以降をサポートする。Appleは記名外部テスターへTestFlightでベータ配布でき、最初の外部ビルドにはTestFlight App Reviewが必要である。

## Decision

- P1のクライアントはiPhoneのみとし、iPad最適化、Android、Google Play配布をP0-P1の対象外とする。
- `ios.deploymentTarget` は `16.4` とする。
- 配布はApp Store ConnectのTestFlightを使い、internal groupでの確認後、記名メール招待のexternal groupへ配布する。公開招待リンクは使わない。
- 5人以上のP1参加者はexternal groupへ個別招待する。最初のexternal buildはTestFlight App Reviewの承認後にのみ配布する。
- release ownerはBeads ownerの`maga`とする。P1開始前に、iOS 16.4以上の実機iPhone 1台と、検証日の最新安定iOSを動かす実機iPhone 1台で、認証・同意・Push許可・Push拒否・background/terminated後の再開・app-switcher maskingを確認し、OS版と結果をrelease evidenceに記録する。
- simulatorはUI回帰に使えるが、Push、app-switcher masking、TestFlight配布の合格証跡には使わない。最小OSを動かす実機を確保できない場合は、TestFlight配布前にdeployment targetを上げる新しいADRを承認する。

## Alternatives Considered

### iOSとAndroidを同時に提供する

却下。P1のテキストCore Promiseには必要なく、配布、実機、Pushの検証面を増やす。

### TestFlight公開リンクを使う

却下。P1は記名参加者・同意・インシデント追跡を要するため、参加者を限定する。

### 開発用の登録端末だけに配布する

却下。P1にはApp Store Connect利用者ではない実参加者が含まれるため、TestFlight external groupの方が適合する。

## Consequences

- Android/Google Play/OS ShareはP1の開発・テスト・リリース条件から除外する。
- TestFlight App ReviewとApple Developer/App Store Connectの利用可能性がP1配布の外部前提になる。
- 実機2台の検証証跡がない場合、P1を開始しない。

## Sources

- Expo SDK 57 support table: https://docs.expo.dev/versions/latest/
- Expo iOS deployment target setting: https://docs.expo.dev/versions/v57.0.0/config/app/
- Apple TestFlight external testers: https://developer.apple.com/help/app-store-connect/test-a-beta-version/invite-external-testers
- Apple beta distribution overview: https://developer.apple.com/documentation/xcode/distributing-your-app-for-beta-testing-and-releases

## Verification

- app configuration sets `ios.deploymentTarget` to `16.4` and excludes Android builds from the P1 CI/release path.
- An internal TestFlight build passes the P1 smoke checklist before any external invitation.
- Named external invitations are sent only after TestFlight App Review approval.
- Release evidence records both required physical-device checks and Push allow/deny results.
