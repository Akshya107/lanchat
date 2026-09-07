# Ephemeral Chat

Peer-to-peer chat on the same Wi-Fi. Black screen, green text. Messages stay in RAM and the session dies when you quit.

**New here?** Read the simple guide: [HOW_TO.md](HOW_TO.md).

## Share this (no zip)

Mac / Linux — they paste once:

```
curl -fsSL https://raw.githubusercontent.com/Akshya107/lanchat/main/get-lanchat.sh | bash
```

Windows — they paste once:

```
irm https://raw.githubusercontent.com/Akshya107/lanchat/main/get-lanchat.ps1 | iex
```

Then they open a **new** terminal and type `lanchat`. Python is installed only if it is missing.

Uninstall (Mac / Linux):

```
curl -fsSL https://raw.githubusercontent.com/Akshya107/lanchat/main/get-lanchat.sh | bash -s -- --uninstall
```

## After install

Open Terminal (Mac) or **cmd** (Windows), type:

```
lanchat
```

Press **Enter**. The session starts.

Type `/quit` or press **Ctrl+C** to close it. The screen is wiped and you will see `session closed.`

## Install

**Mac** (from this folder):

```bash
chmod +x install.sh
./install.sh
```

**Windows** (from this folder, PowerShell):

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

Then close the window, open a **new** cmd/Terminal, type `lanchat`, press Enter.

Optional name: `lanchat --name Ada`

## Or send one file (no install)

AirDrop `ephemeral-chat.pyz` from the Desktop / this folder.

```bash
python3 ~/Downloads/ephemeral-chat.pyz
```

Windows: `py %USERPROFILE%\Downloads\ephemeral-chat.pyz`

## Inside the session

| Command | What it does |
|---|---|
| `/clear` or `cls` | Wipe history |
| `/mute` | Turn off the ting |
| `/unmute` | Turn the ting back on |
| `/join CODE` | LAN join code or `ip:port` on the same Wi-Fi |
| `/room CODE` | Internet room — phone on mobile data and laptop in another city |
| `/code` | Show your LAN join code and room code |
| `/peers` | List connected peers |
| `/nick NAME` | Change your display name |
| `/quit` or Ctrl+C | Close the session |

Same Wi-Fi. Allow Local Network on macOS. On Windows use a Private network.

## Flutter phone app

Same green terminal, same rooms as `lanchat`.

```bash
cd mobile
flutter pub get
flutter run
```

1. Type an operator name, tap **OPEN UPLINK**.
2. **Wi-Fi / hotspot:** UDP + TCP mesh. Same LAN as the CLI. Share `/code` or `/join XXXX-XXXX-XX`.
3. **Mobile data / different cities:** MQTT room. Both sides type `/room ABCDEF` (same 6-character code). Works on cellular because the app tries WebSocket brokers first (many cell networks block raw MQTT port 1883).

Messages stay in RAM. `/quit` returns to the name screen.

Allow **Local Network** on iOS. On Android, allow nearby devices / location if you want the Wi-Fi IP on the join code.
