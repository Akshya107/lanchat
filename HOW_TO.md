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
5. Wait for the green screen. You will see a **room** code, like `K7M2QX`.

That code is the “meeting room” name. Write it down or keep the window open.

To start with your name:

```
lanchat --name Ada
```

---

## 2. Start on the phone

1. Open the **LANCHAT** app.
2. The first time, read **DIRECTIVE 01** and tap **ACCEPT**. Same rules as the computer: you are responsible; the maker is not; private chat only, not illegal activity.
3. Type your **name** (who you are), not the room code.
4. Type the computer’s **room code** in the second box (look for `room=XXXXXX` on the computer).
5. Tap **OPEN LATTICE**.
6. If you already opened the app, type `/room XXXXXX` in the bottom box and tap **SEND**.

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

## 5. Host, private rooms, master key

The first person in a room is the **host**. They can lock the door and kick people.

On the computer (host):

```
/lock
/admit Ada
/kick Ada
```

If the room is private, a phone that joins sees **WAITING OUTSIDE** until the host admits them. Chat is encrypted: the internet relay cannot read it. Only people the host let in can.

**Master key (you):** this app’s owner key lives on your computer at `~/.local/share/lanchat/master.key` (Windows: `%LOCALAPPDATA%\lanchat\master.key`). Any device with that key can take host and lock **any** room:

```
/lock R4LRNS
```

That joins that room, takes host, and makes it private. On the **same Wi‑Fi**, type `/lock` or `/lock lan` — if one other room is nearby, it takes that one. If several rooms are on the LAN, it lists them so you can `/lock CODE`.

On a new phone, paste the key into **MASTER KEY** on the gate, or type `/claim` and paste. Do not send this file to friends.

Friends without the key cannot fake host.

**Spam:** the host auto-kicks people who flood (very fast messages, or the same line over and over). That person / phone cannot join again for **30 seconds**.

**Updates:** when a friend types `lanchat`, if they have internet it pulls the latest GitHub build, then starts. If they are offline, it skips the update and starts as usual. Force skip with `lanchat --no-update`. The phone app does not self-update; send them a new APK when you change it.

---

## What you can type

Just type a message and press Enter (or **SEND** on the phone).

Or type one of these:

| Type this | What happens |
|---|---|
| `/lock` | Make this room private. With the master key, also takes host. |
| `/lock CODE` | Master key: join that room, take host, make it private |
| `/lock lan` | Master key: take the nearby same-Wi‑Fi room and lock it |
| `/open` | Let anyone with the code in. Host only. |
| `/waiting` | List people at the door. Host only. |
| `/admit Ada` | Let that person in. Host only. |
| `/deny Ada` | Send them away. Host only. |
| `/kick Ada` | Remove someone already in. Host only. |
| *(automatic)* | Fast / repeat spam is kicked; they wait 30s to rejoin |
| `/claim KEY` | Paste your master key and take host in this room. |
| `/master` | Says whether this device can auto-take host. Never prints the key. |
| `/host` | Show if you are host, and if the room is open or private. |
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
4. Three windows on one computer each start their **own** room. Copy the first window’s `room=XXXXXX` and type `/room XXXXXX` in the others.
5. Quit and open again if you are stuck. A new room code is created each time — share the new one.

That is all. Same room code → you are in the same chat.