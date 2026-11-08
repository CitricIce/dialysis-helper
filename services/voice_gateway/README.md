# Development voice gateway

This small Python service keeps the Cartesia API key on a trusted computer/server.
It supports generated routine speech and streaming, dynamic questions through an
existing Cartesia Managed Agent. TTS credits alone do not establish agent access;
configure/publish an agent and verify availability in your Cartesia account.
No Cartesia API request was made during implementation.

For a phone prototype, run it on the development Mac on the same trusted network.
Camera, depth, risk, BLE and immediate speech warnings still run on the phone.
For independent use later, deploy an authenticated gateway behind HTTPS; this
stdlib development server is not a production hosting solution.

## Configure locally

1. Create/publish a dedicated practice assistant in Cartesia and obtain its agent
   ID and an appropriate voice ID. Do not attach tools that alter the routine or
   call external services. The server supplies trusted per-session instructions
   and the current check from the bundled template; the app rejects client-tool
   requests. Prompts cannot guarantee clinically correct generated answers.
2. Set these environment variables on the server (never in the app or Git):

```sh
export CARTESIA_API_KEY="your-key"
export CARTESIA_VOICE_ID="your-voice-id"
export CARTESIA_AGENT_ID="your-published-agent-id"
export ARMGUARD_GATEWAY_TOKEN="a-separate-random-token-at-least-24-characters"
```

Generate a separate gateway token, for example with
`python3 -c 'import secrets; print(secrets.token_urlsafe(32))'`. Keep it private.
The Cartesia API key never belongs in the phone's gateway-token field.

3. Run from the repository root:

```sh
python3 services/voice_gateway/server.py
```

The default bind is loopback only. To reach it from the physical phone, explicitly
set `ARMGUARD_GATEWAY_HOST` to the Mac's LAN address (or `0.0.0.0` on a trusted
private development network), then restart. Find the Mac's LocalHostName with
`scutil --get LocalHostName`. Enter `http://that-name.local:8765` in the app, with
the separate gateway token. Both devices must be on the same reachable network;
allow the development server through the Mac firewall if needed. This `.local`
HTTP route is unencrypted and for practice data on a trusted LAN only. Use HTTPS
for deployed access; the app permits HTTPS and local `.local` HTTP, with no
blanket App Transport Security bypass. `localhost` on a phone is the phone.

4. Enable **Allow cloud voice questions**, then Ask a question. Microphone audio
   streams directly from the phone to Cartesia over WSS using a short-lived,
   single-use session token. The gateway only creates the session. End Q&A to
   return to the current check. A separate toggle enables generated Cartesia
   routine prompts; immediate risk/loss warnings always use local speech.

The service refuses unauthenticated requests, limits body/response size,
serializes upstream requests and limits requests to 20 per minute. It suppresses
request and provider-error logging. It does not provision accounts, verify billing,
manage agent versions or erase Cartesia call records. Configure provider retention
and review generated content before any patient-data use. A gateway token entered
on the phone is stored only in memory; this is a one-device development setup.

## Interfaces

- `POST /speak`, Bearer gateway token, JSON `{"text":"..."}` → WAV bytes.
- `POST /agent-session`, same authentication, JSON `{"check_id":"hands"}` →
  server-created WebSocket URL + one-use token. The server looks up the check;
  arbitrary app instructions or prescription fields are not accepted.

The integration follows Cartesia's [TTS bytes API](https://docs.cartesia.ai/api-reference/tts/bytes)
and [Managed Agent WebSocket protocol](https://docs.cartesia.ai/line/integrations/websocket-api).
It uses API version `2026-08-14`, `sonic-3.6` TTS and 16 kHz mono PCM16 agent audio
in 40 ms input chunks. Playback handles barge-in clears and bounds queued audio;
network backlog ends the conversation instead of accumulating delayed speech.
The native app gives the agent no path to mutate `RoutineSession`.

Run local tests without keys, network access or paid requests:

```sh
python3 -m unittest discover -s services/voice_gateway -v
```

Tests exercise real HTTP request parsing against in-memory sockets and mock only
the upstream Cartesia call. They cover auth, size checks, trusted check context,
TTS schema, session destination validation and sanitized failures. A live phone
and published agent are still needed to validate audio formats, session creation,
speaker echo suppression, barge-in, permissions and network recovery.
