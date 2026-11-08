"""Create/migrate ArmGuard's native client tools with an authorized Cartesia key."""
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
    tool("advance_practice_step", "Advance the current ordinary practice check using conversational judgment when the user's answer is sufficient or they want to move on. Avoid confirmation loops and exact-phrase demands. Read state first. Cannot arm/skip a monitoring step, resume a pause, or clear contact review. Not a clinical verification.", {
        "check_id": {"type": "string", "description": "Current check_id from get_routine_state; never a future step. The app binds this to the latest real user turn automatically."}}),
]


def save(path, state):
    temporary = path.with_suffix(".tmp")
    temporary.write_text(json.dumps(state, indent=2) + "\n")
    temporary.chmod(0o600)
    temporary.replace(path)


def setup(key, voice, path=LOCAL_STATE):
    path = Path(path)
    state = json.loads(path.read_text()) if path.exists() else {"tools": {}}
    required = {definition["name"] for definition in TOOLS}
    if state.get("agent_id") and required.issubset(state.get("attached_tools", [])) and state.get("advance_tool_version") == 1:
        return state["agent_id"]
    for definition in TOOLS:
        if definition["name"] not in state["tools"]:
            data, _ = cartesia("v1/agents/tools", definition, key)
            state["tools"][definition["name"]] = json.loads(data)["id"]
            if definition["name"] == "advance_practice_step": state["advance_tool_version"] = 1
            save(path, state)
    if state.get("advance_tool_version") != 1:
        definition = next(item for item in TOOLS if item["name"] == "advance_practice_step")
        cartesia("v1/agents/tools/" + state["tools"]["advance_practice_step"],
                 {"parameters": definition["parameters"]}, key, method="PATCH")
        state["advance_tool_version"] = 1
        save(path, state)
    if state.get("agent_id"):
        agent_id = state["agent_id"]
        data, _ = cartesia(f"v1/agents/{agent_id}", None, key, method="GET")
        current = json.loads(data)["config"].get("tools", [])
        references = list(current)
        known = {item["id"] for item in references}
        for value in state["tools"].values():
            if value not in known:
                references.append({"id": value}); known.add(value)
        if references != current:
            cartesia(f"v1/agents/{agent_id}", {"config": {"tools": references}}, key, method="PATCH")
        state["attached_tools"] = sorted(required)
        save(path, state)
        return agent_id
    config = agent_payload("room", voice)["config_overrides"]
    config["instructions"] = INSTRUCTIONS
    config["tools"] = [{"id": value} for value in state["tools"].values()]
    config["turn"] = {"inactivity_check_in_secs": None, "inactivity_end_call_secs": 240}
    data, _ = cartesia("v1/agents", {
        "name": "ArmGuard practice companion", "config": config}, key)
    state["agent_id"] = json.loads(data)["id"]
    state["attached_tools"] = sorted(required)
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
    print("Native tools ready. Rebuild the iPhone app and start a new call. The hosted gateway is optional.")


if __name__ == "__main__":
    main()
