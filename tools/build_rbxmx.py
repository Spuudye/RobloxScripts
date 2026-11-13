"""Packs src/ into build/DigGame.rbxmx so the game can be dragged into Studio
without Rojo. Run: python3 tools/build_rbxmx.py"""

from pathlib import Path
from xml.sax.saxutils import escape

ROOT = Path(__file__).resolve().parent.parent
FOLDERS = [("DigShared", "src/shared"), ("DigServer", "src/server"), ("DigClient", "src/client")]

counter = 0


def ref() -> str:
    global counter
    counter += 1
    return f"RBX{counter:04d}"


def script_item(path: Path) -> str:
    name = path.name
    if name.endswith(".server.luau"):
        cls, name = "Script", name[: -len(".server.luau")]
    elif name.endswith(".client.luau"):
        cls, name = "LocalScript", name[: -len(".client.luau")]
    else:
        cls, name = "ModuleScript", name[: -len(".luau")]
    source = path.read_text()
    if "]]>" in source:
        raise SystemExit(f"{path} contains ']]>' which can't go in CDATA")
    return (
        f'<Item class="{cls}" referent="{ref()}"><Properties>'
        f'<string name="Name">{escape(name)}</string>'
        f"<ProtectedString name=\"Source\"><![CDATA[{source}]]></ProtectedString>"
        f"</Properties></Item>"
    )


def main() -> None:
    items = []
    for folder_name, rel in FOLDERS:
        children = "".join(script_item(p) for p in sorted((ROOT / rel).glob("*.luau")))
        items.append(
            f'<Item class="Folder" referent="{ref()}"><Properties>'
            f'<string name="Name">{folder_name}</string></Properties>{children}</Item>'
        )
    out = ROOT / "build" / "DigGame.rbxmx"
    out.parent.mkdir(exist_ok=True)
    out.write_text('<roblox version="4">\n' + "\n".join(items) + "\n</roblox>\n")
    print(f"wrote {out.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
