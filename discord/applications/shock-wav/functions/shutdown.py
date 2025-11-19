def main(user, args):
    # read OWNER_ID from globals txt
    with open("globals/OWNER_ID.txt", "r") as f:
        OWNER_ID = int(f.read().strip())

    if user.id != OWNER_ID:
        return {"content": "You can't do this!", "ephemeral": True}

    return {"content": "Shutting down...", "ephemeral": True, "actions": {"shutdown"}}

info = {
    "name": "shutdown",
    "args": {}  # no args needed
}
