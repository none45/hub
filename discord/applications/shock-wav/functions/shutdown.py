def main(user, args):
    with open("globals/owner_id.txt", "r") as f:
        OWNER_ID = int(f.read().strip())

    if user.id != OWNER_ID:
        return {"content": "You can't do this!", "ephemeral": True}

    return {"content": "Shutting down...", "ephemeral": True, "actions": {"shutdown"}}

info = {
    "name": "shutdown",
    "args": {}
}
