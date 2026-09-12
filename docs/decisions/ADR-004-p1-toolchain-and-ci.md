# ADR-004: P1のツールチェーンとCIを固定する

## Status

Accepted

## Date

2026-09-12

## Context

L00はExpo/RN/Supabaseの正確な依存、再現可能なinstall、CIコマンドを必要とする。既存のリポジトリにはpackage manifestがなく、パックはExpo SDK 57系、React Native 0.86系、`expo@57.0.17`を下限としている。

## Decision

- App toolchainは`expo@57.0.17`、React Native `0.86.3`、React `19.2.3`を採用する。Expo SDK 57の互換パッケージは`npx expo install`で解決し、その結果を固定する。
- Backend clientは`@supabase/supabase-js@2.116.0`を採用する。決定時点でnpm registryが返した安定版を明示的に固定し、更新は別ADRで行う。
- CI runtimeはNode `22.22.3`、npm `10.9.8`とする。Expo公式のSDK 57要件であるNode `22.13.x`以上を満たす、決定時点の実行環境を固定する。
- package managerはnpmだけとし、`package-lock.json`を唯一のlockfileにする。pnpm/yarn lockfileは作成しない。
- GitHub Actionsは`feature`と`main`へのpush、およびpull requestで実行する。標準検証は`npm ci`、`npx expo-doctor`、`npm run lint`、`npm run typecheck`、`npm test`、`npx expo export --platform ios`、`npm audit --omit=dev --audit-level=high`、secret scanとする。
- TestFlight/EASの配布はCIの合格だけで自動実行せず、D02のrelease evidence手順で行う。

## Alternatives Considered

### Expo SDKの最新版へ追従する

却下。P1の実機証跡を再現できず、SDKの自動更新が測定結果に混入する。

### pnpmを新たに導入する

却下。現時点のプロジェクトにpnpm境界がなく、npmの標準lockfileで十分なため。

### CIからTestFlightを自動配布する

却下。App Review、記名招待、実機確認を必要とするD02のrelease boundaryを越える。

## Consequences

- L00でmanifest、`package-lock.json`、Node/npm version file、Actions workflowを同じ小単位で作成する。
- Expo/RN/Supabase clientの更新は、lockfileだけを黙って更新せず、互換性・実機・CIを再検証してADRを更新する。
- `npm audit`の結果は到達可能性を確認して扱い、強制的な自動修正は行わない。

## Sources

- Expo SDK 57 compatibility table: https://docs.expo.dev/versions/v57.0.0/
- Expo SDK 57 release and `expo@57.0.17` regression fix: https://expo.dev/changelog/sdk-57
- Supabase JavaScript client package: https://www.npmjs.com/package/@supabase/supabase-js/v/2.116.0
- GitHub Actions Node.js workflow guidance: https://docs.github.com/en/actions/tutorials/build-and-test-code/nodejs

## Verification

- Clean checkoutで`npm ci`がlockfileだけから成功する。
- Expo doctor、lint、typecheck、test、iOS export、audit、secret scanが同じCIで再実行できる。
- `npm ls expo react react-native @supabase/supabase-js`の結果がこのADRと一致する。
