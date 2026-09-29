// Copyright (C) 2026 Girts Folkmanis.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

/**
Reads an SHT4x at every precision, then with a short heater pulse.
*/

import i2c
import sht4x

main:
  bus := i2c.Bus --sda=21 --scl=22
  device := bus.device sht4x.I2C-ADDRESS
  sensor := sht4x.Driver device
  print "Serial: $(%08x sensor.serial-number)"

  print "High:   $sensor.measure"
  print "Medium: $(sensor.measure --precision=sht4x.PRECISION-MEDIUM)"
  print "Low:    $(sensor.measure --precision=sht4x.PRECISION-LOW)"

  // The measurement is taken while heating, so it reads warm and dry.
  print "Heated: $(sensor.heat --power-mw=20)"
  // Wait at least 10 times the pulse before the next one.
  sleep --ms=1_000
  print "After:  $sensor.measure"

  device.close
  bus.close
