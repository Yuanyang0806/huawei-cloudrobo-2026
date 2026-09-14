#!/usr/bin/env python3

import pyrealsense2 as rs

EXPOSURE_LIMIT_US = 8000.0

ctx = rs.context()

devices = []

for dev in ctx.query_devices():
    name = dev.get_info(rs.camera_info.name)

    if "D405" in name:
        devices.append(dev)

if len(devices) != 1:
    raise RuntimeError(
        f"Expected exactly one D405, found {len(devices)}"
    )

dev = devices[0]

name = dev.get_info(rs.camera_info.name)
serial = dev.get_info(rs.camera_info.serial_number)

print(f"[D405] {name}, serial={serial}")

sensor = None

for s in dev.query_sensors():
    if s.supports(rs.option.enable_auto_exposure):
        sensor = s
        break

if sensor is None:
    raise RuntimeError(
        "No D405 sensor supports auto exposure"
    )

sensor_name = sensor.get_info(rs.camera_info.name)
print(f"[D405] sensor={sensor_name}")

# 自动曝光保持开启
sensor.set_option(
    rs.option.enable_auto_exposure,
    1.0
)

# 开启最大曝光限制
if sensor.supports(
    rs.option.auto_exposure_limit_toggle
):
    sensor.set_option(
        rs.option.auto_exposure_limit_toggle,
        1.0
    )

if not sensor.supports(
    rs.option.auto_exposure_limit
):
    raise RuntimeError(
        "auto_exposure_limit unsupported"
    )

sensor.set_option(
    rs.option.auto_exposure_limit,
    EXPOSURE_LIMIT_US
)

# 不限制自动 gain。
# 防止之前测试留下 gain_limit=16。
if sensor.supports(
    rs.option.auto_gain_limit_toggle
):
    sensor.set_option(
        rs.option.auto_gain_limit_toggle,
        0.0
    )

print(
    "[D405] auto_exposure =",
    sensor.get_option(
        rs.option.enable_auto_exposure
    )
)

print(
    "[D405] exposure_limit =",
    sensor.get_option(
        rs.option.auto_exposure_limit
    ),
    "us"
)

if sensor.supports(
    rs.option.auto_gain_limit_toggle
):
    print(
        "[D405] gain_limit_enabled =",
        sensor.get_option(
            rs.option.auto_gain_limit_toggle
        )
    )

print("[D405] configuration OK")
