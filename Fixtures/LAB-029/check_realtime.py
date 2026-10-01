#!/usr/bin/env python3
"""LAB-029-B: compile the actual kernel, then prove a blocking render is rejected.

Run on the build host. Mutations exist only in build/LAB-029-B-probe; source stays unchanged.
This checks clang's C function effects, not Swift trampolines or realtime device deadlines.
"""
from pathlib import Path
import subprocess

root = Path(__file__).resolve().parents[2]
out = root / "build/LAB-029-B-probe"
out.mkdir(parents=True, exist_ok=True)
source = root / "Packages/LabFeatures/Sources/AudioWorkshopDSP/WorkshopKernel.c"
headers = source.parent / "include"
sdk = subprocess.check_output(["xcrun", "--sdk", "macosx", "--show-sdk-path"], text=True).strip()
base = ["xcrun", "clang", "-isysroot", sdk, "-I", str(headers), "-Wall", "-Wextra", "-fsyntax-only"]
subprocess.run(base + [str(source)], check=True)
print("Actual kernel: compiled clean", flush=True)
text = source.read_text()
needle = "static inline uint32_t bitsOf(float value) AWK_REALTIME {"
assert text.count(needle) == 1
for name, statement, diagnostic in [
    ("allocation", "void *p = malloc(4); free(p);", "'malloc'"),
    ("io", 'FILE *f = fopen("unused", "r"); (void)f;', "'fopen'"),
]:
    mutant = out / (name + ".c")
    mutant.write_text('#include <stdio.h>\n' + text.replace(needle, needle + "\n    " + statement))
    result = subprocess.run(base + [str(mutant)], capture_output=True, text=True)
    (out / (name + ".log")).write_text(result.stderr)
    assert result.returncode != 0, "Unsafe render unexpectedly compiled"
    assert "nonblocking" in result.stderr and diagnostic in result.stderr, result.stderr
    print(name + ": rejected by nonblocking diagnostics", flush=True)
    print(next(line for line in result.stderr.splitlines() if "error:" in line), flush=True)
