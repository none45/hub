import importlib
import sys
import os

BASE = "./functions"
sys.path.append(BASE)

def load_function(name):
    try:
        mod = importlib.import_module(name)
        importlib.reload(mod)
        return mod
    except ModuleNotFoundError:
        return None

def run_function(name, user=None, args=None):
    if args is None:
        args = {}
    mod = load_function(name)
    if not mod or not hasattr(mod, "main"):
        return "Function not found or has no main()"
    return mod.main(user, args)
