# Aegis Remote Control: Native Agent and Server (v0.3.1)

This package connects the Aegis One console (v134) to real Windows devices. The agent captures the real screen and applies real mouse and keyboard input. Nothing starts until the signed-in user accepts.

It follows the agent-track Remote Control design:

- **Server** (`aegis-rc-server.exe`) handles signaling only. It never receives the live screen. It checks the operator's permission before the user is asked, signs `open_rc` with Ed25519, relays SDP and ICE, mints per-session TURN credentials, stores encrypted recordings, keeps the policy, and writes the audit log (SQLite).
- **Agent** (`aegis-rc-agent.exe`) connects outbound only, so no inbound port is opened on the endpoint. It verifies the signature, TTL and replay, and asks the user for consent. It then streams the screen (H.264 or JPEG tiles), enforces the policy, and records the session encrypted. It runs in the foreground for testing, or as a Windows service in production.
- **Console** (`Aegis-One-Integrated-Modern-Console_134.html`) is opened from its file in Chrome or Edge.

## Status

| Area | Linux end-to-end | Windows |
|---|---|---|
| Foreground agent: consent, banner, screen, mouse, keyboard, command line, two VMs | 55/55 checks | Tested on two Hyper-V VMs |
| 0.2.0: TURN, close codes, login lockout, keepalive | 12/12 checks | Not yet run |
| 0.2.0: reconnect (ICE restart) after a network change | Not covered by an automated test | Not yet run |
| 0.3.0: encrypted recordings, SQLite, migration | 15/15 checks | Not yet run |
| 0.3.0: H.264 video, tiles fallback | 6/6 checks | Not yet run (needs `ffmpeg.exe`) |
| 0.3.0: service, secure desktop, Ctrl+Alt+Del, DXGI | Not possible on Linux | Compiled and vetted, **not yet run** |

Report anything that fails on Windows together with the agent window's log, or `C:\ProgramData\AegisRC\logs` in service mode.

## Quick test on one Windows PC

1. **Start the server.** Double-click `1-start-server.cmd`. On the first run it prints the following and also writes them to `aegis-rc-data\FIRST-RUN-SECRETS.txt`:
   - the agent enrollment token
   - three operator tokens (Aegis Admin, Karan, Priya N.)
   - the certificate SHA-256

   If Windows Firewall asks, allow access on **private** networks only.

2. **Prepare the agent.**
   - Copy `aegis-rc-data\agent-trust.pub` next to `aegis-rc-agent.exe`.
   - Edit `2-start-agent.cmd` and set:
     - `SERVER=wss://127.0.0.1:8443`
     - `TOKEN` (the agent enrollment token)
     - `PIN` (the certificate SHA-256)
     - `DEVICE` (use a name from the console's device list, for example `PC-DEL-102`)

3. **Start the agent.** Double-click `2-start-agent.cmd`. The log should show `connected ... over TLS 1.3` and `enrolled`.

4. **Trust the certificate.** In Chrome or Edge, open `https://127.0.0.1:8443`. Accept the certificate warning once; the server uses its own certificate.

5. **Connect the console.**
   - Open the console HTML file and go to **Operations › Remote Control**.
   - Click **Connect Server**.
   - Enter `https://127.0.0.1:8443` and the **Aegis Admin** token.
   - The button shows **Server · TLS 1.3**.

6. **Start a session.**
   - In **New Session**, choose the device. It shows **Agent Live · Native**, and the source switches to the native agent.
   - Choose **Full Control**, enter a reason, and click **Start Session**.

7. **Accept on the endpoint.** A Windows prompt shows:
   - who is asking
   - the session type
   - the reason
   - whether the session is recorded
   - the time limits
   - a verification code (the operator sees the same code)

   Choose **Yes** to allow. The real screen appears in the console and mouse and keyboard work.

On a single PC, you are controlling the same screen you are watching, so expect a mirror effect. For a proper demo, run the agent on a second PC.

## Two PCs on the same network

- **Server PC:**
  - In `1-start-server.cmd`, set `-hosts` to the server's LAN IP, then start it.
  - If the server already ran once without that IP, delete `aegis-rc-data\tls-cert.pem` and `aegis-rc-data\tls-key.pem` and start it again. This creates a new certificate, so update `PIN` on every agent.
- **Endpoint PC:**
  - Copy `aegis-rc-agent.exe`, `agent-trust.pub` and `2-start-agent.cmd`.
  - Set `SERVER=wss://<server IP>:8443`.
- **Operator PC:** open `https://<server IP>:8443` once, then connect the console to that address.

Peer-to-peer media needs the two machines to reach each other directly. Across different networks, add a TURN server with `-ice turn:host:3478` on both server and agent.

## What the user is protected by

| Control | How it works |
|---|---|
| TLS 1.3 only | The server refuses TLS 1.2 and lower. The agent also pins the server certificate's SHA-256. |
| Signed kickoff | `open_rc` is signed with Ed25519, single use, with a 60-second TTL. The agent rejects a wrong key, tampering, replay, an expired command, or a command for another device. |
| RBAC before consent | Permissions are checked before the user is asked:<br>• `remotecontrol.start` to start a session<br>• `remotecontrol.control` for Full Control<br>• `remotecontrol.policy` to change policy<br>• `remotecontrol.audit` to read the audit log |
| Consent first | Every session asks the signed-in user, and so does every extra viewer. "No" is the default button, and no answer within 60 seconds counts as declined. Unattended access is possible only if policy allows it **and** nobody is signed in. |
| Per-action consent | Full control, the command line and a restart each ask the user again. |
| Agent-enforced roles | One controller at a time. The agent ignores input from viewers and from anyone in View Only mode. Only the current controller can reopen its session. |
| Visible indicator | A topmost banner shows who is connected, the mode, viewers, recording and privacy. The **End session** button on the banner lets the user stop the session at any time. |
| Privacy mode | The user's screen goes black while the operator keeps seeing the desktop (the window is excluded from capture). Local input is locked when the agent runs as administrator. |
| Limits and cleanup | Idle and maximum session times are enforced by the agent. At the end the agent releases held keys, clears the clipboard, and can lock the workstation. |
| Audit | `aegis-rc-data\audit.jsonl` records metadata only: who, what, when and why. It contains no screen content, chat text or command output. |

## Version 0.3.0: production features (phases 2 to 4)

### Agent as a Windows service (recommended on real endpoints)

Run `3-install-agent-service.cmd` **as administrator** on the endpoint (fill in SERVER, TOKEN and PIN first; the trust file must be next to it).

| What it does | Detail |
|---|---|
| Installs the service | `AegisRC` ("Aegis One Remote Control Agent"), LocalSystem, automatic start, restarts itself after a failure |
| Copies the program | `C:\Program Files\AegisRC\aegis-rc-agent.exe` (and `ffmpeg.exe` if it is next to the agent) |
| Protects the config | `C:\ProgramData\AegisRC\agent.json`; the folder is readable only by SYSTEM and Administrators, and the enrollment token is additionally encrypted with DPAPI |
| Enables Ctrl+Alt+Del | Sets the `SoftwareSASGeneration` policy so the service may send Ctrl+Alt+Del |
| Logs | `C:\ProgramData\AegisRC\logs\service.log` and `helper-session<N>.log` |

How it works: the service runs in session 0, which has no desktop, so it launches a helper (the same exe with `helper`) into the active user session with its own SYSTEM token. As SYSTEM inside that session, the helper follows the screen onto the **secure desktop** (UAC prompts, lock and logon screens), can control **elevated windows**, and can send **Ctrl+Alt+Del**. The consent prompt, banner and chat stay on the user's normal desktop. When the user logs off, switches user, or connects over RDP/Enhanced Session, the service moves the helper to the new active session. After a reboot the service starts automatically.

Commands: `aegis-rc-agent.exe service status | start | stop | uninstall` (elevated). `4-uninstall-agent-service.cmd` removes the service and the protected token.

In service mode the command line runs as **SYSTEM**, and the consent prompt tells the user so.

### Smooth video (H.264)

If `ffmpeg.exe` is next to the agent (or on PATH), the agent sends an **H.264 video track** at 25 fps instead of JPEG tiles. The console shows "H.264 video" in the footer. Without FFmpeg, or if the browser cannot decode the video within 6 seconds, the agent uses JPEG tiles automatically. Flags: `-video=false` forces tiles, `-ffmpeg <path>` picks the binary.

Licensing note: FFmpeg with libx264 is GPL. For a shipped product, use the Windows Media Foundation H.264 encoder or a separately downloaded OpenH264 (the encoder sits behind one small interface).

**Capture method:** `-capture dxgi` uses DXGI Desktop Duplication (GPU), which is faster on high-resolution screens. The default is `gdi`. DXGI falls back to GDI automatically on any failure.

### Encrypted recordings on the server

- **Where it is recorded:** the agent records every recorded session on the device and encrypts it before upload (AES-256-GCM). The per-session key is wrapped for the server's recording key (`aegis-rc-data\recording.key`, X25519).
- **What the server stores:** ciphertext only, in `aegis-rc-data\recordings\`. It decrypts only for playback, and only for operators with `remotecontrol.recording.view`.
- **Audit:** every playback, tamper detection and deletion is audited (`recording_viewed`, `recording_tampered`, `recording_deleted`).
- **Retention:** recordings are deleted after the policy's **Keep recordings (days)** (default 30).
- **Playback:** in the console, **Recordings › Encrypted Server Recordings › Play**.

### Database

Server state (operators, policy, audit log, recording index) is in SQLite (`aegis-rc-data\aegis-rc.db`). Existing `operators.json`, `policy.json` and `audit.jsonl` are imported automatically on first start, and `audit.jsonl` keeps being written as an append-only export for a SIEM.

## Version 0.2.0: production hardening (phase 1)

### TURN for machines on different networks

When the console and the device cannot reach each other directly (different sites, NAT, VPN), the media path goes through a TURN relay. Use **coturn** with its TURN REST API (shared secret) mode:

```
# /etc/turnserver.conf (coturn)
listening-port=3478
tls-listening-port=5349
realm=aegis-rc
use-auth-secret
static-auth-secret=<TURN_SHARED_SECRET>
cert=/etc/ssl/turn.pem
pkey=/etc/ssl/turn.key
```

Start the RC server with the same secret in an environment variable (never on the command line, where other users can see it in the process list):

```
set AEGIS_TURN_SECRET=<TURN_SHARED_SECRET>
aegis-rc-server.exe -addr :8443 -data aegis-rc-data -ice stun:turn.example.com:3478 -turn turns:turn.example.com:5349,turn:turn.example.com:3478
```

For every session the server mints a TURN username of the form `<expiry>:<session id>` and its HMAC password, valid for 2 hours by default (`-turn-ttl`). The credentials go to the console in `rc_started` and to the agent **inside the signed `open_rc`**, so a tampered relay path cannot redirect media. No long-lived TURN accounts exist.

### Other changes

| Area | Change |
|---|---|
| Close reasons | Every refusal and session end carries a fixed code (`permission_denied`, `user_declined`, `agent_offline`, `device_busy`, `no_user`, `invalid_command`, `peer_failed`, `operator_ended`, `user_ended`, `idle_timeout`, `max_duration`, `console_disconnected`, `rate_limited`, `internal_error`). |
| Login protection | Five failed console or agent logins from one address within 5 minutes block that address for 10 minutes (`address_blocked` in the audit log). |
| Request rate limit | At most 20 session requests per operator per minute. |
| Keepalive | The server pings every 25 seconds and drops a console or agent that stops answering within 70 seconds. |
| Reconnect | If the network path breaks during a session (Wi-Fi change, VPN reconnect), the agent tries up to three ICE restarts. The session continues without asking the user again; the console shows "Network interrupted · Reconnecting". |
| Logs | Structured logs (`-log-format text` or `json`). Secrets are never written to the log. |
| HTTP | Idle timeout and header size limits on the server. |

## Known prototype limits

- **Foreground mode (`2-start-agent.cmd`) runs in the user session.** UAC prompts, the lock screen and Ctrl+Alt+Del need service mode (`3-install-agent-service.cmd`).
- **Elevated windows need an elevated agent in foreground mode.** Windows blocks input from a normal process into elevated windows (Server Manager, admin PowerShell, UAC). On Windows Server, run `2-start-agent.cmd` with **Run as administrator**.
- **Primary monitor only.**
- **Without FFmpeg the screen is sent as JPEG tiles** (see Smooth video).
- **Two-way chat.** Operator messages open a chat window on the device; the user types a reply and presses Enter. Closing the window only hides it until the next message.
- **Live only.** The console Remote Control page shows only real sessions, real recordings and history rebuilt from the server audit log. Open the console from the file (double-click), not from the server address.
- **Restart is off by default.** It needs `-allow-reboot` on the agent **and** `reboot_allowed` in the server policy.
- **Recording upload needs the server connection.** Chunks recorded while the agent is offline from the server are not kept (no local spool yet).
- **Signing key is stored as a file.** The open_rc signing key sits in `aegis-rc-data\signing.key`. In production it belongs in an HSM or KMS, with key rotation (the agent already accepts several keys in `agent-trust.pub`).
- **Binaries are unsigned.** Windows SmartScreen will warn (**More info › Run anyway**), and some antivirus products flag unsigned remote-control tools.

## Housekeeping

- Delete `FIRST-RUN-SECRETS.txt` after copying the tokens somewhere safe. Tokens are stored only as SHA-256 hashes.
- Keep `aegis-rc-data` private. It holds the TLS key and the signing key.
#   r e m o t e - c o n t r o l - s e r v e r  
 