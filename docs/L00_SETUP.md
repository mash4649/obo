# L00 setup and verification

Use Node `22.22.3` and npm `10.9.8` from `.nvmrc` and `package.json`.

```text
npm ci
npm run doctor
npm run lint
npm run typecheck
npm test
npm run export:ios
npm audit --omit=dev --audit-level=high
```

`supabase/config.toml` is the committed local-project boundary. It contains no
remote project reference or credentials. Local Supabase services require the
Supabase CLI and a Docker-compatible runtime; neither is started by L00.
