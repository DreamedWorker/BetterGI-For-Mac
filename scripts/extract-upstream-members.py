#!/usr/bin/env python3
"""Extracts selected members from upstream WPF view models into src/BetterGI.Core/Mac/Generated/.

Upstream's task code calls a few static helpers that are declared inside view-model classes whose
files cannot compile on macOS (they are full of WPF). This script copies exactly those members,
verbatim, into partial classes, so the logic stays upstream's. Re-run it after updating upstream/.
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
UP = os.path.join(ROOT, "upstream", "BetterGenshinImpact")
OUT = os.path.join(ROOT, "src", "BetterGI.Core", "Mac", "Generated")

# (upstream file, class declaration to emit, [regex matching the declaration line of each member])
SPECS = [
    ("ViewModel/Pages/KeyBindingsSettingsPageViewModel.cs", "public partial class KeyBindingsSettingsPageViewModel",
     [r"public static VK MappingKey\("]),
    ("ViewModel/Pages/MapPathingViewModel.cs", "public partial class MapPathingViewModel",
     [r"public static readonly string PathJsonPath"]),
    ("ViewModel/Pages/ScriptControlViewModel.cs", "public partial class ScriptControlViewModel",
     [r"private static void SetProjectNextFlagFromSchedule\(", r"public static List<ScriptGroupProject> GetNextProjects\("]),
    ("GameTask/AutoPathing/PathRecorder.cs", "public partial class PathRecorder",
     [r"public static readonly JsonSerializerOptions JsonOptions"]),
    ("Model/SettingItem.cs", "[Serializable]\npublic partial class SettingItem",
     [r"public string Name \{", r"public string Type \{", r"public string Label \{", r"public List<string>\? Options \{",
      r"public Dictionary<string, List<string>>\? CascadeOptions \{", r"public object\? Default \{"]),
    ("ViewModel/Pages/TaskSettingsPageViewModel.cs", "public partial class TaskSettingsPageViewModel",
     [r"public bool GetFightStrategy\(out string path\)", r"public bool GetFightStrategy\(string strategyName, out string path\)",
      r"public bool GetTcgStrategy\("]),
]


def shim_namespaces():
    """Namespaces declared by the stand-in files; a `using` of any other WPF namespace is dropped."""
    found = set()
    for folder in ("src/BetterGI.Core/Shims", "src/BetterGI.Core/Mac", "src/BetterGI.Mac.Platform/Shims"):
        for name in os.listdir(os.path.join(ROOT, folder)):
            if name.endswith(".cs"):
                with open(os.path.join(ROOT, folder, name), encoding="utf-8") as handle:
                    found.update(re.findall(r"^namespace ([\w.]+)", handle.read(), re.M))
    return found


SHIMMED = shim_namespaces()
UI_PREFIXES = ("System.Windows", "Wpf.Ui", "BetterGenshinImpact.View", "Microsoft.Win32", "Microsoft.Xaml", "GongSolutions", "Microsoft.Web")


def usable(using_line):
    target = using_line.rstrip(";").split("=")[-1].replace("using", "").replace("static", "").strip()
    if not target.startswith(UI_PREFIXES):
        return True
    return "=" not in using_line and target in SHIMMED


def extract(lines, pattern):
    """Returns the member whose declaration line matches, with leading comments/attributes."""
    regex = re.compile(pattern)
    for index, line in enumerate(lines):
        if not regex.search(line):
            continue
        start = index
        while start > 0 and lines[start - 1].strip().startswith(("///", "//", "[")):
            start -= 1
        depth, end, seen_brace = 0, index, False
        for end in range(index, len(lines)):
            text = re.sub(r'"(\\.|[^"\\])*"', '""', lines[end])  # ignore braces inside string literals
            text = text.split("//")[0]
            depth += text.count("{") - text.count("}")
            seen_brace = seen_brace or "{" in text
            if (seen_brace and depth == 0) or (not seen_brace and text.rstrip().endswith(";")):
                break
        return lines[start:end + 1]
    raise SystemExit(f"member not found: {pattern}")


# Whole-file copies with a documented textual patch: (upstream file, [(old, new)]). The original must be
# listed in Exclude.props.
PATCHED = [
    # Upstream writes relative paths with backslashes ("User\\JsScript"). On macOS a backslash is an ordinary
    # file-name character, so the central path helper normalises separators.
    ("Core/Config/Global.cs", [
        ("return Path.Combine(StartUpPath, relativePath);",
         "return Path.Combine(StartUpPath, relativePath.Replace('\\\\', Path.DirectorySeparatorChar));"),
    ]),
    # The IPC pipe name is keyed by the Windows user SID; macOS has none, the user name serves.
    ("Service/Instance/InstanceContext.cs", [
        ("""        using var identity = WindowsIdentity.GetCurrent();
        var userSid = identity.User
                      ?? throw new InvalidOperationException("无法取得当前 Windows 用户 SID。");
        return ForUserSid(userSid.Value);""",
         """        return ForUserSid(Environment.UserName);"""),
    ]),
    # Windows ACLs on the IPC pipe become "current user only" (a 0600 Unix domain socket).
    ("Service/Instance/InstanceBootstrap.cs", [
        ("""        using var identity = WindowsIdentity.GetCurrent();
        var ownerSid = identity.User
                       ?? throw new InvalidOperationException("无法取得当前 Windows 用户 SID。");
        var networkSid = new SecurityIdentifier(WellKnownSidType.NetworkSid, null);
        var security = new PipeSecurity();
        security.SetAccessRuleProtection(isProtected: true, preserveInheritance: false);
        security.SetOwner(ownerSid);
        security.AddAccessRule(new PipeAccessRule(
            networkSid,
            PipeAccessRights.FullControl,
            AccessControlType.Deny));
        security.AddAccessRule(new PipeAccessRule(
            ownerSid,
            PipeAccessRights.FullControl,
            AccessControlType.Allow));
        var options = PipeOptions.Asynchronous | PipeOptions.WriteThrough;""",
         """        var options = PipeOptions.Asynchronous | PipeOptions.CurrentUserOnly;"""),
        ("""        return NamedPipeServerStreamAcl.Create(
            pipeName,
            PipeDirection.InOut,
            NamedPipeServerStream.MaxAllowedServerInstances,
            PipeTransmissionMode.Byte,
            options,
            inBufferSize: 16 * 1024,
            outBufferSize: 16 * 1024,
            security);""",
         """        return new NamedPipeServerStream(
            pipeName,
            PipeDirection.InOut,
            NamedPipeServerStream.MaxAllowedServerInstances,
            PipeTransmissionMode.Byte,
            options,
            inBufferSize: 16 * 1024,
            outBufferSize: 16 * 1024);"""),
    ]),
]

# Statements of upstream's service registration (App.xaml.cs) that mention any of these are left out:
# WPF views / view models / windows and Windows-only services. Everything else is registered unchanged.
REGISTRATION_SKIP = re.compile("|".join([
    r"AddView<", r"ViewModel", r"Window\b", r"Window>", r"RichTextBox", r"richTextBox", r"AddNavigationViewPageProvider",
    r"WebViewEnvironmentProvider", r"CloudGameStorageAreaProvider", r"InstanceVisualIdentity", r"ApplicationHostService",
    r"INavigationService", r"IUpdateService", r"ISnackbarService", r"DirectInputMonitor", r"RelativeMouseInputMonitorFactory",
    r"CustomHtmlMaskService", r"IMaskWindowHost", r"Guide", r"Dialogs", r"WebViewInstanceLauncher",
    r"RecognitionTemplateEditorService", r"WindowsNotificationSuppressionService", r"WebPageRuntimeProvider",
    r"I18N\.Culture", r"BannerImageService", r"PuloniaTaskClipboardService", r"PuloniaPlanEditingSession",
    r"PuloniaTriggerInstanceCatalog", r"InferenceSettingsInteraction",
]))


def statements(lines):
    """Splits a block of C# into top-level statements (ending with ';' at bracket depth 0)."""
    current, depth, result = [], 0, []
    for line in lines:
        stripped = line.strip()
        if not current and (not stripped or stripped.startswith("//") or stripped.startswith("#")):
            continue
        current.append(line)
        text = re.sub(r'"(\\.|[^"\\])*"', '""', line).split("//")[0]
        depth += sum(text.count(c) for c in "({[") - sum(text.count(c) for c in ")}]")
        if depth == 0 and text.rstrip().endswith(";"):
            result.append(current)
            current = []
    return result


def generate_registration():
    """Emits upstream's ConfigureServices body, minus UI statements, as MacUpstreamServices.Register."""
    with open(os.path.join(UP, "App.xaml.cs"), encoding="utf-8-sig") as handle:
        lines = handle.read().splitlines()
    start = next(i for i, l in enumerate(lines) if ".ConfigureServices((context, services) =>" in l) + 2
    end = next(i for i, l in enumerate(lines) if i > start and l.strip() == ")" and lines[i + 1].strip() == ".Build();") - 1
    kept, skipped = [], 0
    for statement in statements(lines[start:end]):
        if REGISTRATION_SKIP.search("\n".join(statement)):
            skipped += 1
            continue
        # A macOS app bundle must not be written to: logs go under the writable data root instead.
        kept += [l.replace('Path.Combine(AppContext.BaseDirectory, "log")', 'Global.Absolute("log")') for l in statement]
    usings = [l for l in lines if l.startswith("using ") and usable(l) and "Sinks.RichTextBox" not in l]
    text = ["// <auto-generated> Service registration extracted from upstream App.xaml.cs by scripts/extract-upstream-members.py,",
            "// with WPF / Windows-only statements removed. Do not edit. </auto-generated>", "#nullable enable", *usings,
            "using BetterGenshinImpact.ViewModel.Pages;", "", "namespace BetterGenshinImpact.Mac;", "",
            "public static partial class MacUpstreamServices", "{",
            "    public static void Register(IServiceCollection services)", "    {", *kept, "    }", "}", ""]
    with open(os.path.join(OUT, "MacUpstreamServices.g.cs"), "w", encoding="utf-8") as handle:
        handle.write("\n".join(text))
    print(f"service registration: kept {len(kept)} lines, skipped {skipped} UI statements")


def generate_config_docs():
    """Collects upstream's doc comments for config / parameter properties so the macOS settings editor can
    show them: {ClassName: {PropertyName: summary}} -> src/BetterGI.Mac/Assets/config-docs.json."""
    import glob
    import json
    docs = {}
    files = glob.glob(os.path.join(UP, "Core", "Config", "**", "*.cs"), recursive=True)
    files += [f for f in glob.glob(os.path.join(UP, "GameTask", "**", "*.cs"), recursive=True)
              if re.search(r"(Config|Param|Options)\.cs$", f)]
    member = re.compile(r"^\s*(?:\[[^\]]*\]\s*)*(?:public|private|protected|internal)\s+(?:static\s+|readonly\s+|virtual\s+|override\s+)*[\w<>\[\]?,. ]+?\s+_?(\w+)\s*(?:=|;|\{)")
    for path in files:
        with open(path, encoding="utf-8-sig") as handle:
            lines = handle.read().splitlines()
        current, summary, collecting = None, [], False
        for line in lines:
            text = line.strip()
            found = re.search(r"\b(?:class|record)\s+(\w+)", text)
            if found and not text.startswith("///"):
                current, summary = found.group(1), []
                continue
            if text.startswith("/// <summary>"):
                collecting, summary = True, []
                rest = text[len("/// <summary>"):].replace("</summary>", "").strip()
                if rest:
                    summary.append(rest)
                if "</summary>" in text:
                    collecting = False
                continue
            if collecting:
                if "</summary>" in text:
                    collecting = False
                    text = text.replace("</summary>", "")
                body = text.lstrip("/").strip()
                if body:
                    summary.append(body)
                continue
            if text.startswith("///") or text.startswith("[") and text.endswith("]"):
                continue
            found = member.match(line)
            if found and current and summary:
                name = found.group(1)
                name = name[0].upper() + name[1:]
                docs.setdefault(current, {})[name] = re.sub(r"<[^>]+>", "", " ".join(summary)).strip()
            if text:
                summary = []
    target = os.path.join(ROOT, "src", "BetterGI.Mac", "Assets", "config-docs.json")
    with open(target, "w", encoding="utf-8") as handle:
        json.dump(docs, handle, ensure_ascii=False, indent=0, sort_keys=True)
    print(f"config docs: {sum(len(v) for v in docs.values())} properties in {len(docs)} classes")


def main():
    os.makedirs(OUT, exist_ok=True)
    generate_config_docs()
    for path, patches in PATCHED:
        with open(os.path.join(UP, path), encoding="utf-8-sig") as handle:
            text = handle.read()
        for old, new in patches:
            if old not in text:
                raise SystemExit(f"patch target not found in {path}: {old}")
            text = text.replace(old, new)
        name = os.path.splitext(os.path.basename(path))[0]
        header = f"// <auto-generated> Copy of upstream {path} with a macOS patch applied by scripts/extract-upstream-members.py. Do not edit. </auto-generated>\n"
        with open(os.path.join(OUT, name + ".patched.g.cs"), "w", encoding="utf-8") as handle:
            handle.write(header + text)
        print(f"{name}: patched copy")
    generate_registration()
    for path, declaration, patterns in SPECS:
        with open(os.path.join(UP, path), encoding="utf-8-sig") as handle:
            lines = handle.read().splitlines()
        usings = [l for l in lines if l.startswith("using ") and usable(l)]
        namespace = next(l for l in lines if l.startswith("namespace ")).rstrip(";").split()[1]
        body = []
        for pattern in patterns:
            body += extract(lines, pattern) + [""]
        name = os.path.splitext(os.path.basename(path))[0]
        text = [f"// <auto-generated> Extracted verbatim from upstream {path} by scripts/extract-upstream-members.py. Do not edit. </auto-generated>",
                "#nullable enable", *usings, "", f"namespace {namespace};", "", declaration, "{", *body[:-1], "}", ""]
        with open(os.path.join(OUT, name + ".g.cs"), "w", encoding="utf-8") as handle:
            handle.write("\n".join(text))
        print(f"{name}: {len(patterns)} member(s)")


if __name__ == "__main__":
    sys.exit(main())
