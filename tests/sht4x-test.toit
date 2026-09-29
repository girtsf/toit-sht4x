// Copyright (C) 2026 Girts Folkmanis.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

/**
Tests the driver against $FakeChip, a command-level model of the SHT4x.
*/

import expect show *
import sht4x
import serial.device as serial
import serial.registers as serial

MEASURE-COMMANDS ::= {0xFD, 0xF6, 0xE0, 0x39, 0x32, 0x2F, 0x24, 0x1E, 0x15}

class FakeChip implements serial.Device:
  /** Every command written, oldest first. */
  commands/List := []
  serial-number/int := 0x1234_ABCD
  raw-temperature/int := 0
  raw-humidity/int := 0
  corrupt-next-read/bool := false
  /** The words of the pending response, or null if a read is NACKed. */
  response_/List? := null

  registers -> serial.Registers: throw "UNUSED"

  write bytes/ByteArray -> none:
    expect-equals 1 bytes.size
    command := bytes[0]
    commands.add command
    if command == 0x94:
      response_ = null
    else if command == 0x89:
      response_ = [serial-number >> 16, serial-number & 0xFFFF]
    else if MEASURE-COMMANDS.contains command:
      response_ = [raw-temperature, raw-humidity]
    else:
      throw "fake: unknown command $(%02x command)"

  read amount/int -> ByteArray:
    expect-equals 6 amount
    if not response_: throw "I2C_NACK"
    result := ByteArray 6
    2.repeat: | i/int |
      result[i * 3] = response_[i] >> 8
      result[i * 3 + 1] = response_[i] & 0xFF
      result[i * 3 + 2] = crc8 result[i * 3..i * 3 + 2]
    // Data can only be read once.
    response_ = null
    if corrupt-next-read:
      corrupt-next-read = false
      result[5] ^= 1
    return result

crc8 bytes/ByteArray -> int:
  crc := 0xFF
  bytes.do: | byte/int |
    crc ^= byte
    8.repeat:
      crc = (crc & 0x80) != 0 ? ((crc << 1) ^ 0x31) & 0xFF : (crc << 1) & 0xFF
  return crc

main:
  test-crc
  test-construct
  test-measure
  test-conversion
  test-heat
  test-soft-reset
  test-crc-mismatch

test-crc:
  // The example from the datasheet.
  expect-equals 0x92 (crc8 #[0xBE, 0xEF])

test-construct:
  chip := FakeChip
  sensor := sht4x.Driver chip
  expect-equals [0x94, 0x89] chip.commands
  expect-equals 0x1234_ABCD sensor.serial-number

test-measure:
  chip := FakeChip
  sensor := sht4x.Driver chip
  chip.commands.clear
  chip.raw-temperature = 0x1234
  chip.raw-humidity = 0xABCD
  m := sensor.measure
  expect-equals 0x1234 m.raw-temperature
  expect-equals 0xABCD m.raw-humidity
  sensor.measure --precision=sht4x.PRECISION-HIGH
  sensor.measure --precision=sht4x.PRECISION-MEDIUM
  sensor.measure --precision=sht4x.PRECISION-LOW
  expect-equals [0xFD, 0xFD, 0xF6, 0xE0] chip.commands
  expect-throw "INVALID_ARGUMENT": sensor.measure --precision=3
  expect-throw "INVALID_ARGUMENT": sensor.measure --precision=-1

test-conversion:
  // 26214 is exactly 0.4 * 65535.
  m := sht4x.Measurement --raw-temperature=26214 --raw-humidity=26214
  expect-equals 25.0 m.temperature-c
  expect-equals 44.0 m.humidity-pct
  expect-equals 44.0 m.humidity-pct-uncropped
  expect-equals "25.00C 44.00%RH" m.stringify

  m = sht4x.Measurement --raw-temperature=0 --raw-humidity=0
  expect-equals -45.0 m.temperature-c
  expect-equals 0.0 m.humidity-pct
  expect-equals -6.0 m.humidity-pct-uncropped

  m = sht4x.Measurement --raw-temperature=0xFFFF --raw-humidity=0xFFFF
  expect-equals 130.0 m.temperature-c
  expect-equals 100.0 m.humidity-pct
  expect-equals 119.0 m.humidity-pct-uncropped

test-heat:
  chip := FakeChip
  sensor := sht4x.Driver chip
  chip.commands.clear
  chip.raw-temperature = 0x8000
  duration := Duration.of:
    expect-equals 0x8000 (sensor.heat --power-mw=200).raw-temperature
  expect duration >= (Duration --ms=118)
  sensor.heat --power-mw=110
  sensor.heat --power-mw=20
  expect-equals [0x32, 0x24, 0x15] chip.commands

  chip.commands.clear
  duration = Duration.of: sensor.heat --power-mw=20 --long
  expect duration >= (Duration --ms=1108)
  expect-equals [0x1E] chip.commands

  expect-throw "INVALID_ARGUMENT": sensor.heat --power-mw=100

test-soft-reset:
  chip := FakeChip
  sensor := sht4x.Driver chip
  chip.commands.clear
  sensor.soft-reset
  expect-equals [0x94] chip.commands

test-crc-mismatch:
  chip := FakeChip
  sensor := sht4x.Driver chip
  chip.corrupt-next-read = true
  expect-throw "SHT4x: CRC mismatch": sensor.measure

