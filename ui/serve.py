#!/usr/bin/env python3
"""Serve the stemma browser UI for one project, with rebuild-on-demand.

    python3 ui/serve.py -d examples/echo            # http://127.0.0.1:8737
    python3 ui/serve.py -d examples/echo --stemma "cabal run -v0 stemma --"

Standard library only. The UI reads <dir>/build/lexicon.json and diff.txt;
"Rebuild" runs `stemma -d <dir> build` and reports its output. The Rules
tab reads and saves the project's .bsc files, outlines them with
`stemma rules` (Brassica's parser), and previews an unsaved edit by building
a temporary copy of the project. Lexicon entries in the YAML files can be
edited, previewed and saved the same way. Binds to localhost only.
"""

import argparse
import json
import os
import re
import shlex
import shutil
import subprocess
import sys
import tempfile
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

UI_DIR = Path(__file__).resolve().parent
REPO_DIR = UI_DIR.parent
INPUT_SUFFIXES = {".yaml", ".yml", ".bsc"}


def default_stemma():
    if shutil.which("stemma"):
        return ["stemma"]
    built = REPO_DIR / "result" / "bin" / "stemma"
    if built.exists():
        return [str(built)]
    return ["cabal", "run", "-v0", "stemma", "--"]


def inputs_mtime(project):
    """The newest modification time among the project's inputs."""
    newest = 0.0
    for root, dirs, files in os.walk(project):
        dirs[:] = [d for d in dirs if d != "build" and not d.startswith(".")]
        for f in files:
            if Path(f).suffix in INPUT_SUFFIXES:
                newest = max(newest, os.stat(os.path.join(root, f)).st_mtime)
    return newest


def rules_files(project):
    """The project's .bsc files, relative to it."""
    out = []
    for root, dirs, files in os.walk(project):
        dirs[:] = sorted(d for d in dirs if d != "build" and not d.startswith("."))
        for f in sorted(files):
            if f.endswith(".bsc"):
                out.append(Path(root, f).relative_to(project).as_posix())
    return out


def rules_path(project, rel, suffixes=(".bsc",)):
    """A .bsc file inside the project (outside build/), or None."""
    if not isinstance(rel, str) or not rel.endswith(suffixes):
        return None
    p = (project / rel).resolve()
    return p if p.is_relative_to(project) and "build" not in p.relative_to(project).parts else None


def add_stage_rules(yaml_text, stage, ref):
    """family.yaml with `rules: "<ref>"` added to one stage, editing the text
    so comments and layout are kept. Only block-style stages are handled."""
    lines = yaml_text.split("\n")
    top = next((k for k, l in enumerate(lines) if re.match(r"^stages\s*:\s*(#.*)?$", l)), None)
    if top is None:
        raise ValueError("family.yaml has no top-level stages: block")
    key = re.compile(r"^(\s+)([\"']?)" + re.escape(stage) + r"\2\s*:\s*(#.*)?$")
    at_key = indent = None
    for k in range(top + 1, len(lines)):
        line = lines[k]
        if line.strip() and not line[0].isspace() and not line.startswith("#"):
            break                                   # the next top-level key
        m = key.match(line)
        if m:
            at_key, indent = k, len(m.group(1))
            break
    if at_key is None:
        raise ValueError(f"couldn't find stage {stage} in family.yaml "
                         "(stages written in flow style, { ... }, aren't supported)")
    child = parent = None
    last = at_key
    for k in range(at_key + 1, len(lines)):
        line = lines[k]
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        lead = len(line) - len(line.lstrip())
        if lead <= indent:
            break
        child = child or lead
        if lead == child:
            if re.match(r"\s*rules\s*:", line):
                raise ValueError(f"{stage} already has rules in family.yaml")
            if re.match(r"\s*parent\s*:", line):
                parent = k
        last = k
    at = (parent if parent is not None else last) + 1
    lines.insert(at, " " * (child or indent + 2) + f'rules: "{ref}"')
    return "\n".join(lines)


SOURCE_SUFFIXES = (".bsc", ".yaml", ".yml")


def source_path(project, rel):
    """A rules or YAML file inside the project (outside build/), or None."""
    return rules_path(project, rel, SOURCE_SUFFIXES)


def yaml_files(project):
    """The project's YAML files, relative to it."""
    out = []
    for root, dirs, files in os.walk(project):
        dirs[:] = sorted(d for d in dirs if d != "build" and not d.startswith("."))
        for f in sorted(files):
            if f.endswith((".yaml", ".yml")):
                out.append(Path(root, f).relative_to(project).as_posix())
    return out


def make_handler(project, stemma):
    build_dir = project / "build"

    def run(args, cwd=REPO_DIR, stdin=None):
        cmd = stemma + args
        try:
            p = subprocess.run(cmd, cwd=cwd, input=stdin, capture_output=True, text=True, timeout=600)
            return {"ok": p.returncode == 0, "code": p.returncode, "command": shlex.join(cmd),
                    "stdout": p.stdout, "stderr": p.stderr}
        except (OSError, subprocess.TimeoutExpired) as e:
            return {"ok": False, "code": None, "command": shlex.join(cmd), "stdout": "", "stderr": str(e)}

    def outline(content):
        r = run(["rules", "-"], stdin=content)
        try:
            return json.loads(r["stdout"])
        except ValueError:
            return {"ok": False, "error": r["stderr"] or "stemma rules failed", "line": None, "column": None}

    baseline = {"inputs": None, "mismatches": []}

    def baseline_mismatches():
        """The current sources' expectation mismatches, from a build of a
        copy (so build/ and its diff are left alone); cached until the
        sources change."""
        now = inputs_mtime(project)
        if baseline["inputs"] != now:
            with tempfile.TemporaryDirectory(prefix="stemma-base-") as tmp:
                copy = Path(tmp) / "project"
                shutil.copytree(project, copy, ignore=shutil.ignore_patterns("build", ".*"))
                r = run(["-d", str(copy), "build"])
            baseline["inputs"] = now
            baseline["mismatches"] = [l[len("MISMATCH: "):] for l in r["stderr"].splitlines()
                                      if l.startswith("MISMATCH: ")]
        return baseline["mismatches"]

    def preview(rel, content):
        """Build a copy of the project with one file replaced."""
        return build_with({rel: content}, [])

    def build_with(writes, deletes):
        """Build a copy of the project with some files written and some
        removed. The copy keeps build/forms.tsv, so its diff is against the
        current build."""
        with tempfile.TemporaryDirectory(prefix="stemma-preview-") as tmp:
            copy = Path(tmp) / "project"
            shutil.copytree(project, copy, ignore=shutil.ignore_patterns("build", ".*"))
            if (build_dir / "forms.tsv").exists():
                (copy / "build").mkdir()
                shutil.copy2(build_dir / "forms.tsv", copy / "build" / "forms.tsv")
            for rel, content in writes.items():
                (copy / rel).parent.mkdir(parents=True, exist_ok=True)
                (copy / rel).write_text(content, encoding="utf-8")
            for rel in deletes:
                (copy / rel).unlink(missing_ok=True)
            r = run(["-d", str(copy), "build"])
            # Paths in messages relative to the project, as the UI shows them.
            for k in ("stdout", "stderr"):
                r[k] = r[k].replace(str(copy) + os.sep, "").replace(str(copy), ".")
            lex = copy / "build" / "lexicon.json"
            diff = copy / "build" / "diff.txt"
            r["lexicon"] = json.loads(lex.read_text(encoding="utf-8")) if lex.exists() else None
            r["diff"] = diff.read_text(encoding="utf-8").splitlines() if diff.exists() else None
        r["baseline_mismatches"] = baseline_mismatches()
        return r

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, fmt, *args):
            pass

        def send(self, code, body, ctype="application/json; charset=utf-8"):
            if isinstance(body, str):
                body = body.encode("utf-8")
            self.send_response(code)
            self.send_header("Content-Type", ctype)
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(body)

        def send_json(self, value, code=200):
            self.send(code, json.dumps(value, ensure_ascii=False))

        def send_file(self, path, ctype):
            try:
                self.send(200, path.read_bytes(), ctype)
            except FileNotFoundError:
                self.send_json({"error": f"{path.name} not found; build first"}, 404)

        def do_GET(self):
            route = self.path.split("?", 1)[0]
            if route in ("/", "/index.html"):
                self.send_file(UI_DIR / "index.html", "text/html; charset=utf-8")
            elif route == "/api/lexicon":
                self.send_file(build_dir / "lexicon.json", "application/json; charset=utf-8")
            elif route == "/api/diff":
                self.send_file(build_dir / "diff.txt", "text/plain; charset=utf-8")
            elif route == "/api/rules":
                self.send_json([{"file": f, "content": (project / f).read_text(encoding="utf-8")}
                                for f in rules_files(project)])
            elif route == "/api/sources":
                self.send_json([{"file": f, "content": (project / f).read_text(encoding="utf-8")}
                                for f in yaml_files(project)])
            elif route == "/api/status":
                self.send_json({
                    "project": str(project),
                    "inputs": inputs_mtime(project),
                    "built": (build_dir / "lexicon.json").stat().st_mtime
                    if (build_dir / "lexicon.json").exists() else None,
                })
            else:
                self.send_json({"error": "not found"}, 404)

        def body(self):
            n = int(self.headers.get("Content-Length") or 0)
            try:
                return json.loads(self.rfile.read(n) or b"{}")
            except ValueError:
                return {}

        def do_POST(self):
            route = self.path.split("?", 1)[0]
            if route == "/api/build":
                return self.send_json(run(["-d", str(project), "build"]))
            req = self.body()
            if route == "/api/outline":
                return self.send_json(outline(req.get("content", "")))
            if route == "/api/preview":
                if source_path(project, req.get("file")) is None:
                    return self.send_json({"error": "not a rules or YAML file in this project"}, 400)
                return self.send_json(preview(req["file"], req.get("content", "")))
            if route == "/api/changeset":
                return self.send_json(*changeset(req))
            if route == "/api/stage-rules":
                return self.send_json(*create_stage_rules(req))
            self.send_json({"error": "not found"}, 404)

        def do_PUT(self):
            # /api/rules saves an existing .bsc file; /api/source also YAML.
            route = self.path.split("?", 1)[0]
            if route not in ("/api/rules", "/api/source"):
                return self.send_json({"error": "not found"}, 404)
            req = self.body()
            path = (rules_path if route == "/api/rules" else source_path)(project, req.get("file"))
            if path is None or not path.exists() or not isinstance(req.get("content"), str):
                return self.send_json({"error": "not a file this server can edit"}, 400)
            path.write_text(req["content"], encoding="utf-8")
            self.send_json({"ok": True})

    def changeset(req):
        """Write and delete several files together: {writes: {path: text},
        deletes: [path], expect: {path: text}, apply: bool}. Always builds a
        copy first and returns what that build says. With apply, the change
        is made only if the copy built and every file in expect still has
        the text the change was based on."""
        writes, deletes, expect = req.get("writes") or {}, req.get("deletes") or [], req.get("expect") or {}
        if not isinstance(writes, dict) or not isinstance(deletes, list) or not isinstance(expect, dict):
            return {"error": "bad changeset"}, 400
        for rel in [*writes, *deletes, *expect]:
            if source_path(project, rel) is None:
                return {"error": f"{rel} is not a rules or YAML file in this project"}, 400
        for rel in deletes:
            if Path(rel).name in ("family.yaml", "family.yml"):
                return {"error": "family.yaml can't be deleted"}, 400
        if any(not isinstance(v, str) for v in [*writes.values(), *expect.values()]):
            return {"error": "bad changeset"}, 400
        for rel, text in expect.items():
            path = project / rel
            if not path.exists() or path.read_text(encoding="utf-8") != text:
                return {"error": f"{rel} changed on disk since this was prepared; reload and try again",
                        "conflict": rel}, 409
        r = build_with(writes, deletes)
        r["applied"] = False
        if req.get("apply") and r["lexicon"] is not None:
            for rel, content in writes.items():
                path = source_path(project, rel)
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(content, encoding="utf-8")
            for rel in deletes:
                source_path(project, rel).unlink(missing_ok=True)
            r["applied"] = True
        return r, 200

    def create_stage_rules(req):
        """Give a stage a new rules file: create it and point the stage at it
        in family.yaml. Tried on a copy of the project first, so a bad edit
        never reaches the real files."""
        stage, rel, content = req.get("stage"), req.get("file"), req.get("content", "")
        path = rules_path(project, rel)
        if not isinstance(stage, str) or not stage or path is None or not isinstance(content, str):
            return {"error": "need a stage and a .bsc path inside the project"}, 400
        if path.exists():
            return {"error": f"{rel} already exists; choose another name"}, 400
        family = project / "family.yaml"
        try:
            new_family = add_stage_rules(family.read_text(encoding="utf-8"), stage, rel)
        except ValueError as e:
            return {"error": str(e)}, 400
        with tempfile.TemporaryDirectory(prefix="stemma-stage-") as tmp:
            copy = Path(tmp) / "project"
            shutil.copytree(project, copy, ignore=shutil.ignore_patterns("build", ".*"))
            (copy / "family.yaml").write_text(new_family, encoding="utf-8")
            (copy / rel).parent.mkdir(parents=True, exist_ok=True)
            (copy / rel).write_text(content, encoding="utf-8")
            r = run(["-d", str(copy), "build"])
            if not (copy / "build" / "lexicon.json").exists():
                return {"error": "the project wouldn't build with this change:\n"
                        + r["stderr"].replace(str(copy) + os.sep, "").replace(str(copy), ".")}, 400
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8")
        family.write_text(new_family, encoding="utf-8")
        return {"ok": True, "file": rel}, 200

    return Handler


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("-d", "--dir", default=".", help="project directory (default: .)")
    ap.add_argument("-p", "--port", type=int, default=8737)
    ap.add_argument("--stemma", help="command that runs stemma (default: stemma on PATH, "
                    "then result/bin/stemma, then cabal run)")
    args = ap.parse_args()

    project = Path(args.dir).resolve()
    if not (project / "family.yaml").exists():
        sys.exit(f"error: {project} has no family.yaml")
    stemma = shlex.split(args.stemma) if args.stemma else default_stemma()

    server = ThreadingHTTPServer(("127.0.0.1", args.port), make_handler(project, stemma))
    print(f"stemma ui for {project}")
    print(f"  builds with: {shlex.join(stemma)}")
    print(f"  http://127.0.0.1:{args.port}/")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
