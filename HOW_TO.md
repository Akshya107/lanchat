# How to chat (simple)

This is a private chat that lives only while you are in it. Close it, and the messages are gone. Nothing is saved.

You can use it on a **computer** (green terminal) and on a **phone** (same look). They can talk to each other.

---

## 0. Install once (computer)

Give a friend **only this command**. No zip. No folder.

**Mac / Linux** — open Terminal, paste, press Enter:

```
curl -fsSL https://raw.githubusercontent.com/Akshya107/lanchat/main/get-lanchat.sh | bash
```

**Windows** — open PowerShell, paste, press Enter:

```
irm https://raw.githubusercontent.com/Akshya107/lanchat/main/get-lanchat.ps1 | iex
```

Wait until it says Done. If Python is missing, it installs that too. Then **close the window**, open a new one, and type `lanchat`.

**Uninstall** — Mac / Linux (removes `lanchat` only, not Python):

```
curl -fsSL https://raw.githubusercontent.com/Akshya107/lanchat/main/get-lanchat.sh | bash -s -- --uninstall
```

Windows — delete the folder `%LOCALAPPDATA%\lanchat`.

---

## 1. Start on the computer

1. Open **Terminal** (Mac) or **cmd** (Windows).
2. Type:

```
lanchat
```

3. Press **Enter**.
4. The first time, you will see **DIRECTIVE 01**. Type `ACCEPT` and press Enter. You are responsible for what you send; the maker of the app is not. This is for private chat, not illegal activity. After that, it is remembered on this computer.
5. Wait for the green screen.

To start with your name:

```
lanchat --name Ada
```

---

## 2. Start on the phone

1. Open the **LANCHAT** app.
2. The first time, read **DIRECTIVE 01** and tap **ACCEPT**. Same rules as the computer: you are responsible; the maker is not; private chat only, not illegal activity.
3. Type your **name**.
4. If you are on the **same Wi-Fi** as the computer, leave the room box **blank** and tap **OPEN LATTICE**. You should find each other with no code.
5. If you are on **mobile data** or another network, type the computer’s **room** code, then tap **OPEN LATTICE**.

---

## 3. Same Wi-Fi (usual way)

Open `lanchat` on the computer and the app on the phone. Same Wi-Fi or the same hotspot. **No room code.** They find each other.

If that fails, type `/code` on one device and `/join ABCD-EFGH-12` on the other.

This usually **does not work** with the Android emulator. Use `/room` instead.

---

## 4. Different networks (internet)

If one person is on mobile data or another city, share the **room** code.

On the computer you will see something like `room=K7M2QX`. On the other device type:

```
/room K7M2QX
```

Then just type a message and send it.

- Your messages show on the **left**.
- Their messages show on the **right**.

---

## Updates

When a friend types `lanchat`, if they have internet it pulls the latest GitHub build, then starts. If they are offline, it skips the update and starts as usual. Force skip with `lanchat --no-update`. The phone app does not self-update; send them a new APK when you change it.

---

## What you can type

Just type a message and press Enter (or **SEND** on the phone).

Or type one of these:

| Type this | What happens |
|---|---|
| `/room ABC123` | Meet someone on another network (same code) |
| `/code` | Show your room code and Wi-Fi backup join code |
| `/join ABCD-EFGH-12` | Backup if same-Wi-Fi auto-find fails |
| `/nick Sam` | Change your name |
| `/clear` | Wipe the screen |
| `/help` | Show the list |
| `/quit` | Leave. Messages disappear. |

On the computer you can also press **Ctrl+C** to quit.

---

## First-time install (computer)

Use the one command in **section 0**. That is what you share.

If you are sitting in this project folder on a machine that is not on GitHub yet:

```
./get-lanchat.sh
```

Windows: `powershell -ExecutionPolicy Bypass -File .\get-lanchat.ps1`

---

## Phone app (for developers)

From this project folder:

```
cd mobile
flutter run
```

Pick your phone or the Android emulator.

---

## If they cannot see each other

1. **Same Wi-Fi:** both just open the app. Allow Local Network on iPhone. On Windows use a Private network.
2. If same Wi-Fi still fails, `/code` then `/join` the backup code.
3. **Different network:** both type the same `/room` code. Both need internet.
4. Three windows on one computer still see each other on LAN with no code.
5. Quit and open again if you are stuck.

That is all. Same Wi-Fi → chat. Other network → same room code.
