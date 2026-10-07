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

## Remaining validation

Wukong launch/exit cycles and a gameplay stutter comparison are **not completed**.
The existing kernel-exit/GPU-client state persisted through the initial
investigation; restart subsequently cleared it as measured above.
The changes do not guarantee that the Wine/Metal driver will never stall again.

The before-Steam and minimized-Steam baselines are now collected. Next, collect
snapshots at the Wukong menu, after normal game exit, and after Stop Steam & Wine. Repeat two game
cycles using the same save, settings, and gameplay scene. Compare remaining PIDs,
AGX clients, global graphics memory, wired/compressed memory, swap and game frame
times. Do not attribute all global GPU memory to one process.

`python3 scripts/runtime-diagnostics.py` prints a read-only JSON snapshot. For
interval CPU, use `top -l 4 -s 5 -pid PID -stats pid,cpu,time,mem,threads -n 1`.
