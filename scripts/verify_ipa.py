"""Fail CI if the package is incomplete or is not an arm64 iOS app."""
import plistlib
import struct
import sys
import zipfile

with zipfile.ZipFile(sys.argv[1]) as archive:
    assert archive.testzip() is None, 'Corrupted ZIP'
    prefix = 'Payload/Wellbeing.app/'
    info = plistlib.loads(archive.read(prefix + 'Info.plist'))
    assert info['CFBundleIdentifier'] == 'com.leboxis.wellbeingtracker'
    assert info['CFBundleSupportedPlatforms'] == ['iPhoneOS']
    assert info['MinimumOSVersion'] == '17.0'
    executable = archive.read(prefix + info['CFBundleExecutable'])
    magic, cpu = struct.unpack('<II', executable[:8])
    assert magic == 0xfeedfacf and cpu == 0x0100000c, 'Expected arm64 Mach-O'
    assert prefix + 'Assets.car' in archive.namelist(), 'Missing assets'
    print(f"Validated: {info['CFBundleIdentifier']} {info['CFBundleShortVersionString']} (arm64, iOS 17+)")
