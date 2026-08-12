#!/usr/bin/env python3
"""Golden tests for Hub protobuf scaling + AES-CCM (Phase 6 CI without hardware)."""

from __future__ import annotations

import json
import struct
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / "VirtualCog" / "Resources" / "Fixtures" / "protocol_golden.json"


def parse_varint(buf: bytes, i: int) -> tuple[int, int]:
    result = 0
    shift = 0
    while True:
        b = buf[i]
        i += 1
        result |= (b & 0x7F) << shift
        if not (b & 0x80):
            return result, i
        shift += 7


def decode_fields(buf: bytes) -> dict[int, int]:
    i = 0
    out: dict[int, int] = {}
    while i < len(buf):
        key, i = parse_varint(buf, i)
        field, wire = key >> 3, key & 7
        if wire == 0:
            val, i = parse_varint(buf, i)
            out[field] = val
        elif wire == 2:
            length, i = parse_varint(buf, i)
            i += length
        else:
            raise AssertionError(f"unsupported wire {wire}")
    return out


class HubGoldenTests(unittest.TestCase):
    def test_makinolo_riding_data(self):
        fixture = json.loads(FIXTURE.read_text())
        packet = bytes.fromhex(fixture["hub_riding_data_hex"])
        self.assertEqual(packet[0], 0x03)
        fields = decode_fields(packet[1:])
        exp = fixture["expected"]
        self.assertEqual(fields[1], exp["power"])
        self.assertEqual(fields[2], exp["cadence"])
        self.assertEqual(fields[3], exp["speed_x100"])
        self.assertEqual(fields[4], exp["hr"])

    def test_simulation_defaults_documented(self):
        fixture = json.loads(FIXTURE.read_text())
        sim = fixture["simulation_defaults"]
        self.assertEqual(sim["cwa"], 5100)
        self.assertEqual(sim["crr"], 400)
        self.assertEqual(sim["wind"], 0)

    def test_gear_table_monotonic(self):
        min_r, max_r = 8000.0, 38000.0
        ratios = [round(min_r + (max_r - min_r) * i / 23.0) for i in range(24)]
        self.assertEqual(len(ratios), 24)
        self.assertEqual(ratios[0], 8000)
        self.assertTrue(all(ratios[i] < ratios[i + 1] for i in range(23)))
        # mid gear ~12 near 2.3–2.5× physical baseline region
        self.assertGreater(ratios[11], 20000)
        self.assertLess(ratios[11], 26000)


class HeartRateGoldenTests(unittest.TestCase):
    def test_measurement_uint8_contact(self):
        fixture = json.loads(FIXTURE.read_text())
        packet = bytes.fromhex(fixture["heart_rate_measurement_hex"])
        flags, bpm = packet[0], packet[1]
        self.assertEqual(bpm, fixture["heart_rate_expected_bpm"])
        self.assertEqual(flags & 0x01, 0)  # uint8 BPM
        self.assertEqual(flags & 0x06, 0x06)  # contact supported + detected


class AESCCMTests(unittest.TestCase):
    def test_round_trip_with_cryptography(self):
        try:
            from cryptography.hazmat.primitives.ciphers.aead import AESCCM
        except Exception as exc:  # pragma: no cover
            self.skipTest(f"cryptography not installed: {exc}")

        key = bytes.fromhex("11" * 32)
        nonce_suffix = bytes.fromhex("aabbccdd")
        counter = (1).to_bytes(4, "little")
        nonce = nonce_suffix + counter
        plaintext = bytes.fromhex("3708001001")
        aesccm = AESCCM(key, tag_length=4)
        ciphertext = aesccm.encrypt(nonce, plaintext, None)
        packet = counter + ciphertext
        opened = aesccm.decrypt(nonce, ciphertext, None)
        self.assertEqual(opened, plaintext)
        self.assertEqual(len(packet), 4 + len(plaintext) + 4)


class FITCRCTests(unittest.TestCase):
    def test_crc16_known(self):
        # Empty payload CRC is 0
        self.assertEqual(fit_crc16(b""), 0)


def fit_crc16(data: bytes) -> int:
    table = [
        0x0000, 0xCC01, 0xD801, 0x1400, 0xF001, 0x3C00, 0x2800, 0xE401,
        0xA001, 0x6C00, 0x7800, 0xB401, 0x5000, 0x9C01, 0x8801, 0x4400,
    ]
    crc = 0
    for byte in data:
        tmp = table[crc & 0xF]
        crc = (crc >> 4) & 0x0FFF
        crc = crc ^ tmp ^ table[byte & 0xF]
        tmp = table[crc & 0xF]
        crc = (crc >> 4) & 0x0FFF
        crc = crc ^ tmp ^ table[(byte >> 4) & 0xF]
    return crc


if __name__ == "__main__":
    # Ensure cryptography is available when possible
    try:
        import cryptography  # noqa: F401
    except ImportError:
        import subprocess

        subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "cryptography"])
    unittest.main()
