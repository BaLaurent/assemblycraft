AssemblyCraft 0.14.0 - Windows (64-bit)
=======================================

Jouer / Play
------------
1. Double-click assemblycraft.exe (a console window opens next to the game: it shows the
   "net:" log lines. Do not close it while playing.)
   The exe is not code-signed: Windows SmartScreen may say "Windows protected your PC":
   click "More info" then "Run anyway". Some antivirus programs flag unknown small exes;
   allow it if that happens.
2. Singleplayer: create a world and play. Creative or Survival.
3. Controls: WASD move, Space jump / fly up, Left Shift sneak / fly down, Left Ctrl sprint,
   E inventory, T chat, Tab player list, Esc pause, F3 debug info, F11 fullscreen,
   LMB break/attack, RMB place/use. Everything can be rebound in Settings > Controls.

Multijoueur / Multiplayer (up to 8 players)
-------------------------------------------
HOST (one player): open a world, press Esc, "Open to multiplayer". The game shows a room
code (6 letters), e.g. ABC123. Give it to your friends. If Windows Firewall asks, allow
assemblycraft.exe on "Private" AND "Public" networks (UDP).
GUEST: title screen > Multiplayer, type your name and the room code, Join.
Direct address instead of a code (LAN / VPN / Tailscale): type IP:port, e.g.
192.168.1.20:27615 (the host's game port is 27615).

If a guest cannot connect with the code (strict routers), the game falls back to a relay
server automatically after a few seconds.

Command line (optional):
  assemblycraft.exe --play NAME --host --name Alice [--pvp]     host a world at once
  assemblycraft.exe --join ABC123 --name Bob [--force-relay]    join at once
  assemblycraft.exe --help

Saves are in %APPDATA%\assemblycraft (worlds, settings, multiplayer.cfg).
The game uses OpenGL 1.5+: any graphics driver from the last 15 years is fine.

Third-party: GLFW 3.4 (zlib license) is linked statically; see THIRD-PARTY.txt.
