# Puppet Fight — Manual

*Amstrad CPC 6128 (128K, disc). REVIVE8BIT – 2026 – VASPER.*

![Title screen](docs/img/title.png)

## The story

The world's leaders have stopped taking questions. In *Puppet Fight* they
settle things the old way: two felt puppets, one stage, ninety-nine seconds.

Trump, Putin, Kim, Xi, Musk and Zelensky step into the ring, each with a
move straight out of the headlines. Win your way past every one of them and
the man who pulls the strings comes out from behind the curtain: the Puppet
Master himself.

## Loading

Insert the disc in drive A and type

    RUN"PUPPET

The title screen appears while the fighters are read from the disc. Press
**fire** (or **SPACE**) to go on to the select screen.

The game needs a CPC 6128 (or a 464/664 with 128K and a disc drive). Leave
the disc in the drive: in a game against the computer, the next opponent is
loaded from it between matches. It reads the disc directly, so it needs a
real disc drive or a floppy emulator such as a Gotek or HxC. M4 boards
can't load the next opponent.

## The select screen

![Select screen](docs/img/select.png)

The menu has a row for each choice, and the two fighters stand above it.

| Row | Choices |
|---|---|
| Player 1 | any fighter |
| Player 2 | any fighter (the same one too: the second gets other colours) |
| Opponent | Human or Computer |
| Difficulty | Easy, Medium or Hard (only when the opponent is the computer) |

The keys:

| Key | |
|---|---|
| **Up** / **Down** | Choose a row (the arrow and the yellow show which) |
| **Left** / **Right** | Change it |
| **Fire** / **SPACE** | Start |

Either player's controls work the menu. When the opponent is the computer,
it plays Player 2's fighter.

## How to fight

![The controls screen](docs/img/howto.png)

After the menu, a screen shows the controls and the moves while the
fighters load from the disc. When it says **FIRE TO FIGHT!**, press fire
to start.

## Controls

| | Player 1 | Player 2 |
|---|---|---|
| Move | Cursor keys or joystick 1 | W A S D or joystick 2 |
| Punch | SPACE or fire 1 | Z or fire 1 |
| Kick | COPY or fire 2 | X or fire 2 |

In the moves, **forward** means towards the opponent and **back** away
from them. Fighters always turn to face each other.

## Moves

| Move | How | |
|---|---|---|
| Walk | Left / right | |
| Jump | Up (up and forward or back to jump that way) | You can jump over your opponent |
| Crouch | Down | |
| Block | Hold back while your opponent attacks | Stops punches, kicks and projectiles |
| Punch | Punch | 4 damage |
| Kick | Kick | 5 damage |
| Back kick | Back + kick | 6 damage |
| Sweep | Down + kick | 4 damage, knocks down |
| Uppercut | Down + punch (or down, then up + punch) | 6 damage, knocks down. Good against jumps |
| Special | Down, down-forward, forward + punch or kick | Each fighter's own (see below) |

Any hit on a fighter in the air knocks them down. A fighter who is knocked
down gets up again after a moment.

## Specials

There are three kinds:

- **Projectiles** fly across the stage. They can be blocked, but a blocked
  one still takes a point of health (never the last). Two projectiles
  that meet cancel each other out. A fighter lying down lets one pass
  over. A fighter can only have one projectile in the air at a time.
- **Strikes** land like a big attack: 10 damage, and a knockdown.
- **Throws** grab an opponent standing close and throw them over to the
  other side: 10 damage and a knockdown. A throw can't be blocked. To
  escape, press back just as the grab lands. Holding back is too late.

## Rounds and matches

![A match](docs/img/fight.png)

Each fighter has a health bar at the top of the screen with their name
over it, player 1 on the left, and the round clock is between them. Every
hit that lands throws up a comic-book burst over whoever took it: POW!,
BAM!, ZAP!, WHAM and the rest. A round ends with a knockout,
or when the clock runs out after 99 seconds. Then the fighter with more
health wins; with the same health, nobody does. The winner of a round gets
a marker under their bar. Two rounds win the match.

Big words across the screen open each round, **BEGIN FIGHT**, and close
it: **K.O.**, **PERFECT** (a knockout without losing any health), **TIME
UP** or **DRAW**. They step aside while a fighter jumps through them.

![The winner](docs/img/victory.png)

## Against the computer: the ladder

Set **Opponent** to **Computer** on the select screen to play against it.
Every time you win a match, the screen goes dark for a few seconds while
the next opponent and their home stage come off the disc. The next opponent is the
next fighter on the list, skipping your own.

Beat all the others and the curtain rises on the **Puppet Master**, who
always fights at his hardest. Beat him and the ladder starts again. If you
lose a match, you face the same opponent again.

If the border turns red while the next opponent loads, the disc couldn't
be read. The game keeps trying, so check that the disc is in drive A.

![The Puppet Master](docs/img/boss.png)

With two players, each match is followed by a rematch.

## The fighters

| Fighter | Title | Special | Home stage |
|---|---|---|---|
| Donald Trump | The Greatest American 2.0 | Tweet Storm: a tweet bird (projectile) | The White House |
| Vladimir Putin | Tsar of All the Puppets | Judo Throw (throw) | The Kremlin |
| Kim Jong-Un | Supremest Leader | Surf's Up Missile (projectile) | Pyongyang |
| Xi Jinping | President Emperor | Belt and Road: a long-reaching belt (strike) | Beijing |
| Elon Musk | Tech Support | Chainsaw Rampage (strike) | Starbase |
| Volodymyr Zelensky | Humble President | More Ammo!: a supply crate (projectile, slow and heavy) | Kyiv |
| Ian Bremmer | The Puppet Master | G-Zero World: a globe (projectile, the heaviest) | The puppet theatre |

The Puppet Master can't be chosen on the select screen: you have to earn
the fight.

![The Puppet Master wins](docs/img/boss_win.png)

## About

Puppet Fight is a non-commercial fan project in the spirit of *Puppet
Regime*, GZERO Media's satirical puppet show, which inspired the cast. It
is kept to the show's affectionate, absurd register: slapstick, no real
violence.

Written in Z80 assembly for the Amstrad CPC 6128. The fight runs at a
locked 25 frames a second on a full overscan screen (192 × 272 Mode 0
pixels). The puppets were built and posed in Blender and turned into
Mode 0 sprites, then compiled to Z80 code while you play.
