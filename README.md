# Breathwork for Omarchy

A personal, customizable guided-breathing plugin for the Omarchy shell. It is
based on [Zen for Omarchy](https://github.com/ya-luotao/omarchy-zen) and keeps
the original MIT license.

The plugin provides a fullscreen visual breathing pacer, a bar widget, session
history, a daily streak, optional bells, and optional do-not-disturb mode.
Every inhale, hold, and exhale can begin with a short audio cue.
Every session also begins with a configurable **Get ready** countdown.

The session visual can be changed in **Protocol settings**. Choose the classic
expanding **Orb**, layered **Pulse rings**, or a vertical **Breath bar**. The
choice is saved and applies to every breathing protocol.

## Protocols

| Key | Protocol | Rhythm |
|---|---|---|
| `box` | Box breathing | in 4 · hold 4 · out 4 · hold 4 |
| `478` | 4-7-8 | in 4 · hold 7 · out 8 |
| `coherent` | Coherent | in 5.5 · out 5.5 |
| `equal` | Equal breathing | in 4 · out 4 |
| `extended` | Extended exhale | in 4 · out 6 |
| `triangle` | Triangle breathing | in 4 · hold 4 · out 4 |
| `power` | Power Breathe | configurable rounds and breaths · manual exhale retention · increasing recovery hold |
| `custom` | Personal rhythm | configurable inhale, holds, and exhale |

Session choices in the panel are 3, 5, 10, 15, 20, and 30 minutes.
Power Breathe is round-based, so it uses rounds instead of the selected session
duration. Its dedicated settings editor lets you choose 1–20 rounds,
30–40 breaths per round, a 2–5 second breath pace, the first recovery hold,
and how many seconds that hold gains each round. The defaults produce recovery
holds of 10, 15, and 20 seconds. During each exhale retention, press **Space** or **Enter**
(or choose **Take recovery breath**) when the natural urge to breathe returns.

## Power Breathe safety

Power Breathe follows the basic sequence described by the official Wim Hof
Method: 30 deep breaths, retention after the final exhale, one full recovery
breath held briefly, then another round. The recovery hold starts at 10 seconds
and increases by 5 seconds per round by default. Always practice seated or
lying down in a safe place. Never practice while driving, standing, in water,
in the shower, or anywhere a loss of consciousness could cause injury. Do not
force the retention; continue when you feel the urge to breathe.

Official instructions: <https://www.wimhofmethod.com/breathing-exercises>

## Named personal protocols

Open the bar widget and choose **Protocol settings**, or right-click the bar
icon to open the settings panel directly. It lets you:

- start a new protocol from the timing of the currently selected protocol;
- give it a name;
- set inhale, hold-after-inhale, exhale, and hold-after-exhale durations;
- save it and select it as the default;
- reopen a saved protocol to rename it or change its timing;
- delete a saved protocol with a two-step confirmation.

Named protocols are stored in
`~/.local/state/omarchy/breathwork/protocols.json`. Built-in protocols remain
unchanged and can be used as templates for personal versions.

## Enable

```bash
omarchy plugin enable oma.breathwork
```

The plugin files live in `~/.config/omarchy/plugins/oma.breathwork/`.
Practice history is stored at
`~/.local/state/omarchy/breathwork/stats.json`.

## Custom rhythm

The default custom rhythm is 4 seconds in, 2 seconds held, 6 seconds out, and
no hold after the exhale. Change it with:

```bash
omarchy bar set oma.breathwork customIn 4
omarchy bar set oma.breathwork customHoldIn 2
omarchy bar set oma.breathwork customOut 6
omarchy bar set oma.breathwork customHoldOut 0
omarchy bar set oma.breathwork pattern custom
```

Each phase accepts 0–30 seconds, except inhale and exhale, which require at
least 1 second.

## Other settings

```bash
omarchy bar set oma.breathwork minutes 10
omarchy bar set oma.breathwork getReadySeconds 5
omarchy bar set oma.breathwork visualStyle rings
omarchy bar set oma.breathwork powerRounds 3
omarchy bar set oma.breathwork powerBreaths 30
omarchy bar set oma.breathwork powerBreathSeconds 3
omarchy bar set oma.breathwork powerRecoveryHold 10
omarchy bar set oma.breathwork powerRecoveryIncrease 5
omarchy bar set oma.breathwork bell false
omarchy bar set oma.breathwork phaseCues false
omarchy bar set oma.breathwork dnd false
```

Phase cues are enabled by default and can also be changed in **Protocol
settings**. With a countdown, the session bell marks **Get ready** and the
first inhale receives the ordinary phase cue. With no countdown, the session
bell serves as the first inhale cue so two sounds do not overlap.

The get-ready countdown is also configured in **Protocol settings**, applies
to every protocol, and accepts 0–30 seconds. It runs before practice timing
starts, so it does not reduce the selected session length.

## Commands

```bash
omarchy-shell oma.breathwork start extended 5
omarchy-shell oma.breathwork start power 5
omarchy-shell oma.breathwork status
omarchy-shell oma.breathwork settings
omarchy-shell shell summon oma.breathwork '{"pattern":"custom","minutes":5,"customIn":4,"customHoldIn":2,"customOut":6,"customHoldOut":0}'
```

## Keybinding

Add this to `~/.config/hypr/bindings.lua` if you want a direct shortcut:

```lua
o.bind("SUPER + SHIFT + B", "Breathwork",
  [[omarchy-shell shell summon oma.breathwork '{"pattern": "custom", "minutes": 10}']])
```

## License

MIT. Based on Zen for Omarchy by Luo Tao.
