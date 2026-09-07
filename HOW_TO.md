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
4. Wait for the green screen. You will see a **room** code, like `K7M2QX`.

That code is the “meeting room” name. Write it down or keep the window open.

To start with your name:

```
lanchat --name Ada
```

---

## 2. Start on the phone

1. Open the **LANCHAT** app.
2. Type your name (or leave it blank).
3. Tap **OPEN UPLINK**.
4. Wait for the hello screen. You will also see a **room** code.

---

## 3. Put both in the same room (this is the usual way)

The computer and the phone each pick their own room when they start. **They will not see each other until both use the same code.**

**Easy method:** copy the phone’s room code.

On the computer, type:

```
/room K7M2QX
```

Use *your* real code, not this example. Press Enter.

Or do it the other way: copy the computer’s code, and on the phone type `/room` plus that code.

When it works you will see something like “internet on”. Then just type a normal message and send it.

- Your messages show on the **left**.
- Their messages show on the **right**.

This works if both have internet — Wi‑Fi, mobile data, even different cities.

---

## 4. Same Wi‑Fi only (no internet)

If the laptop and a **real phone** are on the same Wi‑Fi or the same hotspot:

- They often find each other by themselves.
- If not, type `/code` on one device. You get a join code like `ABCD-EFGH-12`.
- On the other device type `/join ABCD-EFGH-12`.

This usually **does not work** with the Android emulator. Use `/room` instead.

---

## What you can type

Just type a message and press Enter (or **SEND** on the phone).

Or type one of these:

| Type this | What happens |
|---|---|
| `/room ABC123` | Join that meeting room (both people use the same code) |
| `/code` | Show your room code and Wi‑Fi join code again |
| `/join ABCD-EFGH-12` | Join someone on the same Wi‑Fi |
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

1. Both must type the **same** `/room` code. Spelling matters.
2. Both need internet for `/room`.
3. On a real iPhone, allow **Local Network** if you want same-Wi‑Fi join.
4. Quit and open again if you are stuck. A new room code is created each time — share the new one.

That is all. Same room code → you are in the same chat.