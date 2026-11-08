import json
import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import server
import setup_agent


class SetupTests(unittest.TestCase):
    def test_creation_attaches_only_two_native_tools_and_rerun_reuses_ids(self):
        with tempfile.TemporaryDirectory() as folder:
            state = Path(folder) / "agent.json"
            responses = [(json.dumps({"id": value}).encode(), "application/json")
                         for value in ("tool-state", "tool-reply", "agent-practice")]
            with patch.object(setup_agent, "cartesia", side_effect=responses) as provider:
                self.assertEqual(setup_agent.setup("private-key", "voice", state), "agent-practice")
                self.assertEqual(setup_agent.setup("private-key", "voice", state), "agent-practice")
                self.assertEqual(provider.call_count, 3)
                payload = provider.call_args.args[1]
                self.assertEqual(payload["config"]["tools"], [{"id": "tool-state"}, {"id": "tool-reply"}])
                self.assertIsNone(payload["config"]["turn"]["inactivity_check_in_secs"])
                self.assertNotIn("private-key", state.read_text())

    def test_confirmed_tools_survive_partial_failure(self):
        with tempfile.TemporaryDirectory() as folder:
            state = Path(folder) / "agent.json"
            with patch.object(setup_agent, "cartesia", side_effect=[(b'{"id":"tool-state"}', "application/json"), OSError()]):
                with self.assertRaises(OSError):
                    setup_agent.setup("key", "voice", state)
            with patch.object(setup_agent, "cartesia", side_effect=[(b'{"id":"tool-reply"}', "application/json"), (b'{"id":"agent"}', "application/json")]) as provider:
                setup_agent.setup("key", "voice", state)
                self.assertEqual(provider.call_count, 2)
                self.assertEqual(provider.call_args_list[0].args[1]["name"], "respond_to_check")

    def test_local_configuration_is_literal_and_does_not_override_environment(self):
        with tempfile.TemporaryDirectory() as folder, patch.dict(os.environ, {"CARTESIA_API_KEY": "existing"}, clear=True), patch.object(server, "LOCAL_STATE", Path(folder) / "missing"):
            config = Path(folder) / ".env"
            config.write_text('CARTESIA_API_KEY=do-not-use\nCARTESIA_VOICE_ID="voice"\nARMGUARD_GATEWAY_TOKEN=$(never-run-this)\n')
            server.load_local_config(config)
            self.assertEqual(os.environ["CARTESIA_API_KEY"], "existing")
            self.assertEqual(os.environ["CARTESIA_VOICE_ID"], "voice")
            self.assertEqual(os.environ["ARMGUARD_GATEWAY_TOKEN"], "$(never-run-this)")


if __name__ == "__main__":
    unittest.main()
