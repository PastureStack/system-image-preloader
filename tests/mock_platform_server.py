#!/usr/bin/env python3
"""Disposable compatibility API used by the real Docker integration smoke test."""

from __future__ import annotations

import argparse
import base64
import json
import pathlib
import signal
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse


ENVIRONMENT_NAME = "PastureStack Integration"
ENVIRONMENT_ID = "1a5"
STACK_NAME = "system-integration"
STACK_EXTERNAL_ID = "catalog://library:infra*system-integration:1"
STACK_PATH = "library:infra*system-integration"


def json_bytes(payload: object) -> bytes:
    return json.dumps(payload, separators=(",", ":")).encode("utf-8")


class Handler(BaseHTTPRequestHandler):
    server_version = "PastureStackIntegrationMock/1"

    def log_message(self, format_string: str, *args: object) -> None:
        del format_string, args

    def reply(self, status: int, payload: object, content_type: str = "application/json") -> None:
        body = payload if isinstance(payload, bytes) else json_bytes(payload)
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def authenticated(self) -> bool:
        expected = "Basic " + base64.b64encode(
            f"{self.server.access_key}:{self.server.secret_key}".encode("utf-8")
        ).decode("ascii")
        return self.headers.get("Authorization") == expected

    def do_GET(self) -> None:
        parsed = urlparse(self.path)
        query = parse_qs(parsed.query)

        if parsed.path == "/latest/self/stack/environment_name":
            self.reply(200, ENVIRONMENT_NAME.encode("utf-8"), "text/plain")
            return

        if parsed.path == "/latest/hosts":
            self.reply(200, [{"uuid": "integration-host"}])
            return

        if not self.authenticated():
            self.reply(401, {"message": "authentication required"})
            return

        if parsed.path == "/v2-beta/projects":
            if query.get("name") != [ENVIRONMENT_NAME]:
                self.reply(400, {"message": "unexpected environment query"})
                return
            self.reply(200, {"data": [{"id": ENVIRONMENT_ID}]})
            return

        if parsed.path == "/v2-beta/settings/registry.default":
            self.reply(200, {"value": None})
            return

        if parsed.path == "/v2-beta/stacks":
            if query.get("system") != ["true"] or query.get("accountId") != [ENVIRONMENT_ID]:
                self.reply(400, {"message": "unexpected stack query"})
                return
            if "name" in query:
                if query["name"] != [STACK_NAME]:
                    self.reply(404, {"data": []})
                    return
                self.reply(
                    200,
                    {"data": [{"name": STACK_NAME, "externalId": STACK_EXTERNAL_ID}]},
                )
                return
            self.reply(200, {"data": [{"name": STACK_NAME}]})
            return

        template_path = f"/v1-catalog/templates/{STACK_PATH}"
        if parsed.path == template_path:
            if query.get("platformVersion") != [self.server.platform_version]:
                self.reply(400, {"message": "unexpected platform version"})
                return
            version_link = (
                f"http://{self.headers['Host']}{template_path}/versions/1"
            )
            self.reply(200, {"versionLinks": [version_link]})
            return

        if parsed.path == f"{template_path}/versions/1":
            compose = (
                "version: '2'\n"
                "services:\n"
                "  integration-target:\n"
                f"    image: {self.server.target_image}\n"
            )
            self.reply(200, {"files": {"docker-compose.yml": compose}})
            return

        self.reply(404, {"message": "not found", "path": parsed.path})


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--port-file", required=True, type=pathlib.Path)
    parser.add_argument("--target-image", required=True)
    parser.add_argument("--platform-version", required=True)
    parser.add_argument("--access-key", required=True)
    parser.add_argument("--secret-key", required=True)
    args = parser.parse_args()

    server = ThreadingHTTPServer(("0.0.0.0", 0), Handler)
    server.target_image = args.target_image
    server.platform_version = args.platform_version
    server.access_key = args.access_key
    server.secret_key = args.secret_key
    args.port_file.write_text(str(server.server_port), encoding="ascii")

    def stop(_signum: int, _frame: object) -> None:
        raise SystemExit(0)

    signal.signal(signal.SIGTERM, stop)
    try:
        server.serve_forever()
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
