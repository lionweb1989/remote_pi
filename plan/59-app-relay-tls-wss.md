# 59 — Transport TLS: clientes confiando no cert auto-assinado do relay (wss)

## Contexto

O relay foi usado em **http puro** (`ws://118.145.119.50:8788`) porque o app
recusava o cert auto-assinado do IP e a TLS por domínio
(`lionweb.duckdns.org:8443`) é DPI-blocked na rede do usuário. Agora:

- **Servidor já está pronto** (feito ontem): Caddy `:8443` com cert
  auto-assinado `CN=118.145.119.50` (`/etc/caddy/ip-cert.pem`, válido até
  2028-11-12), `handle_path /remote-pi*` → relay 8788.
- **Verificado hoje**: `wss://118.145.119.50:8443/remote-pi` completa TLSv1.3
  + WS Upgrade **101 Switching Protocols** — a TLS por **IP não é DPI-blocked**
  (o bloqueio era só do SNI de domínio).
- **Falta**: os clientes (app Flutter + pi-extension Node) **aceitarem o cert
  auto-assinado** — com **pin da impressão digital** (não bypass cego).

Fingerprint SHA-256 do cert (`openssl x509 -fingerprint -sha256`):
`0B:72:0D:06:0F:FB:2C:E0:3B:41:99:F0:96:E1:E7:95:7D:98:A0:70:14:BD:73:FC:58:4D:03:6B:E7:39:40:49`
(lowercase hex: `0b720d060ffb2ce03b4199f096e1e7957d98a07014bd73fc584d036be7394049`)

## Estrutura esperada

- **app/**: helper de pin (`relay_tls.dart`) com o fingerprint + host pinado;
  `WsTransport` (WS) e `MeshClient` (Dio REST) usam um `HttpClient` cujo
  `badCertificateCallback` só libera quando host == `118.145.119.50` **e** o
  SHA-256 do cert bate com o pin; qualquer outro host/cert mantém validação
  padrão. Novo dep: `crypto` (SHA-256 síncrono).
- **pi-extension/**: config ganha `relayTlsInsecure?: boolean` (config.json /
  env `REMOTE_PI_TLS_INSECURE=1`); `RelayClient` (ws) passa
  `rejectUnauthorized: false`; `MeshClient` (fetch) passa
  `agent: https.Agent({ rejectUnauthorized: false })`.
- **Sem mudanças no relay nem no Caddy.**

## Resultado (2026-08-11)

- **Verificado end-to-end** (probe via tsx, depois deletado):
  - MeshClient strict → rejeita o cert autoassinado (comportamento padrão mantido)
  - MeshClient `tlsInsecure` → GET reachable (404) sobre TLS
  - RelayClient (ws) → hello/challenge/auth Ed25519 completo sobre wss ✓
- **Pitfall undici**: Node global fetch ignora `agent`; usa `dispatcher` com
  `new Agent({ connect: { rejectUnauthorized: false } })`, e a versão do
  undici **deve bater com `process.versions.undici`** do Node (24.18 →
  7.28.0), senão `invalid onRequestStart method`. Fix: `undici@7.28.0` fixa.
- **Pitfall dart:io**: `HttpClient.badCertificateCallback` é **setter-only**
  (sem getter) — test não lê, só exercita a fábrica.
- **CI do fork**: analyze falhou 1x (getter undefined) → corrigido;
  rebuild `app-build-test.yml` inclui agora analyze + test + build.

## Passos

### 1. app/ — helper de pin + fio no WS e no Dio

1. `pubspec.yaml`: adicionar `crypto: ^3.0.0`
2. Novo `app/lib/data/transport/relay_tls.dart`:
   - `kPinnedRelayCertSha256` (hex lowercase do fingerprint acima)
   - `kPinnedRelayHost = '118.145.119.50'`
   - `relayPinnedHttpClient()` → `HttpClient` com `badCertificateCallback`
     que compara `sha256(cert.der)` contra o pin (só para o host pinado;
     retorna false caso contrário → validação padrão)
3. `ws_transport.dart`: `IOWebSocketChannel.connect(uri,
   customClient: relayPinnedHttpClient(), pingInterval: ...)`
4. `mesh_client.dart`: `_defaultDio()` → `IOHttpClientAdapter(
   createHttpClient: relayPinnedHttpClient)` (via `package:dio/io.dart`)
5. Teste unitário do callback (host errado → false; host certo com cert
   aleatório → false; cert DER cujo sha256 == pin → true)

**Aceite**: `flutter analyze` zero issues; testes verdes.

### 2. pi-extension/ — flag TLS insecure

1. `config.ts`: `RemotePiConfig` + `relayTlsInsecure?: boolean`;
   `isRelayTlsInsecure()` lê env `REMOTE_PI_TLS_INSECURE` > config
2. `transport/relay_client.ts`: `new WebSocket(url, { rejectUnauthorized:
   !isRelayTlsInsecure() })`
3. `mesh/client.ts`: `MeshClientOptions` + `tlsInsecure`; `fetch(..., {
   agent: tlsInsecure ? new https.Agent({ rejectUnauthorized: false }) :
   undefined })` em GET e POST
4. Bridge o flag em `index.ts:3032` e `session/bridge.ts:129`
5. Testes de `config.ts` (env/config/default)

**Aceite**: `pnpm typecheck && pnpm test` verdes.

### 3. Config de runtime (sem código)

- Pi: `C:\Users\lion\.pi\remote\config.json` →
  `{"relay": "https://118.145.119.50:8443/remote-pi", "relayTlsInsecure": true}`
- App: Settings → relay URL → `https://118.145.119.50:8443/remote-pi`

### 4. Build + instalar + validar

1. Rebuild APK via fork CI (`app-build-test.yml`), baixar artifact
2. FTP pro celular (`ftp://192.168.3.59:2121`), instalar
3. App: mudar relay URL, reconectar → verificar `[ws-in]` conectado;
   Pi: reiniciar sessão remote-pi → conectar; trocar mensagem app↔Pi
4. (Opcional) `tcpdump`/server logs confirmam TLS no 8443

## Definition of Done

- [x] app: pin do cert em WS + REST, analyze/test verdes
- [x] pi-extension: flag tls insecure, typecheck/test verdes
- [x] config runtime aplicada nos dois clientes
- [x] APK novo instalado no celular e conectado via wss no relay
- [x] Mensagem real app↔Pi trafegando com TLS (sem queda p/ http)
  - 2026-08-11: verificado no servidor — 2 conexões ativas em :8443
    (Caddy TLS, IP do usuário), 0 em :8788 direto (sem plaintext)
  - Pi: pi-extension 0.6.0 local (pi install C:/Apps/remote_pi/pi-extension),
    `npm:remote-pi` removido; config com `relayTlsInsecure: true`

## Próximos planos

- Remover o fallback http do onboarding/Settings se TLS provar estável
- Renovar/roda de cert (2028) ou migrar p/ cert confiável (Sectigo IP) e
  atualizar o pin
