#!/usr/bin/env python3
"""
Safe writer for the `idle` block of `~/.config/omarchy/shell.json`.

shell.json is a shared, pre-existing file this plugin doesn't own outright
(omarchy-shell itself, and other plugins, read and write other keys in it).
Reading/writing it straight through a pathname -- which is what this
plugin's QML FileView used to do -- follows symlinks: a symlink planted at
`~/.config/omarchy/shell.json` itself, or at any ancestor directory
(`~/.config`, `~/.config/omarchy`), would silently redirect the merge-and-
overwrite this plugin does into an arbitrary file the user can write, and a
symlink swapped in between reading the old content and writing the merged
result back (TOCTOU) would do the same even if the path looked safe at the
first check.

Every access below instead goes through a directory file descriptor opened
via openat()-style, `dir_fd=`-relative calls, with `O_NOFOLLOW` on every
path component from $HOME down (not just the final leaf) so no ancestor in
the chain can be a symlink that redirects us elsewhere, and an ownership
check (refuses if `~/.config/omarchy` isn't owned by the current user --
but never chmods it: it's a shared directory with normal permissions, not
a private state dir this plugin controls). Immediately before committing,
shell.json is re-opened by identity (device+inode) and compared against
what was read at the start of this same invocation; a mismatch (or the
file appearing/disappearing since) aborts the write rather than clobbering
whatever's there now with a merge based on stale content. The commit
itself writes to a private, exclusively-created temp file in the same
directory, fsyncs it, then atomically renames it over shell.json --
rename(2) replaces the destination as a single unit without following it,
so this is safe even if shell.json currently is (or becomes) a symlink.
"""

import contextlib
import json
import os
import secrets
import stat
import sys
from pathlib import Path

HOME = Path.home()
SHELL_CONFIG_DIR = HOME / ".config" / "omarchy"
SHELL_CONFIG_FILENAME = "shell.json"

# shell.json also carries bar layout and every other plugin's settings, so
# it's bigger than a single-plugin state file, but still a hand-edited JSON
# document -- this is generous headroom, not a tuning knob. Without a cap, a
# swapped-in replacement regular file (same path, attacker-controlled
# content) could make the read below buffer arbitrary amounts of memory
# before JSON parsing ever gets a chance to reject it.
MAX_SHELL_CONFIG_BYTES = 4 * 1024 * 1024


class InsecureConfigPath(Exception):
    """shell.json or its containing directory isn't safely usable."""


def _open_dir_chain_nofollow(anchor_fd: int, components) -> int:
    """Descend from an already-open, trusted directory fd through each path
    component via openat(..., O_DIRECTORY | O_NOFOLLOW), so no ancestor in
    the chain -- not just the final leaf -- can be a symlink that redirects
    us somewhere else. Each intermediate fd is closed as soon as the next
    one is opened; the caller owns the returned final fd."""
    fd = anchor_fd
    owns_fd = False
    try:
        for name in components:
            next_fd = os.open(name, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=fd)
            if owns_fd:
                os.close(fd)
            fd = next_fd
            owns_fd = True
        return fd
    except BaseException:
        if owns_fd:
            os.close(fd)
        raise


def _open_config_dir_nofollow() -> int:
    """openat-style open of `~/.config/omarchy`. Every component from $HOME
    down is opened directory-relative with O_NOFOLLOW, so a mutable
    ancestor (e.g. `.config`) swapped for a symlink can't redirect the
    read-merge-write that follows into a different directory. Unlike a
    private per-plugin state dir, this never creates or chmods anything --
    it's a shared directory with normal, broader-than-0700 permissions --
    but it IS ownership-checked: refuses outright if it isn't owned by the
    current user, rather than trusting whatever is there."""
    components = SHELL_CONFIG_DIR.relative_to(HOME).parts
    home_fd = os.open(HOME, os.O_RDONLY | os.O_DIRECTORY)
    try:
        fd = _open_dir_chain_nofollow(home_fd, components)
    except OSError as e:
        raise InsecureConfigPath(f"{SHELL_CONFIG_DIR}: {e}") from e
    finally:
        os.close(home_fd)
    try:
        st = os.fstat(fd)
        if not stat.S_ISDIR(st.st_mode):
            raise InsecureConfigPath(f"{SHELL_CONFIG_DIR} is not a directory")
        if st.st_uid != os.getuid():
            raise InsecureConfigPath(f"{SHELL_CONFIG_DIR} is not owned by the current user")
        return fd
    except BaseException:
        os.close(fd)
        raise


def _open_regular_nofollow(dir_fd: int, name: str, flags: int):
    """openat(dir_fd, name, flags | O_NOFOLLOW), then verify the result is a
    plain regular file -- refuses a symlink (open itself fails, ELOOP) and
    also anything else non-regular that might already exist there (a fifo,
    device, etc., which O_NOFOLLOW alone doesn't catch). Returns None if the
    file doesn't exist."""
    try:
        fd = os.open(name, flags | os.O_NOFOLLOW, dir_fd=dir_fd)
    except FileNotFoundError:
        return None
    try:
        st = os.fstat(fd)
        if not stat.S_ISREG(st.st_mode):
            raise InsecureConfigPath(f"{name} is not a regular file")
        return fd
    except BaseException:
        os.close(fd)
        raise


def _read_all_fd(fd, max_bytes: int) -> str:
    """Read at most `max_bytes` from fd, raising if the file turns out to
    hold more than that -- reads up to max_bytes + 1 so an exact-cap-sized
    file doesn't false-positive, while never buffering more than that
    regardless of how large the underlying file actually is."""
    chunks = []
    total = 0
    limit = max_bytes + 1
    while total < limit:
        chunk = os.read(fd, min(65536, limit - total))
        if not chunk:
            break
        chunks.append(chunk)
        total += len(chunk)
    if total > max_bytes:
        raise InsecureConfigPath(f"{SHELL_CONFIG_FILENAME} exceeds {max_bytes}-byte cap")
    return b"".join(chunks).decode("utf-8", errors="replace")


def _write_config_dir_file_atomic(dir_fd: int, name: str, text: str) -> None:
    """Write `text` to `name` under `dir_fd` via a private, exclusively-
    created temp file in the same directory, fsync'd, then atomically
    renamed over the real name. rename(2) replaces the destination as a
    single unit without following it, so this is safe even if `name`
    currently is (or becomes) a symlink. The containing directory is
    fsync'd afterward too -- the rename itself is a directory-entry change,
    distinct from the file-content fsync, and can otherwise still be lost
    on a crash even though the write it reported success for looked durable."""
    tmp_name = f".{name}.tmp.{os.getpid()}.{secrets.token_hex(4)}"
    fd = os.open(tmp_name, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o644, dir_fd=dir_fd)
    try:
        with os.fdopen(fd, "w") as f:
            f.write(text)
            f.flush()
            os.fsync(f.fileno())
        os.replace(tmp_name, name, src_dir_fd=dir_fd, dst_dir_fd=dir_fd)
        os.fsync(dir_fd)
    except BaseException:
        with contextlib.suppress(OSError):
            os.unlink(tmp_name, dir_fd=dir_fd)
        raise


def mutate_idle_key(key: str, value) -> dict:
    """Merge `{"idle": {key: value}}` into shell.json and write the whole
    file back, so sibling keys (bar layout, other plugins' settings) survive
    untouched. Refuses to write if the current content doesn't parse as
    JSON, or if shell.json changed identity between the read at the start
    of this call and the commit at the end of it."""
    dir_fd = _open_config_dir_nofollow()
    try:
        before_fd = _open_regular_nofollow(dir_fd, SHELL_CONFIG_FILENAME, os.O_RDONLY)
        before_stat = None
        raw = ""
        if before_fd is not None:
            try:
                raw = _read_all_fd(before_fd, MAX_SHELL_CONFIG_BYTES).strip()
                before_stat = os.fstat(before_fd)
            finally:
                os.close(before_fd)

        config = {}
        if raw:
            try:
                parsed = json.loads(raw)
            except ValueError as e:
                return {"success": False, "error": f"shell.json parse failed, refusing to write: {e}"}
            if isinstance(parsed, dict):
                config = parsed

        if not isinstance(config.get("idle"), dict):
            config["idle"] = {}
        config["idle"][key] = value
        config["version"] = 1
        text = json.dumps(config, indent=2) + "\n"

        # Revalidate immediately before committing: abort on any state
        # change since the read above (identity change, or the file
        # appearing/disappearing) rather than overwrite based on a merge
        # that's no longer accurate -- and never write through whatever a
        # symlink swapped in during that window would have pointed to.
        after_fd = _open_regular_nofollow(dir_fd, SHELL_CONFIG_FILENAME, os.O_RDONLY)
        try:
            if (before_stat is None) != (after_fd is None):
                return {"success": False, "error": "shell.json appeared or disappeared since it was read; refusing to write"}
            if after_fd is not None:
                after_stat = os.fstat(after_fd)
                if (after_stat.st_dev, after_stat.st_ino) != (before_stat.st_dev, before_stat.st_ino):
                    return {"success": False, "error": "shell.json changed since it was read; refusing to overwrite"}
        finally:
            if after_fd is not None:
                os.close(after_fd)

        _write_config_dir_file_atomic(dir_fd, SHELL_CONFIG_FILENAME, text)
        return {"success": True, "idle": config["idle"]}
    finally:
        os.close(dir_fd)


def main() -> int:
    if len(sys.argv) != 3:
        print(json.dumps({"success": False, "error": "usage: power_timings_ctl.py <key> <json-value>"}))
        return 2
    key, value_json = sys.argv[1], sys.argv[2]
    try:
        value = json.loads(value_json)
    except ValueError as e:
        print(json.dumps({"success": False, "error": f"invalid value: {e}"}))
        return 2
    try:
        result = mutate_idle_key(key, value)
    except InsecureConfigPath as e:
        result = {"success": False, "error": str(e)}
    except OSError as e:
        result = {"success": False, "error": str(e)}
    print(json.dumps(result))
    return 0 if result.get("success") else 1


if __name__ == "__main__":
    sys.exit(main())
