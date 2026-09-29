# sht4x

A Toit driver for the Sensirion
[SHT4x](https://sensirion.com/products/catalog/SHT40) digital relative
humidity and temperature sensors (SHT40, SHT41, SHT43, SHT45).

## Usage

```toit
import i2c
import sht4x

main:
  bus := i2c.Bus --sda=21 --scl=22
  device := bus.device sht4x.I2C-ADDRESS  // I2C-ADDRESS-B/-C for SHT40-BD1x/-CD1x.
  sensor := sht4x.Driver device

  measurement := sensor.measure
  print "$(%.2f measurement.temperature-c)C $(%.1f measurement.humidity-pct)%RH"
```

See [examples/i2c.toit](examples/i2c.toit) for a complete program.

## Features

| Feature                                | API                                  | Command(s)             |
| -------------------------------------- | ------------------------------------ | ---------------------- |
| Measurement, high/medium/low precision | `measure`, `measure --precision=...` | `0xFD`, `0xF6`, `0xE0` |
| Heater pulse (20/110/200mW, 0.1s/1s)   | `heat --power-mw=...`, `--long`      | `0x15`-`0x39`          |
| Serial number                          | `serial-number`                      | `0x89`                 |
| Soft reset                             | `soft-reset`                         | `0x94`                 |

Every word read is CRC-checked. `Measurement` keeps the raw signals and
converts on access: `temperature-c`, `humidity-pct` (cropped to 0..100) and
`humidity-pct-uncropped`.

## Notes

**The constructor soft-resets the sensor** and reads the serial number. That
aborts a measurement or heater pulse left running by a host reset, and throws
if nothing answers at the address.

**Calls block for the maximum duration** from the datasheet (1.6ms, 4.5ms or
8.3ms; heater 0.11s or 1.1s plus 8.3ms). The sensor doesn't stretch the clock
and NACKs a read while busy, so the driver waits rather than polls.

**Heated measurements don't reflect ambient conditions.** The heater has a
maximum duty cycle of 10%, should only be used below 65C ambient, and draws up
to 100mA; a weak supply can brown out the sensor. There's no "heater off"
command: every pulse ends on its own.

**No general call reset.** It is sent to address `0x00` and resets every device
on the bus that honours it, so it belongs to the bus, not this driver.

**No SHT3x/SHT85 support.** Those share the address but use 16-bit commands and
a different humidity formula.

## References

* [SHT4x datasheet](https://sensirion.com/resource/datasheet/sht4x) (v7.3, June 2026)

## AI Disclosure

Robots wrote most of this.
