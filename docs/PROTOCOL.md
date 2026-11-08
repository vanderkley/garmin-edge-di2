# Di2 Bluetooth LE notes

Measured on a Shimano RD-M8250 (12-speed wireless) with an Edge Explore 2.
No bonding and no E-TUBE passkey are needed.

## Services

| Service | UUID |
|---|---|
| Shimano runtime (gear, D-FLY) | `000018ef-5348-494d-414e-4f5f424c4500` |
| Shimano E-TUBE config (not used) | `000018ff-5348-494d-414e-4f5f424c4500` |
| Battery (standard) | `0000180f-0000-1000-8000-00805f9b34fb` |

The suffix `5348494d414e4f5f424c4500` is ASCII for `SHIMANO_BLE`. The derailleur advertises
`18FF` and manufacturer data with company ID `0x044A`. The advertisements carry no gear info.

## Gear: `2AC1` (notify)

A 17-byte packet is sent on every shift:

```
00 00 03 FF FF 05 0C 80 80 80 FC EE 12 FF FF 16 00
               ^^ ^^
               |  number of rear gears (12)
               rear gear (1 = largest cog)
```

Bytes 3/4 are `FF FF` on a 1x system. They are assumed to be the front position and the ring
count on 2x systems, which is not verified yet. 3- and 6-byte packets are also sent and are ignored.

## Battery: `2A19` (read / notify)

One byte, in percent, reported in Shimano steps (100, 90 … 25, 20, 15, 10, 5, 0).

## D-FLY: `2AC2` (indicate)

`[counter, ch1, ch2, ch3, ch4]`. `F0` means the channel is not assigned.
Per channel, the high nibble is the event and the low nibble is a per-channel counter:

| High nibble | Event |
|---|---|
| `1` | short press |
| `2` | long press start |
| `3` | long press, repeating |
| `4` | double press |
| `0` | released |

## Edge firmware quirks

- **31.33**: `registerProfile` with a custom 128-bit UUID returns status 2, and any
  `registerProfile` after that crashes the app. The field registers the Shimano service first
  and stops after a failure.
- **30.22**: works. `CONNECTION_STRATEGY_SECURE_PAIR_BOND` froze the Edge, so the field never bonds.
- `AntPlus.Shifting` is not available to data fields on the Edge Explore 2.
