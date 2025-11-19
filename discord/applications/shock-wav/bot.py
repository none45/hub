import os
import sys
import json
import importlib
import discord
from discord import app_commands

sys.path.append("./functions")
import functions_manager

# ---------- Load Bot Token from GitHub Secret ----------
tokens_json = os.environ.get("DISCORD_APP_TOKENS")
if not tokens_json:
    raise Exception("DISCORD_APP_TOKENS env variable not found!")

tokens = json.loads(tokens_json)
BOT_NAME = "shock-wav"
TOKEN = tokens.get(BOT_NAME)
if not TOKEN:
    raise Exception(f"Token for {BOT_NAME} not found!")

# ---------- Read OWNER_ID from globals txt ----------
with open("globals/owner_id.txt", "r") as f:
    OWNER_ID = int(f.read().strip())

# ---------- Bot Setup ----------
intents = discord.Intents.default()
bot = discord.Client(intents=intents)
tree = app_commands.CommandTree(bot)

# ---------- Load functions ----------
BASE = "./functions"
functions_files = [f.replace(".py", "") for f in os.listdir(BASE) if f.endswith(".py")]

async def register_command(func_name):
    mod = importlib.import_module(func_name)
    importlib.reload(mod)
    info = getattr(mod, "info", {})
    command_name = info.get("name")
    if command_name is None:
        return  # skip functions without a slash command

    @tree.command(name=command_name, description=f"Run {command_name}")
    async def generic_call(interaction: discord.Interaction):
        args_table = info.get("args", {})
        args = {}
        for key in args_table:
            if args_table[key] == "user_id":
                args[key] = interaction.user.id
            else:
                args[key] = ""

        result = functions_manager.run_function(func_name, user=interaction.user, args=args)

        if isinstance(result, dict):
            content = result.get("content", "")
            ephemeral = result.get("ephemeral", False)
            await interaction.response.send_message(content, ephemeral=ephemeral)

            actions = result.get("actions", set())
            if "shutdown" in actions:
                await bot.close()
        else:
            await interaction.response.send_message(str(result))

@bot.event
async def on_ready():
    # set bot online and activity
    await bot.change_presence(
        status=discord.Status.online,
        activity=discord.Game(name="with functions")
    )

    # register slash commands
    for func_name in functions_files:
        await register_command(func_name)
    await tree.sync()

    # print immediately
    print(f"{bot.user} online and status set")

# ---------- Run Bot ----------
bot.run(TOKEN)
