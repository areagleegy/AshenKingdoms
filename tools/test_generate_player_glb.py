from __future__ import annotations

import json
import struct
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from tools import generate_player_glb


JSON_CHUNK = generate_player_glb.GLB_JSON_CHUNK_TYPE
BIN_CHUNK = generate_player_glb.GLB_BIN_CHUNK_TYPE


def make_glb(
    document: object | None = None,
    chunks: list[tuple[int, bytes]] | None = None,
    version: int = 2,
    declared_size_delta: int = 0,
) -> bytes:
    if chunks is None:
        if document is None:
            document = {"asset": {"version": "2.0"}}
        json_chunk = json.dumps(document, separators=(",", ":")).encode("utf-8")
        json_chunk += b" " * ((-len(json_chunk)) % 4)
        chunks = [(JSON_CHUNK, json_chunk)]
    body = b"".join(struct.pack("<II", len(payload), kind) + payload for kind, payload in chunks)
    declared_size = 12 + len(body) + declared_size_delta
    return struct.pack("<4sII", b"glTF", version, declared_size) + body


class FakeResponse:
    def __init__(self, body: bytes, final_url: str = "https://cdn.example.invalid/model.glb"):
        self._body = body
        self._offset = 0
        self._final_url = final_url

    def __enter__(self) -> "FakeResponse":
        return self

    def __exit__(self, *_args: object) -> None:
        return None

    def geturl(self) -> str:
        return self._final_url

    def read(self, size: int = -1) -> bytes:
        if size < 0:
            size = len(self._body) - self._offset
        end = min(len(self._body), self._offset + size)
        chunk = self._body[self._offset:end]
        self._offset = end
        return chunk


class GeneratePlayerGlbTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp_dir = tempfile.TemporaryDirectory()
        self.root = Path(self.temp_dir.name)

    def tearDown(self) -> None:
        self.temp_dir.cleanup()

    def validate_bytes(self, content: bytes) -> None:
        path = self.root / "fixture.glb"
        path.write_bytes(content)
        generate_player_glb._validate_glb_container(path)

    def test_accepts_minimal_structurally_valid_glb_2(self) -> None:
        self.validate_bytes(make_glb())

    def test_accepts_json_and_one_binary_chunk(self) -> None:
        self.validate_bytes(make_glb(chunks=[
            (JSON_CHUNK, b'{"asset":{"version":"2.0"}}    '),
            (BIN_CHUNK, b"\\x00\\x00\\x00\\x00"),
        ]))

    def test_rejects_bad_magic(self) -> None:
        content = bytearray(make_glb())
        content[0:4] = b"NOPE"
        path = self.root / "bad.glb"
        path.write_bytes(content)
        with self.assertRaises(generate_player_glb.MeshyError):
            generate_player_glb._validate_glb_container(path)

    def test_rejects_non_v2_glb(self) -> None:
        self.validate_rejects(make_glb(version=1))

    def test_rejects_declared_file_size_mismatch(self) -> None:
        self.validate_rejects(make_glb(declared_size_delta=4))

    def test_rejects_truncated_chunk_header(self) -> None:
        content = make_glb(chunks=[(JSON_CHUNK, b'{"asset":{"version":"2.0"}}    ')])
        content += b"\\x00\\x00\\x00\\x00"
        content = bytearray(content)
        struct.pack_into("<I", content, 8, len(content))
        path = self.root / "truncated-chunk-header.glb"
        path.write_bytes(content)
        with self.assertRaises(generate_player_glb.MeshyError):
            generate_player_glb._validate_glb_container(path)

    def test_rejects_chunk_outside_container(self) -> None:
        # The archive declares a JSON chunk larger than the container payload.
        content = struct.pack("<4sII", b"glTF", 2, 20) + struct.pack("<II", 4, JSON_CHUNK)
        path = self.root / "chunk-outside.glb"
        path.write_bytes(content)
        with self.assertRaises(generate_player_glb.MeshyError):
            generate_player_glb._validate_glb_container(path)

    def test_rejects_unaligned_chunk_length(self) -> None:
        content = struct.pack("<4sII", b"glTF", 2, 23) + struct.pack("<II", 3, JSON_CHUNK) + b"abc"
        path = self.root / "unaligned.glb"
        path.write_bytes(content)
        with self.assertRaises(generate_player_glb.MeshyError):
            generate_player_glb._validate_glb_container(path)

    def test_rejects_non_json_first_chunk(self) -> None:
        self.validate_rejects(make_glb(chunks=[(BIN_CHUNK, b"\\x00\\x00\\x00\\x00")]))

    def test_rejects_invalid_json_chunk(self) -> None:
        self.validate_rejects(make_glb(chunks=[(JSON_CHUNK, b"not-json") ]))

    def test_rejects_document_without_glTF_asset_version(self) -> None:
        self.validate_rejects(make_glb(document={"scene": 0, "scenes": []}))

    def test_rejects_duplicate_json_chunks(self) -> None:
        json_chunk = b'{"asset":{"version":"2.0"}}    '
        self.validate_rejects(make_glb(chunks=[(JSON_CHUNK, json_chunk), (JSON_CHUNK, json_chunk)]))

    def test_rejects_duplicate_binary_chunks(self) -> None:
        json_chunk = b'{"asset":{"version":"2.0"}}    '
        binary_chunk = b"\\x00\\x00\\x00\\x00"
        self.validate_rejects(make_glb(chunks=[
            (JSON_CHUNK, json_chunk),
            (BIN_CHUNK, binary_chunk),
            (BIN_CHUNK, binary_chunk),
        ]))

    def validate_rejects(self, content: bytes) -> None:
        path = self.root / "invalid.glb"
        path.write_bytes(content)
        with self.assertRaises(generate_player_glb.MeshyError):
            generate_player_glb._validate_glb_container(path)

    def test_download_accepts_valid_glb_and_replaces_existing_output(self) -> None:
        output = self.root / "player.glb"
        output.write_bytes(b"old model")
        content = make_glb()
        with mock.patch(
            "tools.generate_player_glb.urllib.request.urlopen",
            return_value=FakeResponse(content),
        ):
            generate_player_glb._download_glb(
                "https://cdn.example.invalid/model.glb", output, force=True
            )
        self.assertEqual(output.read_bytes(), content)
        self.assertFalse(output.with_suffix(".glb.part").exists())

    def test_download_rejects_truncated_glb_without_replacing_output(self) -> None:
        output = self.root / "player.glb"
        original = b"previous-good-model"
        output.write_bytes(original)
        malformed = make_glb(declared_size_delta=4)
        with mock.patch(
            "tools.generate_player_glb.urllib.request.urlopen",
            return_value=FakeResponse(malformed),
        ):
            with self.assertRaises(generate_player_glb.MeshyError):
                generate_player_glb._download_glb(
                    "https://cdn.example.invalid/model.glb", output, force=True
                )
        self.assertEqual(output.read_bytes(), original)
        self.assertFalse(output.with_suffix(".glb.part").exists())

    def test_download_rejects_https_to_http_redirect(self) -> None:
        output = self.root / "player.glb"
        original = b"previous-good-model"
        output.write_bytes(original)
        with mock.patch(
            "tools.generate_player_glb.urllib.request.urlopen",
            return_value=FakeResponse(make_glb(), final_url="http://insecure.example.invalid/model.glb"),
        ):
            with self.assertRaises(generate_player_glb.MeshyError):
                generate_player_glb._download_glb(
                    "https://cdn.example.invalid/model.glb", output, force=True
                )
        self.assertEqual(output.read_bytes(), original)
        self.assertFalse(output.with_suffix(".glb.part").exists())


if __name__ == "__main__":
    unittest.main()
