// Copyright (C) 2026 Girts Folkmanis.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import io
import serial.device as serial

/** The I2C address of the SHT40-AD1x, SHT41, SHT43 and SHT45. */
I2C-ADDRESS ::= 0x44
/** The I2C address of the SHT40-BD1x. */
I2C-ADDRESS-B ::= 0x45
/** The I2C address of the SHT40-CD1x. */
I2C-ADDRESS-C ::= 0x46

/** Low precision (repeatability): 1.6ms, the least energy. See $Driver.measure. */
PRECISION-LOW ::= 0
/** Medium precision (repeatability): 4.5ms. See $Driver.measure. */
PRECISION-MEDIUM ::= 1
/** High precision (repeatability): 8.3ms, the least noise. See $Driver.measure. */
PRECISION-HIGH ::= 2

/**
A single measurement of the sensor.
*/
class Measurement:
  /** The raw temperature signal, a 16-bit unsigned integer. */
  raw-temperature/int
  /** The raw humidity signal, a 16-bit unsigned integer. */
  raw-humidity/int

  constructor --.raw-temperature --.raw-humidity:

  /** The temperature, in degrees Celsius. */
  temperature-c -> float:
    return -45.0 + 175.0 * raw-temperature / 65535.0

  /**
  The relative humidity, in percent, cropped to 0..100.

  See $humidity-pct-uncropped for the value before cropping.
  */
  humidity-pct -> float:
    return max 0.0 (min 100.0 humidity-pct-uncropped)

  /**
  The relative humidity, in percent, as the conversion formula yields it.

  The formula can yield values from -6 to 119, and values outside 0..100 are
    not physical. They may still be useful, for example to study the
    distribution of sensors near the ends of the range. Most users want
    $humidity-pct.
  */
  humidity-pct-uncropped -> float:
    return -6.0 + 125.0 * raw-humidity / 65535.0

  stringify -> string:
    return "$(%.2f temperature-c)C $(%.2f humidity-pct)%RH"

/**
Driver for an SHT4x sensor.

The sensor has no configuration. Every command is a single measurement, with
  or without heating, after which the sensor returns to idle.

The driver does not own the device it is given, and closing that device is the
  caller's job.
*/
class Driver:
  static CMD-MEASURE-HIGH_ ::= 0xFD
  static CMD-MEASURE-MEDIUM_ ::= 0xF6
  static CMD-MEASURE-LOW_ ::= 0xE0
  static CMD-SERIAL-NUMBER_ ::= 0x89
  static CMD-SOFT-RESET_ ::= 0x94
  static CMD-HEATER-200MW-1S_ ::= 0x39
  static CMD-HEATER-200MW-100MS_ ::= 0x32
  static CMD-HEATER-110MW-1S_ ::= 0x2F
  static CMD-HEATER-110MW-100MS_ ::= 0x24
  static CMD-HEATER-20MW-1S_ ::= 0x1E
  static CMD-HEATER-20MW-100MS_ ::= 0x15

  // Maximum durations from the datasheet, indexed by the PRECISION-* constants.
  static MEASURE-COMMANDS_ ::= [CMD-MEASURE-LOW_, CMD-MEASURE-MEDIUM_, CMD-MEASURE-HIGH_]
  static MEASURE-US_ ::= [1_600, 4_500, 8_300]

  static HEATER-LONG-US_ ::= 1_100_000
  static HEATER-SHORT-US_ ::= 110_000
  static RESET-US_ ::= 1_000
  // Not in the datasheet. Sensirion's own driver waits 10ms.
  static SERIAL-NUMBER-US_ ::= 10_000

  device_/serial.Device
  serial-number_/int := 0

  /**
  Constructs a driver for the SHT4x on the given device.

  Soft-resets the sensor, which aborts a measurement or heater pulse that may
    still be running from before a host reset, and reads the serial number.

  Throws if the sensor does not answer, or answers with a bad checksum.
  */
  constructor .device_:
    soft-reset
    serial-number_ = read-serial-number_

  /**
  The 32-bit unique serial number.

  Sensirion's calibration certificates, as for the SHT43, are identified by it.
  */
  serial-number -> int:
    return serial-number_

  /**
  Measures temperature and humidity once.

  The $precision is one of $PRECISION-HIGH (the default), $PRECISION-MEDIUM,
    or $PRECISION-LOW. Lower precision means more noise, but a shorter
    measurement and less energy.
  */
  measure --precision/int=PRECISION-HIGH -> Measurement:
    if not (PRECISION-LOW <= precision <= PRECISION-HIGH):
      throw "INVALID_ARGUMENT"
    return command-and-read_ MEASURE-COMMANDS_[precision] MEASURE-US_[precision]

  /**
  Heats the sensor, then measures temperature and humidity once.

  The heater runs with $power-mw milliwatts, which is one of 20, 110 or 200,
    for 1s if $long is true, and for 0.1s otherwise. At the end of the pulse the
    sensor takes a high-precision measurement, still heating, and turns the
    heater off. The call blocks for the whole pulse.

  The measurement is taken while heating and does not reflect the ambient
    conditions; the sensor specifications are not valid during heating.

  Heating removes condensed water from the sensor, and periodic pulses prevent
    creep at high humidity. The heater must not be on more than 10% of the time,
    only be used below 65C ambient temperature, and draws up to 100mA. There is
    no command to keep it on; for longer heating, call this repeatedly without
    pausing.
  */
  heat --power-mw/int --long/bool=false -> Measurement:
    command/int := ?
    if power-mw == 200:
      command = long ? CMD-HEATER-200MW-1S_ : CMD-HEATER-200MW-100MS_
    else if power-mw == 110:
      command = long ? CMD-HEATER-110MW-1S_ : CMD-HEATER-110MW-100MS_
    else if power-mw == 20:
      command = long ? CMD-HEATER-20MW-1S_ : CMD-HEATER-20MW-100MS_
    else:
      throw "INVALID_ARGUMENT"
    heater-us := long ? HEATER-LONG-US_ : HEATER-SHORT-US_
    return command-and-read_ command (heater-us + MEASURE-US_[PRECISION-HIGH])

  /**
  Soft-resets the sensor.

  Aborts any running measurement or heater pulse. Takes 1ms.
  */
  soft-reset -> none:
    device_.write #[CMD-SOFT-RESET_]
    sleep (Duration --us=RESET-US_)

  command-and-read_ command/int delay-us/int -> Measurement:
    device_.write #[command]
    sleep (Duration --us=delay-us)
    words := read-words_
    return Measurement --raw-temperature=words[0] --raw-humidity=words[1]

  read-serial-number_ -> int:
    device_.write #[CMD-SERIAL-NUMBER_]
    sleep (Duration --us=SERIAL-NUMBER-US_)
    words := read-words_
    return (words[0] << 16) | words[1]

  /**
  Reads two 16-bit words, each followed by a CRC byte.

  The sensor does not stretch the clock, and NACKs the read if it is still
    busy.
  */
  read-words_ -> List:
    bytes := device_.read 6
    return List 2: | i/int |
      offset := i * 3
      if bytes[offset + 2] != (crc8_ bytes[offset..offset + 2]):
        throw "SHT4x: CRC mismatch"
      io.BIG-ENDIAN.uint16 bytes offset

/** Computes the Sensirion CRC-8: polynomial 0x31, initialization 0xFF. */
crc8_ bytes/ByteArray -> int:
  crc := 0xFF
  bytes.do: | byte/int |
    crc ^= byte
    8.repeat:
      crc = (crc & 0x80) != 0 ? ((crc << 1) ^ 0x31) & 0xFF : (crc << 1) & 0xFF
  return crc
