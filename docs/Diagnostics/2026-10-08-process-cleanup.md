# Process cleanup investigation — 8 October 2026

Machine: M5 Pro, 24 GB RAM, macOS 26.5.2. Runtime: installed Sikarugir Wine 10.
The installed launcher was 0.6.7; this investigation installed a local 0.6.9 build.

## Measured results

| State | Steam main helper CPU | Global graphics memory in use | Old Wine PID 21629 |
| --- | --- | --- | --- |
| Steam visible, Wukong already closed | about 75% (`ps`, consistent with the reported 60–80%) | 9.80 GB | `?Es`, 19 AGX command queues |
| Steam manually minimized, same flags | 1.3% in two 5-second `top` interval samples | 9.79 GB | Still present |
| Identified Steam bottle processes stopped | No Steam helper remaining | 9.90 GB in the immediate snapshot | Still present, 19 queues |

Graphics values are decimal GB and system-wide. They do not establish how much
memory PID 21629 owns. Later snapshots fluctuate around the same level because
other apps also allocate graphics memory. Swap was 9,100 MiB initially and 8,732 MiB
after shutdown; wired memory remained about 11.4 GiB. Neither metric resets instantly.

A three-second sample of the high-CPU helper repeatedly entered AppKit/QuartzCore
layer/image commit work. Minimizing the window reduced CPU without changing
`--disable-gpu --in-process-gpu`. These flags are injected by the installed runtime,
and were preserved. This is evidence that visible Steam redraw work is avoidable;
it is not a frame-rate measurement of Wukong.

The revised scanner identified 16 processes in the active Steam bottle. After the
live shutdown test, none remained. The older process had lost its executable path,
open-file ownership evidence and normal libproc task information. `KERN_PROC_PID`
still reported its original birth time and exit flag. It was reported separately,
without assigning it to a bottle or sending it signals.

## Changes

- Give Steam its own `-shutdown` request, then use
  `wineboot --end-session --shutdown` for clean Windows session closure, with up to
  15 seconds for each request. Respect a declined session-close request if apps remain.
- Escalate remaining identified processes through the bottle's wineserver,
  SIGTERM, and SIGKILL, checking PID and birth time before signalling.
- Verify ownership with the runtime executable plus exact WINEPREFIX or an open
  file in the bottle. Inspect process files instead of recursively walking a game library.
- Persist verified process identities outside game data. Monitor at five-second
  intervals to retain ownership before descriptors disappear. Use kernel process
  information when ordinary libproc information disappears during exit.
- Show cleanup failures before quitting, and show an older exiting-Wine warning
  when the bottle opens. A driver cleanup stall requires a Mac restart.
- Add optional minimized Steam startup; it is enabled on this Mac. Keep renderer,
  compatibility flags, resolution and game settings unchanged during this investigation.

The clean-session command follows [Wine 10's implementation](https://github.com/wine-mirror/wine/blob/wine-10.0/programs/wineboot/wineboot.c).

## Verification

57 automated tests passed. Additional opt-in testing used two real temporary Wine
prefixes with the installed runtime. Stopping A removed its seven observed
processes while B's five observed processes and its command stayed alive. Cleanup
then stopped B. No temporary Wine processes remained. Tests also cover persisted
ownership after open files disappear, rejecting reused process identities, forced
termination of a stubborn process, and preservation of an unrelated native process.

An unrelated native Steam IPC process also remained untouched. The quit dialog was observed showing PID 21629 and restart instructions, with
Keep Launcher Open and Quit Anyway choices.

Principal Wukong configuration hashes were unchanged through investigation and
shutdown:

- GameUserSettings.ini: `c365b6a77e29bdb2a4cad5635d15c2d5b195029c4f322cdadf0135127bf4e7b2`
- Engine.ini: `6ef10e91bbb6f7f9215185a024383ec05b7339eb3348ac3d1d9cd971cae85f4d`

No saves were edited or deleted.

## Post-restart baseline

The user restarted the Mac; `kern.boottime` confirms 8 October 2026 at 02:03:33
local time. At 02:07:47, before Windows Steam was launched, no Wine/Steam/game
process or Wine AGX client remained. Global graphics memory in use was
278,233,088 bytes (0.28 GB), wired memory was 2,634,317,824 bytes (2.63 GB), and
swap usage was zero. The previous PID 21629 and its 19 queues were gone. This
confirms that restart cleared the observed stalled state; it does not establish
that the launcher changes prevent a future graphics-driver stall.

The installed app is 0.6.9, build 28. Windows Steam was launched through its
Launch Steam button with Start Steam minimized enabled. Steam PID 8140 had
`-silent`; main webhelper PID 8168 retained `--disable-gpu --in-process-gpu`.
After startup settled, three five-second CPU interval samples at 02:09:31,
02:09:36 and 02:09:41 were 1.9%, 2.1% and 2.2%. At 02:09:35, global graphics
memory in use was 0.74 GB and swap remained zero. These samples validate fresh
minimized startup, not just manual minimization of an existing session.

The two principal Wukong configuration hashes still matched the values above
before this new game test. The process ledger had refreshed with current-boot
identities and retained permissions of 0600. No saves or game settings were
edited by the investigation.

Computer Use exposes the native launcher but not the Wine-hosted game windows
on this Mac. The user was asked to launch Wukong with their usual launch option
and leave it at the main menu, so gameplay and a normal in-game exit can be
validated with their cooperation rather than substituting a forced termination.

## First post-restart Wukong launch

The user reported the game launched. Wukong's bootstrap PID 8897 and game PID
8899 started at 02:11:40; EpicWebHelper PID 8940 started at 02:11:53. The game log
at 02:11:50 reported 6,361.55 MB physical memory free, compared with 3,515.98 MB
in the preceding 00:02:24 launch. This is improved launch-time availability, not
proof of frame-time improvement.

At 02:12:16, global graphics memory in use was 3.14 GB, and AGX exposed the new
game client's 19 command queues and EpicWebHelper's four queues. The ledger
recorded both current PID/birth-time identities, so they can be followed through
exit without depending on open files remaining readable.

Steam main helper CPU was 1.2%, 1.2% and 1.4% in five-second intervals at
02:12:49–02:13:00, and 1.1%, 1.2% and 1.1% at 02:14:09–02:14:19. Wineserver
was about 4–6% CPU in these intervals, rather than the reported prolonged 62%.
The game process's `top` memory footprint was about 9,700–9,800 MiB. At 02:14:42,
global graphics memory in use was 3.41 GB, wired memory 5.66 GB, compressor
10.80 GB, and swap usage 2,637 MiB. Memory compression/swap is still substantial
with this game and the other open apps. It must not be conflated with the old
post-exit graphics-driver stall.

Wukong rewrote configuration files during launch; their post-launch hashes differ
from the pre-launch values above. No manual game-configuration or save-file edits
were performed during this validation. There is no automated frame-time
measurement or visible Wine-game UI here.

## First game exit and launcher quit

The user completed a full gameplay test and reported that Wukong ran very well
at full fan speed. This is a positive user-observed result, not an instrumented
FPS claim; no fan controls were changed during this investigation.

The game log recorded `Closing by request` at 02:24:35 and closed at 02:24:45.
By the 02:26:19 snapshot, PIDs 8897, 8899 and 8940 were absent, as were both of
their AGX clients. Global graphics memory in use was 0.81 GB, wired memory 3.04
GB, and compressor 1.39 GB. About 11.30 GB was in the free-page pool. Swap usage
was 5,513 MiB; retained swap after exit is not proof that a process or GPU client
is still alive. The observed stuck-process condition did not recur in this exit.

Steam remained open for the separate exit measurement. Its main helper used
7.0%, 8.1% and 8.9% CPU in the 02:27:18–02:27:28 intervals, higher than the
minimized gaming intervals but still below the previous roughly 75% baseline.
This variation is retained in the results rather than claiming Steam always
runs at 1–2%.

The installed app was then quit using Command-Q with its cleanup-on-quit toggle
enabled. At 02:28:07, no launcher, Wine, Steam or game processes remained and no
Wine AGX clients remained. Global graphics memory in use was 1.11 GB; it is
system-wide and varies with the other open apps. No cleanup-failure alert was
required in this successful quit.

Immediately before and after that shutdown, the following hashes matched:

- GameUserSettings.ini: `18afc35d4d6c507e3f92bcd3384fb65319490959c3aefd43e7d156494ddd8a49`
- Engine.ini: `0bddc1addc83204861bdf924a7969a5f6ee0b3310b4863ea7bbbd995586e5a1f`
- Sorted aggregate of files in the game's SaveGames directory:
  `50202775a83a5e12c8bf17eb0d714a8ce3fe462d66068a05ae8e9a52935bdb8c`

The regular 57-test suite passed again. The opt-in real Wine isolation test
also passed again after reboot: stopping temporary bottle A removed its eight
observed PIDs while bottle B's five observed PIDs and command remained alive.
Temporary bottle B was then cleaned up; the final snapshot contained no Wine
processes. The tests do not modify the real Steam bottle's saves/settings.

## Second launch (repeat check)

The launcher and minimized Steam were reopened with the same bottle, renderer
and display profile. The first-exit configuration hashes still matched after
Steam startup. Wukong was requested through the launcher's Windows-app control
by running the existing Steam executable with `-applaunch 2358720`; temporary
launch arguments were cleared from the field afterward. No game executable,
graphics settings or runtime binary was modified for this test.

The bootstrap PID 11950 started at 02:30:00, game PID 11952 at 02:30:01, and
EpicWebHelper PID 12021 at 02:30:12. The log reported 9,787.30 MB physical memory
free at 02:30:09, back within the earlier healthy 8–9 GB range. At 02:30:28,
global graphics memory in use was 3.79 GB and the two new clients had 19 and
four queues. Both PID/birth-time identities were recorded in the ledger.
The normal-exit repeat check is awaiting the user's in-game Quit action.

## Remaining validation

The first full gameplay test, normal game exit, launcher-quit cleanup, and
cross-bottle isolation have passed. The second normal game exit and final
Stop Steam & Wine check are not yet completed.
The existing kernel-exit/GPU-client state persisted through the initial
investigation; restart subsequently cleared it as measured above.
The changes do not guarantee that the Wine/Metal driver will never stall again.

Next, collect snapshots after the second normal game exit and after Stop Steam
& Wine. No objective frame-time comparison or multi-day soak test has been
performed. Do not attribute all global GPU memory to one process, or promise
that the underlying graphics driver cannot stall again.

`python3 scripts/runtime-diagnostics.py` prints a read-only JSON snapshot. For
interval CPU, use `top -l 4 -s 5 -pid PID -stats pid,cpu,time,mem,threads -n 1`.
