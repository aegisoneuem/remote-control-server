# Aegis One — Remote Control Reference (v134, server and agent 0.3.0)

**Purpose:** reference for rebuilding the Remote Control (RC) module in the Aegis One React/TypeScript console (`aegis_one_webui`), and for aligning the server (`aegis_one_server`, Go) and agent tracks.

**Design reference:** `Aegis-One-Integrated-Modern-Console_130.html`. Match its UI exactly: buttons, fonts, colours, tabs, tables. The RC code in that file is a plain-JS extension (`<script id="aegis-rc-ext">` and `<style id="aegis-rc">`) layered on the minified console bundle. Rebuild it as a proper feature module; do not copy the extension verbatim.

**Working prototype:** `aegis-rc` (Go). It contains `aegis-rc-server` (signaling) and `aegis-rc-agent` (Windows endpoint). It has been verified on a Windows 11 Hyper-V VM with a real screen, real input, consent, banner, TLS 1.3 and a pinned certificate. A 55-check end-to-end test passes on a Linux test desktop.

**Architecture source:** "Remote Control — Cross-Team Integration & Open Questions" (agent track, Vijay). Where this reference differs from that document, the difference is called out in §12.

---

## 1. Principles (non-negotiable)

1. **Consent first.** The signed-in end user must accept every session, and every additional viewer, before anything starts. "No" is the default button, and no answer within 60 seconds counts as declined.
2. **Tell the user exactly what is requested.** The prompt shows who is asking, the session type, the reason or ticket, whether the session is recorded, the time limits, and a verification code.
3. **Escalations ask again.** Full control (from View Only), the command line and a restart each need fresh user approval when `per_action_consent` is on, which is the default.
4. **TLS 1.3 only** for all console↔server and agent↔server traffic. The agent pins the server certificate's SHA-256.
5. **RBAC before consent.** The server checks the operator's permission before the user is ever prompted.
6. **Signed kickoff.** The server signs `open_rc` with Ed25519. The agent verifies the key id, the signature, the TTL, replay protection and the target device.
7. **The agent enforces, the console displays.** The agent decides who may send input (one controller; viewers are view-only), applies policy limits, and cleans up. The console never enforces security on its own.
8. **Server is signaling only.** Screen data never passes through the server.
9. **Live only on the RC page.** No sample sessions, sample history or estimated recording sizes. Show only real data.
10. **Audit holds metadata only.** Who, what, when and why. Never screen content, chat text or command output.

## 2. Architecture

```
Console (browser)  ──WSS, TLS 1.3──►  RC Server  ◄──WSS, TLS 1.3, pinned──  Agent (endpoint, outbound only)
      │                                 │ RBAC · signs open_rc (Ed25519) · relays SDP/ICE · policy · audit
      └──────────── WebRTC peer to peer (DTLS): screen, input, control, chat, shell ────────────┘
```

**Session sequence:**
1. Console → `rc_start`.
2. Server checks permissions, signs `open_rc` and replies `rc_started` (psid, session id, verification code).
3. Agent verifies the command → `rc_status verified`.
4. Agent shows the consent prompt → `rc_status consent_wait {code, user}`.
5. User accepts → `rc_status accepted`.
6. Agent → `rc_offer` (SDP). Console → `rc_answer`. Both sides trickle `rc_ice`.
7. Data channels open. The first screen keyframe arrives and the session goes **Live**.

## 3. Console module

### 3.1 Placement
- Sidebar: **Operations › Remote Control**, directly below Live Activity. Use the same nav-item markup, icon style and active state as the existing items.
- Breadcrumb: `Operations › Remote Control`.
- Proposed route: `/operations/remote-control`. The viewer is a full-screen overlay; it can also be a route, `/devices/:deviceId/remote-control/:sessionId`.

### 3.2 Page header
- Title "Remote Control".
- Subtitle: "View and control managed endpoints for service desk support. Every session is visible to the end user, audited and, by policy, recorded."

Actions, right to left:

| Action | Behaviour |
|---|---|
| **End-User Share Page** | Demo only (§5). |
| **Agent Endpoint** | Demo only (§5). |
| **Connect Server** | Status chip. States:<br>• `off`: "Connect Server"<br>• `connecting`: amber blinking dot<br>• `on`: "Server · TLS 1.3", green dot<br>• `error`: red border |
| **Operator** select | Demo only. Disabled while connected; the identity then comes from the server token. |

### 3.3 Connect Server dialog
- **Fields:** server address (`https://host:8443`, remembered in localStorage) and operator token (password input, kept in **sessionStorage only**).
- **Note text:**
  - when connected: "Connected as {name} · TLS 1.3 · signing key {key_id} · {n} agent(s) online."
  - before connecting: "The token is kept in this tab only. If the server uses its own certificate, open its address once in this browser and accept it."
- **Buttons:** Cancel or Disconnect, and Connect.

### 3.4 Tabs
New Session · Active Sessions (count badge) · Session History · Recordings · Policy.

**New Session**
- **Mode cards:** View Only, Full Control, Chat Only (the existing `aw-modes` card style).
- **Card 01 "Session Details":**
  - Reason/ticket: required by policy. The server also rejects an empty reason for controllers.
  - Monitor, Quality.
  - Screen Source. Order:
    1. `native` — "Aegis agent on the real device (native, via the Aegis RC server)"
    2. `agent`
    3. `sim`
    4. `local`
    5. `paired`
  - Session Options (locked, set by policy): Record Session, On-Screen Indicator (always), Ask User to Accept, Run as SYSTEM.
- **Card 02 "Select Device":**
  - Search by hostname, IP or logged-in user. Platform filter. Radio list.
  - Devices that have a native agent sort first, with the badge **"Agent Live · Native"** (green), or **"In Session · Native"** while busy.
  - Native agents missing from the console inventory are appended as rows.
  - Choosing a device that has a native agent auto-selects source `native`.
- **Submit bar:**
  - Summary: `"{mode} · {monitor} · Recorded · User must accept · Native Aegis agent, real device"`.
  - Primary button: **Start Session**.
- **Validation messages, verbatim:**
  - "Connect to the Aegis RC server first (Connect Server, top right)."
  - "No native Aegis agent is connected for {device}."
  - "{device} is already in a session controlled by {operator}. Join it from Active Sessions."
  - "Enter a reason or ticket number. Policy requires one."

**Active Sessions**
- Real sessions only: your own, plus sessions the server reports for native agents.
- Columns: Session, Device (sub-line "Native agent · {os}"), Controller (badge "You"), Mode, Started, Duration (live ticking), Participants, and an action ("Open" or "Join as Viewer").

**Session History**
- Rows come from two places, merged by session id and sorted newest first:
  - local history of real sessions;
  - sessions rebuilt from the server audit log (`rc_requested` → `session_ended`, plus `consent_declined` and `rc_denied`). This needs `remotecontrol.audit` and refreshes at most every 15 seconds.
- Columns: Session, Device, Operator, Mode (sub-line "From Server Audit", "Real Screen" or "Simulated"), Started, Duration, Reason/Ticket, Ended, Recording ("Play" or "Not Recorded").
- Below the table, a **Server Audit Log** card with a "Load Audit Log"/"Refresh" button and columns Time, Event, Operator, Device, Session, Detail.

**Recordings**
- Real recordings only (`realRec`).
- Columns: Session, Device, Operator, Recorded, Duration, Size (real bytes), Events, and Play.
- Note: "Real recordings of live sessions only. Playback uses its own permission (Recording: View)…"

**Policy**
- When the server is connected, show the **Server Policy · Native Agents** card first. It is editable only with `remotecontrol.policy`, and its Save button is "Save Server Policy".
- Its fields are listed in §7.
- The local simulator policy follows under the sub-heading "Simulator Policy · This Browser".

### 3.5 Viewer (full-screen overlay)
**Colours:** bar `#1D2127`, toolbar `#181B20`, stage `#111418`, live screen background `#0B0D10`, accent gold `#C6A16B`, borders `#2C3138`/`#3A4048`, text `#E8EAED`, muted `#9AA3AE`, live green `#3FB950`/`#7EE2A0`, danger `#B42318`.

**Top bar**
- Left: LIVE/CONNECTING pill and REC pill.
- Device name, with "{os} · {ip} · {user}". For native sessions use the OS, IP and user **reported by the agent**.
- Meta: session id · mode (plus " · Viewer") · elapsed time · "{n} in session".
- Right: Minimise, and End Session (danger) or Leave.

**Toolbar groups**
1. View Only | Full Control (segmented; "Open Screen" in chat-only).
2. Source chip ("Real Device · Native Agent") · Ctrl+Alt+Del.
3. Native only: Privacy Mode (toggles to "Privacy On") · Quality select (Balanced `12,70`, Sharp `20,80`, Low bandwidth `6,50`, sent as `{fps, q}`) · Fullscreen. Fullscreen uses `requestFullscreen` plus `navigator.keyboard.lock()`.
4. Chat (unread count) · Command Line · Participants.
5. Reboot · Request Control (viewers).

**Stage states**
- **Connecting:** a steps list with states `done` / `now` / pending:
  1. "Server Checked Your Permission"
  2. "Server Signed open_rc (Ed25519)"
  3. "Agent Verified Signature"
  4. "Waiting for User to Accept"
  5. "Connecting Peer to Peer"
  6. "Session Started" (or "Viewing as Participant", or "Chat Opened")

  From step 3 onwards it also shows:
  - a **Verification code** box (gold border, 24px monospace);
  - "{user} is asked to allow:" followed by session type, reason, recorded, limits and the "ask again" line.
- **Live:** the screen fills the stage (object-fit: contain).
  - The label "Full control · Click the screen, then type" fades out after 4 seconds.
  - Viewers see "Viewing · {controller} has control".
- **Asking:** a top-centre strip, "Waiting for {user} to allow full control | Verification code 123 456", shown while a per-action consent is pending.
- **Not connected:** title "Session Not Connected", the reason, and buttons "Try Again" and "End Session".

**Watchdogs**
- No peer connection within 20 seconds → not connected, with the message "Could not connect peer to peer within 20 seconds. Check the firewall on the device (allow aegis-rc-agent.exe)…".
- Connected but no frame within 8 seconds → show the agent's last notice, or "Connected to the agent, but no screen has arrived yet…".

**Footer**
- Left: "Signaling TLS 1.3 · DTLS 1.2 data channel · peer to peer with the native agent · {w×h} · {fps} fps · {kbps} kbps · {rtt} ms". The DTLS version comes from `getStats()` `transport.tlsVersion`: `FEFD` = 1.2, `FEFC` = 1.3.
- Right: a one-line description of the source.

**Side panels (340px)**
- **Chat:** bubbles, with your own messages on the right in gold.
- **Command Line:** PowerShell-style prompt `PS C:\Windows\system32>`. Output arrives asynchronously on the shell channel. `cls` clears locally.
- **Participants:** avatar initials, name ("(you)"), role. The controller sees "Pass Control" next to each viewer. A hint explains that the agent ignores viewer input.

**Dialogs**
- End session.
- Pass control.
- Control request (from a viewer): "Pass Control" / "Decline".
- Reboot.

**Input mapping (native)**
- Pointer events are mapped to fractions (0–1) of the content box of the `<canvas>`, honouring letterboxing.
- `pointermove` is throttled to 25 ms on the unordered `move` channel.
- `pointerdown` and `pointerup` (with `button`), `wheel` (`deltaX`/`deltaY`), and `keydown`/`keyup` (`key`, `code`, modifiers) go on the reliable `input` channel.
- Pointer capture is used during drags. The context menu is suppressed.

### 3.6 Recording
- The console records the received canvas stream with `MediaRecorder` (`video/webm;codecs=vp9` → `vp8` → `webm`).
- A restart splits a session into parts, which play in sequence.
- Production target: agent-side, encrypted recording with retention (open question in §12).

## 4. Wire protocol

### 4.1 Console ↔ server (`wss://host:8443/ws/console`)

| Direction | `t` | Fields |
|---|---|---|
| → | `auth` | `token` |
| ← | `hello` | `operator {id,name,perms}`, `server {version,tls,key_id,ice_servers}`, `policy`, `agents[]` |
| ← | `auth_failed` | `text` |
| ← | `agents` | `agents[] {device,os,user,ip,version,caps,online,screen{w,h},session{id,operator,mode,people,started,reason}}` |
| → | `rc_start` | `device, mode(view/control/chat), reason, join(session id for viewers), session(reopen own session)` |
| ← | `rc_started` | `psid, session, device, key_id, code, mode` |
| ← | `rc_status` | `psid, k: verified / consent_wait (code, user) / accepted` |
| ← | `rc_deny` | `psid, reason` |
| ← | `rc_offer` / → `rc_answer` | `psid, sdp {type,sdp}` |
| ↔ | `rc_ice` | `psid, c {candidate,sdpMid,sdpMLineIndex,usernameFragment}` |
| → | `rc_close` | `psid, end (true = controller ends for everyone)` |
| → | `policy_set` / ← `policy` | `policy` (requires `remotecontrol.policy`) |
| → | `audit_list` / ← `audit` | `audit[] {at,event,operator,device,session,detail}` (requires `remotecontrol.audit`) |
| ← | `error` | `text` |

### 4.2 Agent ↔ server (`/ws/agent`)
- **Agent → server:**
  - `agent_auth {token(enrollment), device, os, user, ip, version, caps[], screen}`
  - `agent_state {user, sess}`
  - `rc_status`, `rc_deny`, `rc_offer`, `rc_ice`
  - `rc_event {session, k, text, extra.operator}` (audit)
- **Server → agent:** `auth_ok`, `open_rc {psid, cmd_b64, sig, key_id}`, `rc_answer`, `rc_ice`, `rc_close`.
- **Routing:** the server keeps `psid → {console, agent, session, device, operator}`. A console or agent may only signal its own psids.

### 4.3 Signed `open_rc`
- **Fields, in this exact order** (the signature covers the exact JSON bytes, carried base64 as `cmd_b64`): `type="open_rc", sid, session, device, operator, operator_id, role(controller|viewer), mode, reason, policy, issued(unix ms), ttl(60), nonce, key_id`.
- **Key id:** first 6 bytes of SHA-256(public key), in hex.
- **Agent checks, in order:**
  1. known key id;
  2. Ed25519 signature;
  3. type and key id match;
  4. TTL (not older than `ttl` seconds, not more than 30 seconds in the future);
  5. sid matches psid;
  6. device matches;
  7. sid not seen before (replay);
  8. session rules.
- **Session rules:**
  - A viewer needs an existing session with the same id.
  - A controller is refused if another session exists.
  - **Only the current controller (same `operator_id`) may reopen its own session.** This blocks hijack.
  - Refused while a consent prompt is open.
- **Verification code:** `SHA-256("aegis-rc-verify:" + sid)`, first 4 bytes mod 10⁶, formatted `"%03d %03d"`.

### 4.4 Data channels (the agent creates them all, then sends the offer)

| Label | Ordered | Direction | Payload |
|---|---|---|---|
| `screen` | yes | agent → console | binary tiles (below) |
| `input` | yes | console → agent | `{k: down/up (b,x,y) / wheel (dx,dy) / key (key,code,down,ctrl,alt,shift,meta)}` |
| `move` | **no, 0 retransmits** | console → agent | `{k:"move", x, y}` |
| `control` | yes | both | see below |
| `chat` | yes | both | → `{x}`; ← `{who, x}` |
| `shell` | yes | both | → `{c}`; ← `{out}` |

**Control messages**
- **Console → agent:** `mode {mode}`, `privacy {on}`, `keyframe`, `quality {fps 2–30, q 30–90}`, `sas`, `reboot`, `pass {to: psid}`, `reqctl`, `deny_req {to}`, `end`.
- **Agent → console:**
  - `roster {session, people[{id,tab,operator,role,mode}], privacy}`
  - `notice {text}`
  - `consent_wait {action, code}`, `consent_result {action, ok}`
  - `reqctl {tab, operator}`, `req_denied`
  - `ended {reason}`

**Screen tile format** (big endian; only changed 64×64 tiles are JPEG-encoded at quality 70; batches stay at or under 56 KB):
- Frame start: `0x01 | u16 width | u16 height | u32 seq | u8 key`
- Tile batch: `0x02 | u16 count | count × (u16 x | u16 y | u16 w | u16 h | u32 len | JPEG)`
- Frame end: `0x03 | u32 seq`

The console decodes tiles in order with `createImageBitmap` and draws them onto a canvas. The first frame end makes the session Live.

## 5. Screen sources

| Source | Status | Notes |
|---|---|---|
| `native` | **Production path** | Native agent through the server. Everything in this document applies. |
| `agent` | Demo | Browser tab `#rc-agent` simulating an endpoint, over BroadcastChannel signaling. Same browser only. |
| `sim` | Demo | Simulated desktop, no media. |
| `local` / `paired` | Demo | Browser screen share. View only; no input possible. |

The production console needs only `native`. Keep the demo sources behind a "Demo sources" flag, or drop them.

## 6. Agent behaviour (endpoint)

| Area | Behaviour |
|---|---|
| Connection | Outbound only, with reconnect backoff from 1 to 30 seconds. |
| Consent prompt (Windows) | System-modal Yes/No with "No" as default and a 60-second timeout. |
| Banner | Topmost and excluded from capture (`WDA_EXCLUDEFROMCAPTURE`). Text: "Remote session in progress · {operator} · {mode} · {n} watching · Recorded · Screen hidden", plus an **End session ✕** button. |
| Chat window | The end user can read and reply. Enter sends. Closing the window only hides it. |
| Privacy mode | A full-screen black window, click-through and excluded from capture. Local input is locked with `BlockInput` when the agent is elevated. All injection runs on the same OS thread, as Windows requires. |
| Capture | GDI on a dedicated locked OS thread, including the cursor. The bitmap is deselected before `GetDIBits`. Default 12 fps, diff tiles, backpressure when `bufferedAmount` exceeds 4 MB, a per-viewer keyframe when its channel opens. |
| Input | `SendInput` with absolute coordinates. Printable keys go as Unicode; shortcuts and special keys as virtual keys. Held modifiers are released on mode change and at session end. |
| Limits | Idle timeout (default 15 minutes without controller input) and maximum session length (default 120 minutes). |
| Cleanup at end | Release keys, remove the privacy screen, clear the clipboard, optionally lock the workstation, hide the banner, and post a chat line saying the session ended. |
| Prototype gaps | Runs in the user session, so there is no Ctrl+Alt+Del, UAC or lock-screen capture. Production is a SYSTEM service with a per-session helper. |

## 7. Policy, permissions, audit

**Policy** (server, signed into every `open_rc`):

| Field | Default | Meaning |
|---|---|---|
| `consent` | `always` | `always`, or `unattended_if_no_user` (only when nobody is signed in) |
| `per_action_consent` | true | Ask again for control, shell and reboot |
| `record` | true | Recording required |
| `idle_s` | 900 | Range 60–14400 |
| `max_s` | 7200 | Range 300–43200 |
| `clear_clipboard_on_end` | true | |
| `lock_on_end` | false | |
| `privacy_allowed` | true | |
| `shell_allowed` | true | |
| `reboot_allowed` | false | The agent also needs `-allow-reboot` |

**Permissions**
- `remotecontrol.start`
- `remotecontrol.control` (needed for Full Control)
- `remotecontrol.recording.view`
- `remotecontrol.policy`
- `remotecontrol.audit`

**Audit events**
- Agents and consoles: `agent_online`, `agent_offline`, `agent_rejected`, `console_connected`, `console_auth_failed`.
- Requests: `rc_requested`, `rc_refused` (server RBAC), `rc_denied` (agent).
- Consent: `consent_granted`, `consent_declined`, `consent_skipped`.
- Session: `peer_joined`, `peer_left`, `mode`, `privacy`, `shell_command` (the command line itself, as metadata), `input_ignored`, `control_passed`, `reboot`, `chat_from_user` (no content), `rc_close`, `session_ended` (with a cleanup summary), `policy_changed`.

**Secrets:** operator and enrollment tokens are stored as SHA-256 hashes only and compared in constant time.

## 8. Session state machine (console)

`idle → creating (rc_start) → signed (rc_started) → verified → awaiting_consent → connecting (offer/answer/ICE) → live(view|control|chat)`

| From | Event | To |
|---|---|---|
| live | per-action consent pending | live + asking |
| any | `rc_deny`, timeout, `failed` | not_connected (Try Again) |
| any | `ended`, End, Leave | closed |

A history row is written on close.

## 9. Proposed target structure

**Console**
```
src/features/remote-control/
  api/serverClient.ts       WSS client, auth, message types (§4.1)
  webrtc/peer.ts            RTCPeerConnection, answer, ICE, getStats (DTLS version, RTT)
  webrtc/screenDecoder.ts   tile format (§4.4), ordered decode, canvas, fps/kbps
  webrtc/input.ts           pointer/wheel/keyboard mapping (§3.5)
  state/sessionMachine.ts   §8
  components/  RemoteControlPage, NewSessionTab, ActiveSessionsTab, HistoryTab, RecordingsTab,
               PolicyTab (server + local), ServerConnectDialog, Viewer, ViewerToolbar, ConnectSteps,
               VerificationCode, ConsentDisclosure, AskingStrip, ChatPanel, ShellPanel,
               ParticipantsPanel, RecordingPlayer
  hooks/useRcServer.ts, useRcSession.ts
  __tests__/                port the acceptance tests in §10
```

**Server:** `internal/remotecontrol/`, as a sibling of `remoteops` (per the agent-track doc). It holds the handlers in §4.1–4.2, migration `0023_remote_control.sql`, the permissions in §7 and the audit events.

**Prototype source:** `aegis-rc/internal/{wire,server,agent,screen,platform}`.

## 10. Acceptance tests (55, all passing in the prototype)

**Transport and identity**
- TLS 1.2 refused.
- Agent refuses a wrong certificate pin.
- Agent connects over TLS 1.3.
- Operator identity comes from the token.

**Starting a session**
- Native agent listed and auto-selected.
- Server policy shown.
- Verification code shown, and the same code appears in the user prompt with type, reason and recording.
- Live after consent.
- Real frames arrive.
- Footer shows TLS 1.3 and DTLS.

**Input and tools**
- Click, typing, Ctrl+C and wheel are applied.
- Shell asks first, then returns output.
- Privacy mode is applied and shown.
- Chat reaches the user's window, and the user's reply reaches the console.

**Collaboration and access control**
- Second operator joins as a viewer after user consent, gets real video, and has no input layer.
- Roster shows 2.
- Hijack by another operator is refused.
- Operator without `remotecontrol.control` is refused before the user is asked.
- Viewer leaves and the controller stays live.

**End and retry**
- Cleanup at end: privacy off, clipboard cleared.
- Real recording saved.
- A decline is shown, then a retry is accepted.
- Declined escalation stays View Only; a second escalation is accepted.

**Chat only and live-only data**
- Chat-only connects, opens the user chat window, sends no screen, and the reply arrives.
- No sample sessions, recordings or history.
- A fresh browser sees history rebuilt from the server audit.

**Audit**
- Contains `rc_requested`, `consent_granted`, `consent_declined`, `shell_command`, `privacy`, `rc_refused` and `session_ended`.
- Contains no chat content.

## 11. Known limits of the prototype

- Agent runs in the user session (see §6).
- Primary monitor only.
- JPEG tiles, not a video codec. Next step: H.264/VP8 over a media track for smooth motion.
- No TURN: same network or a reachable network only. Pass `-ice` to add TURN.
- Unsigned binaries trigger SmartScreen and antivirus warnings. Production needs code signing.
- The signing key is a file. Production needs HSM/KMS, `key_id` rotation, and a revocation list (the agent already accepts several keys).
- Recordings stay in the operator's browser.

## 12. Decisions to confirm with the agent track (Vijay)

1. **Consent-first instead of unattended-first.** The product owner asked for consent on every session. Unattended access is only possible when policy allows it and nobody is signed in.
2. **Operator identity is a human user**, bound to an operator token in the prototype. This answers Server Q2 and Console Q1. Production should bind to console SSO users and `issued_by_user_id`.
3. **Transport for the prototype:** JSON over WSS mirroring `RCSession`. Production moves to the proto (`open_rc` Command plus an `RCSession` bidi RPC), with additive fields such as `policy`, `operator_id`, `key_id` and `reason`.
4. **Recording location** (Server Q4): agent-side and encrypted is proposed, because the server never sees media.
5. **Policy fields in §7**, **per-action consent** and **hijack protection** are proposed additions to the agent contract.


## 13. Changes in 0.2.0 (production hardening, phase 1)

**Protocol additions (all additive):**

| Message | New field | Meaning |
|---|---|---|
| `rc_started` (server → console) | `ice[] {urls[], username?, credential?}` | ICE servers for this peer connection: STUN plus short-lived TURN credentials |
| `open_rc` (signed) | `ice[]` (last field) | The same list, signed, for the agent |
| `rc_deny` | `close` | Fixed close reason (below) |
| `rc_close` (server → agent) | `close` | `operator_ended` or `console_disconnected` |
| control `ended` (agent → console) | `close` | Fixed close reason |
| `rc_offer` on a live psid | — | Agent ICE restart; the console answers on the same `RTCPeerConnection` |

**Close reasons:** `permission_denied`, `reason_required`, `agent_offline`, `invalid_command`, `device_busy`, `no_user`, `user_declined`, `peer_failed`, `operator_ended`, `user_ended`, `idle_timeout`, `max_duration`, `console_disconnected`, `rate_limited`, `internal_error`. The `session_ended` audit detail ends with the code in brackets.

**TURN credentials:** coturn `use-auth-secret` scheme. Username `"<unix expiry>:<psid>"`, credential `base64(HMAC-SHA1(secret, username))`, default lifetime 2 hours (`-turn-ttl`). The secret is read from `AEGIS_TURN_SECRET`.

**Server protections:**
- Five failed logins from one address within 5 minutes block it for 10 minutes; audit `address_blocked`.
- Twenty `rc_start` per operator per minute.
- WebSocket ping every 25 seconds; a peer that stops answering is dropped after 70 seconds.
- HTTP idle timeout and header size limits.
- Structured logs (`slog`, text or JSON).

**Agent reconnect:** when the peer connection becomes `disconnected` or `failed`, the agent waits 3 seconds, then makes up to three ICE restarts of 10 seconds each before ending with `peer_failed`. The console shows a "Network interrupted" strip and waits up to 40 seconds.

**Tests added:**
- Unit tests: TURN credential format, per-session ICE list, login limiter, sliding-window limiter.
- End-to-end: the browser restricted to `iceTransportPolicy: relay` connects through a TURN server using the minted credential (selected pair `relay`); close codes on RBAC refusal, decline and unknown device; the fifth bad login blocks the address, even for a valid token afterwards.
- Not yet covered by an automated test: the ICE-restart path after a real network change.


## 14. Changes in 0.3.0 (production features, phases 2 to 4)

### 14.1 Storage (server)

SQLite through a pure-Go driver, file `aegis-rc.db`, rollback-journal mode (WAL is avoided: its shared-memory index crashed on restart with this driver). Tables:

| Table | Columns |
|---|---|
| `operators` | `id, name, token_sha256, perms (JSON), created_at, disabled` |
| `settings` | `k, v (JSON)`; holds the policy |
| `audit` | `id, at, event, operator, device, session, detail` |
| `recordings` | `session, device, operator, reason, started_at, ended_at, duration_ms, chunks, bytes, width, height, key_id, eph_pub, wrapped_key, status, expires_at` |

The queries are portable to Postgres (migration `0023`). JSON files from 0.1/0.2 are imported once, and `audit.jsonl` is still appended as a SIEM export.

### 14.2 Encrypted recordings

**Signed `open_rc`** gains two fields, `rec_key_id` and `rec_pub` (X25519 public key, base64).

**Policy** gains `retention_days` (default 30, range 1 to 3650).

**Agent → server messages:**

| Message | Fields |
|---|---|
| `rec_open` | `session`, `rec {key_id, eph_pub, wrapped}`, `screen {w, h}` |
| `rec_chunk` | `session`, `n`, `data` (base64 sealed chunk) |
| `rec_close` | `session`, `n` = duration in ms |

The server accepts them only for a session it signed for that device.

**Crypto** (`internal/rec`):
- The data key (DEK) is 32 random bytes per recording.
- Each chunk is AES-256-GCM. The nonce is 4 zero bytes followed by the chunk number (u64 big endian). The associated data is the session id followed by the chunk number.
- The DEK is wrapped with X25519 using an ephemeral key, then HKDF-SHA256 with salt = session id and info = `aegis-rc-rec-v1`, then AES-256-GCM.

**Chunk content:** repeated `[u32 t_ms][u32 len][screen tile message]`. There is a full keyframe every 30 seconds, and a chunk is flushed every 5 seconds or at 512 KB.

**Console ↔ server** (`remotecontrol.recording.view` required):

| Direction | Message | Fields |
|---|---|---|
| → | `rec_list` | |
| ← | `recordings` | `recs[] {session, device, operator, reason, started, ended, duration_ms, bytes, chunks, status, expires, w, h}` |
| → | `rec_get` | `session` |
| ← | `rec_meta` | |
| ← | `rec_data` | `n`, `data` (base64 plaintext frames), repeated |
| ← | `rec_end` | `text?` (error text, if any) |

**Audit events:** `recording_started`, `recording_saved`, `recording_viewed`, `recording_tampered`, `recording_deleted`. A sweep every 5 minutes deletes expired recordings.

### 14.3 Windows service

**Commands:** `aegis-rc-agent service install|uninstall|start|stop|status`.

**Service setup:**
- Service `AegisRC`, running as LocalSystem, automatic start, with recovery restarts.
- The exe is copied to `%ProgramFiles%\AegisRC`.
- The config goes in `%ProgramData%\AegisRC\agent.json`. The folder DACL is SYSTEM and Administrators only, and the token is DPAPI-protected (machine scope).
- `SoftwareSASGeneration` is set to 1.

**Supervisor:**
- Every 2 seconds it picks the active session: the console session if it is active, otherwise an active RDP session, otherwise the console session.
- It launches `aegis-rc-agent helper` in that session with a duplicated SYSTEM token (`SetTokenInformation(TokenSessionId)`, `CreateProcessAsUser`, desktop `winsta0\default`).
- The helper runs inside a kill-on-close job object.
- If the active session changes, the helper is moved there. A crashing helper is retried with backoff.

**Helper:**
- The capture and input threads follow the input desktop (`OpenInputDesktop`/`SetThreadDesktop`), which covers UAC prompts and the lock and logon screens.
- The user name comes from `WTSQuerySessionInformation`, so the helper does not report "SYSTEM".
- Ctrl+Alt+Del uses `SendSAS(FALSE)` from `sas.dll`.
- The agent adds the caps `system_service`, `secure_desktop` and `sas`.
- The consent text says shell commands run as SYSTEM.

### 14.4 Smooth video

**Agent:**
- If FFmpeg is found, the agent adds an H.264 video track (`profile-level-id=42e01f`, packetization-mode 1) before the offer.
- The encoder is libx264: ultrafast preset, zerolatency tune, baseline profile, no B-frames, 25 fps, 2500 kbps, a keyframe every 4 seconds, AUD-delimited access units, and the frame capped at 1920 px wide.
- A PLI/FIR from the viewer, a new viewer, or a resolution change restarts the encoder to get an IDR frame (at most once every 2 seconds).

**Console:**
- The console draws the video onto the existing canvas with `requestVideoFrameCallback`, so input mapping, recording and live detection are unchanged.
- If no frame is decoded within 6 seconds, it sends the control message `{k: "video", on: false}` and the agent switches that viewer to JPEG tiles.

**Recordings** still use tiles.

**DXGI Desktop Duplication** is opt-in (`-capture dxgi`). It uses COM vtable indices verified against published headers and falls back to GDI on any error.

**Production note:** replace FFmpeg/libx264 (GPL) with the Media Foundation H.264 encoder or OpenH264.

### 14.5 Tests

**Automated, all passing on Linux:**
- 55 base end-to-end checks with video on.
- 12 phase 1 checks: TURN relay-only, close codes, lockout.
- 15 phase 2 checks:
  - JSON migration to SQLite
  - ciphertext at rest
  - decrypted playback that draws frames
  - RBAC on recordings
  - tamper detection
  - audit events
- 6 phase 4 checks: H.264 decoded at 18 fps or more, inbound RTP bitrate, input through video, tiles fallback.
- Unit tests for the wire format, screen encoder, server limiter and TURN credentials, recording crypto (including tamper, reorder and wrong key), the store (including reopen after restart), and the H.264 encoder.

**Not automatable here, to run on Windows:**
- service install and the session helper
- the secure desktop
- `SendSAS`
- DXGI
- ICE restart after a real network change
