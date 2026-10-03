#!/usr/bin/env python3
"""Stdio test for the Casa Desk MCP server: initialize, tools/list, and an argument-check call.

Needs no permissions and reads no personal data. Run: python3 Tests/test_mcp.py
"""
import json
import os
import subprocess
import sys
import unittest

SERVER = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "mcp", "casa-desk-mcp.py")
EXPECTED = {"doctor", "calendar_list", "calendar_search", "reminders_lists", "reminders_list", "contacts_search",
            "contacts_show", "notes_search", "notes_show", "messages_search", "messages_chats", "mail_list", "mail_search",
            "mail_read", "shortcuts_list", "icloud_list", "icloud_read", "spotlight_search", "focus_status",
            "safari_bookmarks", "safari_reading_list"}


def session(messages):
    p = subprocess.run([sys.executable, SERVER], input="".join(json.dumps(m) + "\n" for m in messages),
                       capture_output=True, text=True, timeout=30)
    return [json.loads(l) for l in p.stdout.splitlines() if l.strip()]


class MCPTest(unittest.TestCase):
    def test_initialize_and_list(self):
        replies = session([
            {"jsonrpc": "2.0", "id": 1, "method": "initialize",
             "params": {"protocolVersion": "2025-06-18", "capabilities": {}, "clientInfo": {"name": "test", "version": "0"}}},
            {"jsonrpc": "2.0", "method": "notifications/initialized"},
            {"jsonrpc": "2.0", "id": 2, "method": "tools/list"},
        ])
        self.assertEqual(len(replies), 2, "the notification must get no reply")
        init, listed = replies
        self.assertEqual(init["id"], 1)
        self.assertEqual(init["result"]["serverInfo"]["name"], "casa-desk")
        self.assertIn("tools", init["result"]["capabilities"])
        tools = listed["result"]["tools"]
        self.assertEqual({t["name"] for t in tools}, EXPECTED)
        for t in tools:
            self.assertTrue(t["annotations"]["readOnlyHint"], t["name"])
            self.assertFalse(t["annotations"]["destructiveHint"], t["name"])
            self.assertEqual(t["inputSchema"]["type"], "object")

    def test_missing_argument_is_an_error_not_a_crash(self):
        (reply,) = session([{"jsonrpc": "2.0", "id": 3, "method": "tools/call",
                             "params": {"name": "contacts_search", "arguments": {}}}])
        self.assertTrue(reply["result"]["isError"])
        self.assertIn("missing q", reply["result"]["content"][0]["text"])

    def test_unknown_method(self):
        (reply,) = session([{"jsonrpc": "2.0", "id": 4, "method": "resources/write"}])
        self.assertEqual(reply["error"]["code"], -32601)


if __name__ == "__main__":
    unittest.main()
