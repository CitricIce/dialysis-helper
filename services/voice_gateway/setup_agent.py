"""Create ArmGuard's two client tools and agent using an authorized Cartesia key."""
import json
import os
from pathlib import Path

from server import INSTRUCTIONS, LOCAL_STATE, agent_payload, cartesia, load_local_config


def tool(name, description, properties):
    return {"type": "client", "name": name, "description": description,
            "pre_tool_speech": "off", "execution_mode": "immediate",
            "expects_response": True, "response_timeout_secs": 10,
            "parameters": {"type": "object", "properties": properties,
                           "required": list(properties)}}


TOOLS = [
    tool("get_routine_state", "Read the current step, native reply, pause and camera readiness. Use before acting on a routine reply.", {}),
    tool("respond_to_check", "Submit the latest exact user words once for the current check. Never submit assistant speech or invent consent.", {
        "check_id": {"type": "string", "description": "Current check_id returned by get_routine_state."},
        "user_words": {"type": "string", "description": "Verbatim latest user transcript, without paraphrasing."}}),
]


def save(path, state):
    temporary = path.with_suffix(".tmp")
    temporary.write_text(json.dumps(state, indent=2) + "\n")
    temporary.chmod(0o600)
    temporary.replace(path)


def setup(key, voice, path=LOCAL_STATE):
    path = Path(path)
    state = json.loads(path.read_text()) if path.exists() else {"tools": {}}
    if state.get("agent_id"):
        return state["agent_id"]
    for definition in TOOLS:
        if definition["name"] not in state["tools"]:
            data, _ = cartesia("v1/agents/tools", definition, key)
            state["tools"][definition["name"]] = json.loads(data)["id"]
            save(path, state)
    config = agent_payload("room", voice)["config_overrides"]
    config["instructions"] = INSTRUCTIONS
    config["tools"] = [{"id": value} for value in state["tools"].values()]
    config["turn"] = {"inactivity_check_in_secs": None, "inactivity_end_call_secs": 240}
    data, _ = cartesia("v1/agents", {
        "name": "ArmGuard practice companion", "config": config}, key)
    state["agent_id"] = json.loads(data)["id"]
    save(path, state)
    return state["agent_id"]


def main():
    load_local_config()
    if not os.environ.get("CARTESIA_API_KEY") or not os.environ.get("CARTESIA_VOICE_ID"):
        raise SystemExit("Set CARTESIA_API_KEY and CARTESIA_VOICE_ID in the local .env first.")
    try:
        agent_id = setup(os.environ["CARTESIA_API_KEY"], os.environ["CARTESIA_VOICE_ID"])
    except (OSError, ValueError, KeyError):
        # Provider errors may include credentials. Never echo their bodies.
        raise SystemExit("Agent setup failed. Check API-key permissions, voice ID and Managed Agents access. Saved resource IDs can be reused on the next run.") from None
    print("ArmGuard agent ready: " + agent_id)
    print("Run python3 services/voice_gateway/server.py next. The server reads the saved agent ID.")


if __name__ == "__main__":
    main()
