#!/usr/bin/env python3
"""校验 PaneGrid 双语对照表。

检查项：
1. 源码里每个 Localization.t/tf 与 AppNotice(key:) 的键都在对照表中（漏翻）。
2. 对照表中没有未被引用的键（冗余）。
3. 键与译文的占位符序列完全一致且顺序相同（避免 String(format:) 参数错位或崩溃）。
4. 译文非空。

用法（在仓库根目录）：
    python3 scripts/verify-localization.py
退出码：0 通过，1 存在问题。
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LOCALIZATION = ROOT / "Sources/PaneGridCore/Localization.swift"
SOURCES = [p for p in (ROOT / "Sources").rglob("*.swift") if p != LOCALIZATION]

KEY_RE = re.compile(r'Localization\.(t|tf)\(\s*"((?:[^"\\]|\\.)*)"')
NOTICE_RE = re.compile(r'key:\s*"((?:[^"\\]|\\.)*)"')
TABLE_RE = re.compile(r'^\s*"((?:[^"\\]|\\.)*)"\s*:\s*"((?:[^"\\]|\\.)*)"\s*,?\s*$')
SPEC_RE = re.compile(r'%(?:@|ld|d|s|f|\.\d+f)')

# 这些键通过枚举 rawValue 或运行时兜底引用，静态扫描看不到字面量调用。
DYNAMIC_KEYS = {
    "Workspace", "Saved layouts", "Settings",   # WorkspaceSection.rawValue
    "System", "Dark", "Light",                  # AppTheme.rawValue.capitalized
    "Follow System",                            # AppLanguage.label
    "Application",                              # AppDelegate 兜底名称
}


def unescape(value: str) -> str:
    return value.replace('\\"', '"').replace("\\\\", "\\")


def main() -> int:
    if not LOCALIZATION.exists():
        print(f"找不到对照表：{LOCALIZATION}")
        return 1

    table = {}
    problems = []
    for number, line in enumerate(LOCALIZATION.read_text(encoding="utf-8").splitlines(), 1):
        match = TABLE_RE.match(line)
        if not match:
            continue
        key, value = unescape(match.group(1)), unescape(match.group(2))
        if key in table:
            problems.append(f"DUPLICATE KEY {key!r}（第 {number} 行，首次在第 {table[key][1]} 行）")
        table[key] = (value, number)

    used = {key: ["<dynamic>"] for key in DYNAMIC_KEYS}
    for path in SOURCES:
        for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            place = f"{path.relative_to(ROOT)}:{number}"
            for _, literal in KEY_RE.findall(line):
                used.setdefault(unescape(literal), []).append(place)
            for literal in NOTICE_RE.findall(line):
                used.setdefault(unescape(literal), []).append(place)

    for key, places in sorted(used.items()):
        if key not in table:
            problems.append(f"MISSING TRANSLATION {key!r}\n    used at {', '.join(places)}")

    for key in sorted(table):
        if key not in used:
            problems.append(f"UNUSED KEY {key!r}")

    for key, (value, number) in sorted(table.items()):
        if not value.strip():
            problems.append(f"EMPTY TRANSLATION {key!r}（第 {number} 行）")
            continue
        if SPEC_RE.findall(key) != SPEC_RE.findall(value):
            problems.append(
                f"PLACEHOLDER MISMATCH {key!r}（第 {number} 行）\n"
                f"    key:   {SPEC_RE.findall(key)}\n"
                f"    value: {SPEC_RE.findall(value)}"
            )

    print(f"源码引用键: {len(used)}    对照表条目: {len(table)}")
    if problems:
        print(f"\n发现 {len(problems)} 个问题：\n")
        for problem in problems:
            print(problem)
        return 1

    print("PASS：所有键均已翻译，占位符一致，无冗余条目。")
    return 0


if __name__ == "__main__":
    sys.exit(main())

