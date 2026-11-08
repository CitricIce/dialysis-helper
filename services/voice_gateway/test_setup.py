import json
import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import server
import setup_agent


class SetupTests(unittest.TestCase):
    def test_creation_attaches_three_native_tools_and_rerun_reuses_ids(self):
        with tempfile.TemporaryDirectory() as folder:
            state = Path(folder) / "agent.json"
            responses = [(json.dumps({"id": value}).encode(), "application/json")
                         for value in ("tool-state", "tool-reply", "tool-advance", "agent-practice")]
            with patch.object(setup_agent, "cartesia", side_effect=responses) as provider:
                self.assertEqual(setup_agent.setup("private-key", "voice", state), "agent-practice")
                self.assertEqual(setup_agent.setup("private-key", "voice", state), "agent-practice")
                self.assertEqual(provider.call_count, 4)
                payload = provider.call_args.args[1]
                self.assertEqual(payload["config"]["tools"], [{"id": "tool-state"}, {"id": "tool-reply"}, {"id": "tool-advance"}])
                self.assertIsNone(payload["config"]["turn"]["inactivity_check_in_secs"])
                self.assertNotIn("private-key", state.read_text())

    def test_confirmed_tools_survive_partial_failure(self):
        with tempfile.TemporaryDirectory() as folder:
            state = Path(folder) / "agent.json"
            with patch.object(setup_agent, "cartesia", side_effect=[(b'{"id":"tool-state"}', "application/json"), OSError()]):
                with self.assertRaises(OSError):
                    setup_agent.setup("key", "voice", state)
            with patch.object(setup_agent, "cartesia", side_effect=[(b'{"id":"tool-reply"}', "application/json"), (b'{"id":"tool-advance"}', "application/json"), (b'{"id":"agent"}', "application/json")]) as provider:
                setup_agent.setup("key", "voice", state)
                self.assertEqual(provider.call_count, 3)
                self.assertEqual(provider.call_args_list[0].args[1]["name"], "respond_to_check")

    def test_existing_agent_migration_keeps_other_tools_and_configuration(self):
        with tempfile.TemporaryDirectory() as folder:
            state = Path(folder) / "agent.json"
            state.write_text(json.dumps({"agent_id": "existing-agent", "tools": {"get_routine_state": "state", "respond_to_check": "reply"}}))
            current = [{"id": "state"}, {"id": "reply"}, {"id": "another-tool"}]
            responses = [(b'{"id":"advance"}', "application/json"),
                         (json.dumps({"config": {"tools": current, "model": {"id": "preserved"}}}).encode(), "application/json"),
                         (b'{}', "application/json")]
            with patch.object(setup_agent, "cartesia", side_effect=responses) as provider:
                self.assertEqual(setup_agent.setup("key", "voice", state), "existing-agent")
                self.assertEqual(provider.call_args_list[1].kwargs["method"], "GET")
                self.assertEqual(provider.call_args.kwargs["method"], "PATCH")
                self.assertEqual(provider.call_args.args[1], {"config": {"tools": current + [{"id": "advance"}]}})
                self.assertEqual(setup_agent.setup("key", "voice", state), "existing-agent")
                self.assertEqual(provider.call_count, 3)

    def test_existing_advance_tool_migrates_without_exact_words_parameter(self):
        with tempfile.TemporaryDirectory() as folder:
            state = Path(folder) / "agent.json"
            tools = {"get_routine_state": "state", "respond_to_check": "reply", "advance_practice_step": "advance"}
            state.write_text(json.dumps({"agent_id": "agent", "tools": tools, "attached_tools": list(tools)}))
            references = [{"id": value} for value in tools.values()]
            responses = [(b'{}', "application/json"), (json.dumps({"config": {"tools": references}}).encode(), "application/json")]
            with patch.object(setup_agent, "cartesia", side_effect=responses) as provider:
                self.assertEqual(setup_agent.setup("key", "voice", state), "agent")
                patch_call = provider.call_args_list[0]
                self.assertEqual(patch_call.args[0], "v1/agents/tools/advance")
                self.assertEqual(patch_call.kwargs["method"], "PATCH")
                self.assertEqual(patch_call.args[1]["parameters"]["required"], ["check_id"])
                self.assertEqual(setup_agent.setup("key", "voice", state), "agent")
                self.assertEqual(provider.call_count, 2)

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
