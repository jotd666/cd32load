cd32load is a program which understands whdload slaves and loads its data from CD32 drive (goodbye OS flashes!!)
As a bonus, it can also run games from OFS/FFS (512 & 1024) formatted IDE hard disks on A600 (2MB chip and even 1MB chip) and A1200.

Some extra plugins (game specific) allow to play CD music on games originally without music / change the music to CD music

There are a lot of bugs & limitations but worth a shot for the ones which work (tested on winuae and on real CD32 & A1200 hardware)

Howto:

- install "cd32load" in C subdir of the CD/HD
- copy your whdload installs in directories: make sure that no file is XPK packed (checked at runtime)
- For CDs: create your CD using ISOCD (commodore) (Windows batch toolchain py Patrik,SysX and me only works well on winuae)
  Other software usually work, but not here, due to the lowlevel CD routine
- For HDs: on a IDE drive, create one partition and format it in OFS or FFS, 512 bytes per block, copy installs there

Features:

- CUSTOMx tooltypes supported, CUSTOM, BUTTONWAIT, PAL, NTSC, NOVBRMOVE, NOCACHE, DATA
- can run multi-disk 1Meg games without flashes (Assassin)
- support for CD audio play while game is running (needs special work for each game) 
- (**) can run some AGA games on a CD32 without (not so many) flashes (Body Blows Galactic, Burning Rubber, Master Axe...)
- (*) tooltypes to redirect joypad buttons (green,blue,yellow,pause,fwd,reverse) to raw keycodes !
  ex: JOY1GREEN=0x40 (or $40) will issue "SPACE" key event when green is pressed
- (*) Mouse emulation with joypad (Earok), see virtual_mouse.txt for more details
- (*) Virtual keyboard (Earok), see virtual_keyboard_doc.txt for more details
- quit by CD32/Amiga reset or using the quitkey on an external keyboard, or mapping the quitkey on a joypad button (dangerous!)
- user friendly error information (Red Screen Of Death) using StingRay's display system
- mapping swap if joystick in port 2 & joypad in port 1 when JOYPAD=1, which allows to play with your favourite joystick
  and benefit from joy2key remapping (pause, space, ...) with the other controller.
- source code included

(*) features not available on a non-expanded A600 (needs 68010+) unless JOYPAD is explicitly set and game is suitable
(**) features not available on a A600/A1200, only from CD

Run it (through your favourite launcher):

example: cd32load assassin.slave CUSTOM1=1 JOY1GREEN=0x40

pressing green CD32 controller will issue rawkey 0x40 (space). Not sure of the usefulness in Assassin...

Basic options:

- SLAVE: mandatory: provide whdload slave to run
- DATA: like whdload, specify game files directory. Caution: if files aren't there, CD32Load can crash/abort
- BUTTONWAIT: if implemented in slave, will wait on title screens, loading screens...
- JOYPAD=0,1,2,3: 0: no remap, 1: remap only on port 0, 2: remap only on port 1, 3: remap both ports (2 player games)
  Important note: if whdload slave has native joypad support, always use JOYPAD=0
- VK: enable virtual keyboard
- VM: enable virtual mouse
- JOYx<color/direction>: assign a raw keycode to a joypad button
- VMMODIFY,VMMODIFYBUT: see virtual mouse doc
- NOVBRMOVE: if game crashes, has strange behaviour with inputs try that (try JOYPAD=0 first!)
- IDEHD: force the use of hard drive even if there's a CD unit (CD0:)
- DISKUNIT: set unit of hard drive / cd. Useful if DH1: is the disk containing games.
- NTSC/PAL: force display either in NTSC or PAL
- CDFREEZE: blocks interrupts when accessing CD/HD. Turn it in case of problem on to see if it fixes the crash/lockup. Needed for
  some games (Pinball Dreams), crashes others (Apano Sin)
- FILECACHE: turns on file caching. Basically can be used with most 512K/1MB games. Not on 2MB games.
  A lot of games work fine and load quickly using FILECACHE on real hardware. On WinUAE it has little effect. Don't get fooled when testing
  your games on WinUAE, a lot of defects cannot be seen. If FILECACHE is accepted by the game, then use it as it almost acts like a RAM loader
  and it reduces the risk of read errors / interrupt / game conflicts.
- CPUCACHE: you might want to see if the game is faster with caches on. From my experience, a lot of games crash with caches on on this particular
  CD32 + chipmem only setup, so I turned it off by default from v0.24

Expert options:

- CD1X: (not supported with IDEHD): sets CD speed to 1x instead of default 2x
- CDBUFFER: adjust CD buffer address. Expert option. Default: 0x1E0000. From v0.15, alignment is not necessary,
  and will be performed at run-time. Means that if game has no free aligned zone, cd32load will swap the leading
  block, perform cd operation and swap back (slower, but at least it gives a chance to the slave!)
- RESLOAD_TOP: install top of resident loader here. If set, also computes CDBUFFER (unless set). Has no effect if system has fastmem
- NOBUFFERCHECK: don't check if CD buffer overlaps memory at startup or during game load: can cause nasty crashes!!
- FORCECHIP: force chipmem to a given size (override slave requirements)
- FORCEEXP: force expmem to a given value (override slave requirements)
- PRETEND: display options & slave info and exit
- TIMEOUT: specify timeout in seconds after which the game will reboot (only on 68010+).
- FREEZEKEY: specify hex raw key code to enter HRTMon if HRTMon is installed. Allows to debug most games on real unexpanded CD32 hardware.
  Ex FREEZEKEY=0x5F
- AUTOREBOOT: reboots after a while when encounters an exception instead of freezing on the CD32Load Red Screen Of Death. If HRTMon is detected,
  the RSOD enters HRTMon and this option is ignored.
- MASKINT6: useful for some games which don't define interrupt 6 handler properly. CD32 console triggers some level 6 interrupts
  that other amigas don't. John Twiddy games are suffering from this lockup bug (well now I have fixed the slaves so won't happen)
- READDELAY: add a delay before reading data from disk. 10000 => 650 ms wait, 2000  => 130 ms wait, approx 0,065 ms per unit.
  Default is 3000 (200ms). It's a safe value. Some games work with 0 (Silkworm). Should not slow loading too much. Fixes some games
  which used to crash earlier. Too early to say, but it's promising.
- RETRYDELAY: number of TOF to wait after a failed read (same units as READDELAY). Default is 3000 (200ms)
- NB_READ_RETRIES: number of retries before red screen of death file read error: default 2 retries
- DEBUG: screen flashes green during READDELAY wait, screen flashes red during RETRYDELAY wait
- FAILSAFE: activates flags which degrade CD32load features but give more chance for programs to work
  equivalent to JOYPAD=0 CDFREEZE CD1X (MASKINT6 isn't included because it can also cause issues)
- USEFASTMEM: enables use of fast memory. This is rather a test option, as if you have fastmem on your console, you're
  likely to have a TF board and a CF card, you don't really need CD32load. But to test if the CD loading is the issue
  this option is very useful, with PRELOAD=disk.1 option to preload even-sized disk images in memory
  
Note: a proper combination of RESLOAD_TOP and CDBUFFER parameters allow to run some AGA slaves
This is possible only from CD, not available from HD (RN routine is the one supporting HD and does not have a
read file offset routine so memory cannot be optimized)
Check "tested_games.txt" file for working settings.

Unimplemented options:

- FILTEROFF: disable filter on startup


About joypad to keyboard redirection:

This mechanism uses VBLANK redirected interrupt to scan joypad(s) and send key events if buttons or/and directions pressed.
This mechanism was reserved to 68010+ machines until CD32load v0.26. Now it is possible to make it work on a 68000
On a 68000, just set explicitly JOYPAD=1,2 or 3 to activate VBL interrupt redirection:
When the slave performs a "cache flush", which happens a lot (loading data, patching...), CD32Load checks if its VBL handler
is installed. If not, it installs it, and backs up the original VBL handler, which is called after CD32Load handler. This allows
to read joypad on each VBL interrupt and makes joypad=>keyboard remap even on a 68000, without modifying the slave!

Also applies to 68010+ machines when NOVBRMOVE has been set to avoid slave crashes (sometimes necessary)

The joypad read routine may conflict with existing slave/game read routine, specially if game/slave supports 2nd button/joypad.

- Default is JOYPAD=2: means port 1 has button redirection to keys.
- JOYPAD=3 turns both joyports on for redirection
- JOYPAD=1 means that only port 0 has button redirection
 (useful when conflicts with game controls. Use JOYPAD=1 JOY0BLUE=0x19 JOY0RED=0x40 to enable P on RMB & spc on LMB on a 1-player game)
- JOYPAD=0 turns it off on both ports (required when slave/game already supports joypad buttons / 2 player mode & control conflicts)

- By default, joypad port 1 mapping is enabled like this:
  * blue => space
  * green => return
  * yellow => left ALT
  * play => P
  * bwd => F1
  * fwd => F2
  * fwd+bwd => ESC
- By default, joypad port 0 mapping is enabled like this:
  * blue => 2
  * green => 1
  * yellow => backspace
  * play => P
  * bwd => F3
  * fwd => F4
  * fwd+bwd => ESC

To disable a given default remapping, just set it to 0: JOY1BLUE=0x00

Note that you can reset the console by pressing all color buttons + play button simultaneously
(avoids knocking off the beer when getting up to press CD32 reset button)

CUSTOMx options:

Hold buttons at CD32Load startup to set CUSTOMx=1 even if not set by command line. Useful on read-only media!!
ATM only value 1 can be set (it is the most useful). Of course, multiple presses enable several CUSTOMx flags

- Blue:    CUSTOM1=1
- Yellow:  CUSTOM2=1
- Green:   CUSTOM3=1
- Reverse: CUSTOM4=1
- Forward: CUSTOM5=1


About data loading:

- I found out that RN loading routine not only supported CD drives but also HD drives!! probably so game developpers
  could test their games out of HDs before burning a zillion CDs (costs time & money, specially back in 1992!!)
- The HD loading is limited to OFS/FFS formatted partitions (no PFS), 512 bytes for sector size, on A600/A1200/A4000 internal IDE interface (no SCSI),
  also has been tested with an IDE CF card and it works!
  (A1200/A4000 Gayle IDE autodetect (that means it could possibly load/write on an A4000 too, but no interest since A4000s have fastmem)
- The CD loading can be done only from a CD32/IDE CD-ROM. If RN loading CD32 games (James Pond, Chuck Rock) work on your CD,
  then it will work on CD32load

Kickemu support & limitations:

- kickstart emulation (A500 ROM) is partially supported. Not a lot of games were tested.
- kickstart emulation (A1200/A4000 ROM) is not supported. Not enough memory for everything anyway (AGA+ A1200 Kick needs > 2MB)
- the resload_LoadKick function is not supported. This happens on early kickemu slaves. A simple slave rewrite/
  conversion to WHDLoad v16 will allow the slave to work (I have done several of those)
- the resload_ExNext function is not supported: directory read won't work in games (but as it is used mainly for saving...)
- Sometimes kickstart emulation won't work on real HW although it is working perfectly on WinUAE, 
  because too slow/reads too many small files: that requires further testing with the new READDELAY default option, could improve a lot
  All 512K kickemu titles using diskimages work well because diskimages can be cached (Marble Madness CD-audio diskimage version is one of those).
  1MB titles cannot use cache.

Bugs/todo (high priority):

- added more info in "red screen of death" about last attempted CD command
- manage to avoid NOVBRMOVE/JOYPAD0 in some games (Rainbow Islands) or add explicit joypad support
  (well, adding joypad support is modifying game slaves directly, not CD32load)
- add option to force joystick type / test fire pressed at game start => forces 2-button joy
- Kickemu does not seem to like IDEHD mode: freezes
- replace IDE/HD code by some other IDE code which is able to read file parts
  (current code only reads whole files, so diskfiles + low memory => you're toast)
- support more WHD games, even if the compatibility rate is now very high

Bugs/todo (low priority):

- add support for CD play in more slaves :)
- Zeewolf seems to crash if the virtual keyboard is used during the game (the password screen is fine). I don't know why
- Some games won't work, either because of the memory layout, or imperfect whdload emulation
- use FastMem when available (would allow to run some memory-needy AGA games from CD, but is that worth now that whdload is free?)
- implement keyrawtable
- support resload_Delta

Contributors:

- JOTD: main source code, bits & pieces integration of all parts & whdload emulation
- Toni Wilen: for WinUAE, keyboard interrupt generation code, help on Akiko interrupts,
  CD routine fix, CD audio replay code, and insight that made this program possible and widely useable. BIG THANKS!!
- Psygore: IDE CD load routine
- Earok: joystick directions remapping, virtual keyboard, virtual mouse
- Wepl & asman & others: ReadJoyPad.s routines to safely read joypad
- Wepl: for the greatest of all: WHDLoad
- WHDLoad team: for writing so many slaves that work with CD32load :)
- StingRay: error report screen
- Patrik & Syx: for their nice ISO-related python scripts
- StatMat: for his ISOCD-Win program, although I was not able to successfully use it, it looks promising
- Rob Northen: IDE hard drive load routine (and previously used CD routine, but Psygore's is better)
- Earok, jayminer, amigajay for extensive support and for testing my program very thouroughfully
- Akira: for setting up googledocs compatibility list
- all members of EAB for their kind replies to my sometimes noob posts (after 25 years owning an Amiga!)
  and for sometimes excellent suggestions



enjoy!
