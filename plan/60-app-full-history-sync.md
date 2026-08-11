# 60 — App: sync completo do histórico da sessão (full history pull)

## Contexto

Hoje o app só recebe **os últimos N eventos** do Pi (`REMOTE_PI_SYNC_LIMIT`,
default 30) ao abrir/conectar uma sessão — o protocolo `session_sync` usa
"mirror semantics" (o app substitui o cache local pela resposta). Quando o Pi
reinicia ou a sessão é resetada, o histórico antigo some do app também
(design do plan 11). Usuário pediu: **o app puxar o histórico COMPLETO da
sessão atual de uma vez** ("一次性地抓取当前会话的历史记录"), sem exportar.

## Estrutura esperada

- **Protocolo**: `session_sync` ganha flag `full: boolean`. `full: true` → o
  Pi responde com **todos** os eventos da sessão (ignora o clamp de limite),
  **em lotes** (protocolo já define `eos`, mas nenhum dos lados implementava
  a acumulação — necessário para históricos grandes / imagens do plan 30).
- **Pi** (`pi-extension/src/index.ts`): `_handleSessionSync` com branch `full`
  → mapeia `_messageBuffer` inteiro, envia em lotes de ~400KB JSON
  (min 1 evento), `eos:true` no último. `limit` continua valendo no modo
  mirror (últimos N).
- **App** (`app/`):
  - `protocol.dart`: `SessionSync.full` (default false, serializado quando true)
  - `sync_service.dart`: **acumulação de lotes** por `in_reply_to` até `eos`
    (o path atual `_applyHistory(msg)` por mensagem quebraria com lotes);
    novo `requestFullHistory()` → `SessionSync(id, full: true)`
  - `chat_viewmodel.dart`: expõe `requestFullHistory()`
  - `chat_page.dart`: botão (ícone refresh/download) ao lado do "info" →
    dispara sync completo + SnackBar de feedback

## Passos

### 1. Pi — tipos + full batch

1. `protocol/types.ts`: `{ type: "session_sync"; id: string; limit?: number; full?: boolean }`
2. `index.ts` `_handleSessionSync`: se `msg.full` → `allEvents` inteiro,
   lotes de ~400KB (somando `JSON.stringify` dos eventos), `eos` no último;
   senão, mirror atual. `_sessionStartedAt === null` → histórico vazio igual.

**Aceite**: `pnpm typecheck && pnpm test` verdes; teste unit do batch helper.

### 2. App — protocolo + acumulação + trigger

1. `protocol.dart`: campo `full` em `SessionSync` (+ toJson)
2. `sync_service.dart`:
   - estado `_historyAccum` / `_historyStartedAt` por `in_reply_to`
   - `case SessionHistory`: acumula; só `_applyHistory` no `eos`
   - `requestFullHistory()`
3. `chat_viewmodel.dart`: `requestFullHistory()` → `_sync`
4. `chat_page.dart`: IconButton no AppBar (lucide `refreshCw`), tooltip
   "Sync full history", SnackBar "Histórico sincronizado" ao receber eos
   (hook num stream de eventos novo ou log simples — ver passo 3)

**Aceite**: `flutter analyze` zero; testes unit de acumulação (2 lotes + eos).

### 3. Feedback de conclusão (opcional, se barato)

O app pode ouvir o `session_history` final via stream existente e mostrar
SnackBar. Se exigir muito fio, fallback: SnackBar otimista "Sincronizando…"
apenas.

**Aceite**: botão dispara; app exibe algo ao terminar.

### 4. Build + instalar + validar

1. Push → CI do fork (analyze + test + build) → artifact
2. FTP pro celular, instalar
3. Teste: mandar >30 mensagens na sessão → app "Sync full history" →
   todo o histórico aparece (não só 30)

## Definition of Done

- [ ] Pi: `full` com lotes + `eos`; typecheck/test verdes
- [ ] App: `full` no protocolo, acumulação de lotes, botão na chat page
- [ ] CI verde (analyze + test + build) e APK no celular
- [ ] Manual: sessão com >30 msgs → sync completo traz tudo

## Próximos planos

- Persistência do histórico no Pi (sobreviver a restart) — mudaria o
  contrato do `session_started_at` (plan 11)
- Exportar histórico do app (compartilhar texto) — usuário disse que não
  precisa agora
