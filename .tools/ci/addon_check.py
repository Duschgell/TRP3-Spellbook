#!/usr/bin/env python3

import os
import re
import shutil
import stat
import subprocess
import sys
from pathlib import Path
from xml.etree import ElementTree as ET

CORE = "TRP3_RPSpellbook"
ADDONS = (CORE, CORE + "_GameMaster", CORE + "_NPC")
EXTERNAL = {"totalRP3", "totalRP3_Extended", "totalRP3_KuiNameplates"}
REQUIRED = {CORE: {"totalRP3"}, ADDONS[1]: {CORE}, ADDONS[2]: {CORE}}
LIFECYCLE = {
    CORE: (None, "Core.lua"),
    ADDONS[1]: ("Modules/GameMasterBootstrap.lua", None),
    ADDONS[2]: ("NPC/Bootstrap.lua", "NPC/Module.lua"),
}



LOAD_DEPENDENCIES = {
    "Constants.lua": (
        "Core/ConstantsExtension.lua", "Data/ExportCodec.lua", "TRP3Bridge.lua",
        "Chat/Fallbacks.lua", "Communication/Hover.lua", "UI/PlayerTooltip.lua",
        "SpellCreation/Editor.lua", "SpellCreation/Presentation.lua",
        "GameMaster/IncomingActions.lua",
        "Data/ReleaseNotes.lua", "UI/VersionCheck.lua",
    ),


    "Core/ConstantsExtension.lua": (
        "Communication/Protocol.lua", "Communication/GameMaster.lua",
        "Chat/Fallbacks.lua", "Communication/Hover.lua", "UI/PlayerTooltip.lua",
        "Data/ReleaseNotes.lua", "UI/VersionCheck.lua",
    ),


    "Core/Cache.lua": (
        "Communication/Protocol.lua", "Communication/GameMaster.lua",
        "TRP3Bridge.lua", "Chat/Fallbacks.lua", "Communication/Hover.lua",
        "UI/PlayerTooltip.lua",
        "UI/VersionCheck.lua",
    ),


    "TRP3Bridge.lua": ("Communication/Hover.lua",),
    "Core/Runtime.lua": ("GameMaster/IncomingActions.lua",),
    "Database.lua": ("Data/DatabaseHardening.lua",),
    "Data/BackupValidation.lua": ("Data/Backup.lua",),
    "UI/Theme.lua": ("UI/TimedEffects.lua",),
    "UI/UIFactory.lua": ("UI/TimedEffects.lua",),
    "Data/TimedEffects.lua": ("Core/TimedEffects.lua", "GameMaster/TimedEffects.lua"),
    "Data/EffectVisibility.lua": ("Chat/EffectSharing.lua",),
    "Data/ReleaseNotes.lua": ("Communication/Protocol.lua", "UI/VersionCheck.lua"),
    "Localization.lua": ("Locales/enUS.lua", "Locales/deDE.lua", "Locales/frFR.lua"),
    "Locales/enUS.lua": ("Bindings.lua",),
    "Locales/deDE.lua": ("Bindings.lua",),
    "Locales/frFR.lua": ("Bindings.lua",),
}


RESERVED = {"CON", "PRN", "AUX", "NUL"}
RESERVED.update(f"{prefix}{n}" for prefix in ("COM", "LPT") for n in range(1, 10))


def require(condition, message):
    if not condition:
        raise ValueError(message)


def kind(path):
    info = path.lstat()
    require(not stat.S_ISLNK(info.st_mode)
            and not getattr(info, "st_file_attributes", 0) & 0x400,
            f"Symlink/reparse point forbidden: {path}")
    if stat.S_ISDIR(info.st_mode):
        return "directory"
    require(stat.S_ISREG(info.st_mode), f"Special file forbidden: {path}")
    return "file"


def children(path):
    require(kind(path) == "directory", f"Not a directory: {path}")
    entries, folded = {}, set()
    for item in sorted(path.iterdir(), key=lambda p: p.name):
        key = item.name.casefold()
        require(key not in folded, f"Case collision in {path}: {item.name}")
        folded.add(key)
        entries[item.name] = item
    return entries



def exact(parent, name, expected):
    entries = children(parent)
    require(name in entries, f"Missing or wrong-case path: {parent / name}")
    result = entries[name]
    require(kind(result) == expected, f"Wrong file type: {result}")
    return result



def portable(name):
    require(re.fullmatch(r"[A-Za-z0-9_-][A-Za-z0-9_.-]*", name)
            and not name.endswith(".")
            and name.split(".", 1)[0].upper() not in RESERVED,
            f"Non-portable path component: {name!r}")


def reference(raw):
    parts = raw.replace("\\", "/").split("/")
    for part in parts:
        portable(part)
    return "/".join(parts)


def inventory(directory, prefix=""):
    result = {}
    entries = children(directory)
    require(entries, f"Empty package directory: {directory}")
    for name, path in entries.items():
        portable(name)
        relative = prefix + name
        if kind(path) == "directory":
            result.update(inventory(path, relative + "/"))
        else:
            require(path.suffix in {".lua", ".xml", ".toc"},
                    f"Unapproved deliverable type: {path}")
            result[relative] = path
    return result


def text(path):
    return path.read_bytes().decode("utf-8-sig")


def manifest(path):
    metadata, entries = {}, []
    for number, raw in enumerate(text(path).splitlines(), 1):
        line = raw.strip()
        if line.startswith("##"):
            key, separator, value = line[2:].partition(":")
            key = key.strip().casefold()
            require(separator and key, f"{path}:{number}: malformed metadata")
            require(key not in metadata, f"{path}:{number}: duplicate metadata")
            metadata[key] = value.strip()
        elif line and not line.startswith("#"):
            entries.append(reference(line))
    require(entries, f"Empty TOC inventory: {path}")
    require(metadata.get("title") and metadata.get("version"),
            f"Missing Title/Version: {path}")
    require(re.fullmatch(r"\d+(?:\s*,\s*\d+)*", metadata.get("interface", "")),
            f"Invalid/missing Interface: {path}")
    return metadata, entries


def dependencies(value):
    if not value:
        return []
    result = [part.strip() for part in value.split(",")]
    require(all(re.fullmatch(r"[A-Za-z0-9_][A-Za-z0-9_-]*", p)
                for p in result), f"Malformed dependency list: {value!r}")
    return result


def tool(root, name, flag, marker):
    executable = shutil.which(name)
    require(executable, f"Required tool missing: {name}")
    result = subprocess.run(
        [executable, flag], cwd=root, check=True, timeout=15,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
    )

    require(marker in result.stdout, f"Unexpected {name} version: {result.stdout}")
    print(result.stdout.strip(), flush=True)
    return executable


def run(root, *command):
    print("+ " + " ".join(map(str, command)), flush=True)
    subprocess.run(list(map(str, command)), cwd=root, check=True, timeout=60)



def main():
    require(len(sys.argv) == 2, "Usage: addon_check.py REPOSITORY_ROOT")
    root = Path(os.path.abspath(sys.argv[1]))
    require(kind(root) == "directory", "Repository root must be a directory")
    license_path = exact(root, "LICENSE", "file")
    require(license_path.read_bytes().strip(), "Empty LICENSE")
    package, lua_files, xml_files, graph = set(), [], [], {}
    for addon in ADDONS:
        directory = exact(root, addon, "directory")
        files = inventory(directory)
        toc = addon + ".toc"
        require(toc in files, f"Missing exact-name manifest: {addon}/{toc}")
        metadata, entries = manifest(files[toc])

        require("requireddeps" not in metadata or "dependencies" not in metadata,
                f"Ambiguous RequiredDeps/Dependencies: {addon}")

        required = dependencies(metadata.get(
            "requireddeps", metadata.get("dependencies", "")))

        optional = dependencies(metadata.get("optionaldeps", ""))
        declared = required + optional

        require(len({p.casefold() for p in declared}) == len(declared),
                f"Duplicate dependencies: {addon}")

        require(all(p in set(ADDONS) | EXTERNAL for p in declared),
                f"Unknown/wrong-case dependency: {addon}: {declared}")

        require(REQUIRED[addon] <= set(required),
                f"Missing mandatory dependency: {addon}: {REQUIRED[addon]}")

        graph[addon] = sorted(p for p in declared if p in ADDONS)
        bootstrap, activation = LIFECYCLE[addon]


        if bootstrap:
            require(bootstrap in entries, f"Missing bootstrap: {addon}/{bootstrap}")
            require(entries[0] == bootstrap, f"Bootstrap must load first: {addon}")

        if activation:
            require(activation in entries,
                    f"Missing activation entry: {addon}/{activation}")
            require(entries[-1] == activation,
                    f"Activation must follow all explicit TOC roots: {addon}")
        loaded, order = set(), []

        def load(relative):
            require(relative in files,
                    f"Missing/wrong-case reference: {addon}/{relative}")
            require(relative not in loaded,
                    f"Duplicate/cyclic load: {addon}/{relative}")
            path = files[relative]
            require(path.suffix in {".lua", ".xml"},
                    f"Invalid load target: {path}")
            loaded.add(relative)
            order.append(relative)
            content = text(path)
            if path.suffix == ".lua":
                require(not content.startswith("\x1bLua"),
                        f"Lua bytecode forbidden: {path}")
                lua_files.append(path)
                return

            require("\x00" not in content
                    and not re.search(r"<!\s*(?:DOCTYPE|ENTITY)\b", content, re.I),
                    f"DOCTYPE/entities/NUL forbidden: {path}")
            document = ET.fromstring(content)
            xml_files.append(path)
            for element in document.iter():
                tag = element.tag.rsplit("}", 1)[-1]
                if tag == "Include":
                    require("file" in element.attrib,
                            f"Include without file: {path}")
                if tag in {"Include", "Script"} and "file" in element.attrib:
                    child = reference(element.attrib["file"])
                    suffix = ".xml" if tag == "Include" else ".lua"
                    require(child.endswith(suffix), f"Wrong XML load type: {path}")
                    parent = relative.rpartition("/")[0]
                    load(parent + "/" + child if parent else child)


        for entry in entries:
            load(entry)
        if addon == CORE:
            require("Bindings.xml" in files, "Core Bindings.xml missing")

        if "Bindings.xml" in files:
            load("Bindings.xml")
        require(any(name.endswith(".lua") for name in loaded),
                f"Empty Lua inventory: {addon}")
        require(set(files) == loaded | {toc},
                f"Unreferenced deliverables in {addon}: "
                f"{sorted(set(files) - loaded - {toc})}")

        if addon == CORE:
            positions = {name: index for index, name in enumerate(order)}
            for provider, consumers in LOAD_DEPENDENCIES.items():
                require(provider in positions,
                        f"Missing load-order provider: {provider}")
                for consumer in consumers:
                    require(consumer in positions,
                            f"Missing load-order consumer: {consumer}")
                    require(positions[provider] < positions[consumer],
                            f"Provider must precede consumer: {provider} -> {consumer}")
        package.update(f"{addon}/{name}" for name in files)

    state, addon_order = {}, []

    def visit(addon):
        require(state.get(addon) != 1, f"Addon dependency cycle at {addon}")
        if state.get(addon) == 2:
            return
        state[addon] = 1
        for dependency in graph[addon]:
            visit(dependency)
        state[addon] = 2
        addon_order.append(addon)

    for addon in ADDONS:
        visit(addon)
    github = exact(root, ".github", "directory")
    workflow_directory = exact(github, "workflows", "directory")
    workflows = children(workflow_directory)
    require(workflows, "No workflows discovered")

    for name, path in workflows.items():
        portable(name)
        require(kind(path) == "file" and path.suffix in {".yml", ".yaml"},
                f"Unexpected workflow-directory entry: {path}")
        require(text(path).strip(), f"Empty workflow: {path}")
    require(lua_files and xml_files and workflows, "Empty check group")
    print(sys.version, flush=True)
    luac = tool(root, "luac5.1", "-v", "Lua 5.1")
    xmllint = tool(root, "xmllint", "--version", "libxml")
    actionlint = tool(root, "actionlint", "-version", "1.7.12")

    for path in sorted(lua_files):
        run(root, luac, "-p", path)

    for path in sorted(xml_files):
        run(root, xmllint, "--noout", "--nonet", path)

    run(root, actionlint, "-config-file", os.devnull,
        "-shellcheck=", "-pyflakes=", *workflows.values())

    print("Addon dependency order: " + " -> ".join(addon_order))

    for name in sorted(package):
        print("PACKAGE " + name)

    print(f"PASS: {len(lua_files)} Lua, {len(xml_files)} XML, "
          f"{len(workflows)} workflows; {len(package)} package files")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, ET.ParseError,
            subprocess.SubprocessError, RecursionError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        sys.exit(1)
