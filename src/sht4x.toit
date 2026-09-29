// Copyright (C) 2026 Girts Folkmanis.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import .driver
export *

/**
Driver for the Sensirion SHT4x digital relative humidity and temperature
  sensors.

The family consists of the SHT40, SHT41, SHT43 and SHT45, which differ in
  accuracy but share one interface. Most variants use $I2C-ADDRESS; the
  SHT40-BD1x uses $I2C-ADDRESS-B and the SHT40-CD1x $I2C-ADDRESS-C.

The sensor has no configuration and no continuous mode. Each command is one
  measurement:
- $Driver.measure measures temperature and humidity, in 1.6ms to 8.3ms
  depending on the precision.
- $Driver.heat runs the on-chip heater for 0.1s or 1s, then measures. Use it
  to remove condensed water, or to prevent creep at high humidity. Mind the 10%
  duty cycle.

Between commands the sensor idles at about 80nA, so there is no sleep mode.

The returned $Measurement converts the raw signals; its humidity is cropped to
  0..100%RH, as the datasheet advises.

# Examples
```
import i2c
import sht4x

main:
  bus := i2c.Bus --sda=21 --scl=22
  device := bus.device sht4x.I2C-ADDRESS
  sensor := sht4x.Driver device
  measurement := sensor.measure
  print "$(%.2f measurement.temperature-c)C, $(%.1f measurement.humidity-pct)%RH"
```
*/
