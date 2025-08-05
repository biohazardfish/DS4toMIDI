# DS4toMIDI 🎮🥁

Use your PS4 controller as a MIDI drum pad on macOS — powered by Swift.

## Features
- Converts button presses into MIDI notes
- Supports analog triggers (L2/R2) with velocity
- Works via Bluetooth or USB
- Compatible with Logic Pro, GarageBand, etc.

## How to Use
1. Connect your PS4 controller via USB or Bluetooth
2. Launch the app (or run via Swift in Terminal)
3. Open Logic Pro and assign MIDI notes to drum sounds

## MIDI Mapping
| Button | MIDI Note | Instrument |
|--------|-----------|------------|
| X      | 36        | Kick       |
| O      | 38        | Snare      |
| △      | 42        | Hi-hat     |
| □      | 46        | Open HH    |
| L2/R2  | Velocity  | Expressive hits |

## License
MIT
