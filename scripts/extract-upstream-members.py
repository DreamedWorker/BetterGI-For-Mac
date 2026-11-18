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

PATCHED += [
    # Upstream forces a full blocking GC every 2 s inside the capture tick, holding the dispatcher lock.
    # With the whole app in one heap on macOS this stalls capture and every running task for ~250 ms each
    # time. OpenCvSharp reports Mat memory to the GC (AddMemoryPressure), so the runtime already collects
    # when native image memory grows; the forced collection is dropped.
    ("GameTask/TaskTriggerDispatcher.cs", [
        ("""                if ((DateTime.Now - _prevManualGc).TotalSeconds > 2)
                {
                    GC.Collect();
                    _prevManualGc = DateTime.Now;
                }""",
         """                // macOS port: periodic GC.Collect() removed (see scripts/extract-upstream-members.py)"""),
    ]),
]

PATCHED += [
    # The "auto enter game" trigger OCRs the whole screen every 2 s for 5 minutes after capture starts, to
    # catch the age-rating popup. On the CPU that OCR takes ~250 ms and stalls the capture loop each time.
    # The popup is only clicked when its white confirm button is found as well, so the (cheap) button
    # template match now runs first and the OCR only when the button is on screen. Same behaviour.
    ("GameTask/GameLoading/GameLoading.cs", [
        ("""            _latestLoadingOcrRegions = content.CaptureRectArea.FindMulti(RecognitionObject.OcrThis);
            if (_latestLoadingOcrRegions.Any(region =>
                    region.Text.Contains("适龄") || region.Text.Contains("监护")))
            {
                // 适龄提示窗口自动关闭
                var agePopup = content.CaptureRectArea.Find(ElementRecognition.Get("BtnWhiteConfirm", content.CaptureRectArea));
                if (!agePopup.IsEmpty())
                {
                    agePopup.Click();
                    _logger.LogInformation("检测到适龄提示，自动点击确认");
                }
            }""",
         """            // macOS port: button first, full-screen OCR only when it is present (see scripts/extract-upstream-members.py)
            var agePopup = content.CaptureRectArea.Find(ElementRecognition.Get("BtnWhiteConfirm", content.CaptureRectArea));
            if (!agePopup.IsEmpty())
            {
                _latestLoadingOcrRegions = content.CaptureRectArea.FindMulti(RecognitionObject.OcrThis);
                if (_latestLoadingOcrRegions.Any(region =>
                        region.Text.Contains("适龄") || region.Text.Contains("监护")))
                {
                    // 适龄提示窗口自动关闭
                    agePopup.Click();
                    _logger.LogInformation("检测到适龄提示，自动点击确认");
                }
            }"""),
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


def excluded_patterns():
    """Upstream paths left out of the build (Exclude.props), as regular expressions."""
    with open(os.path.join(ROOT, "src", "BetterGI.Core", "Exclude.props"), encoding="utf-8") as handle:
        text = handle.read()
    patterns = []
    for include in re.findall(r'<UpstreamExclude Include="([^"]+)"', text):
        for item in include.split(";"):
            item = item.strip().replace("$(U)", "")
            if item:
                patterns.append(re.compile("^" + re.escape(item).replace(r"\*\*", ".*").replace(r"\*", "[^/]*") + "$"))
    return patterns


def generate_match_template_patches():
    """Routes every upstream Cv2.MatchTemplate call to BetterGenshinImpact.Mac.FastMatch (parallel; OpenCV's
    own is single-threaded on Apple Silicon). Writes patched copies and the list of originals to exclude."""
    skip = excluded_patterns()
    already = {path for path, _ in PATCHED}
    rewritten = []
    for folder, dirs, files in os.walk(UP):
        rel_folder = os.path.relpath(folder, UP).replace(os.sep, "/")
        if rel_folder.split("/")[0] in ("View", "ViewModel", "Markup", "Wine", "obj", "bin"):
            dirs[:] = []
            continue
        for name in files:
            if not name.endswith(".cs"):
                continue
            rel = (name if rel_folder == "." else rel_folder + "/" + name)
            if rel in already or any(p.match(rel) for p in skip):
                continue
            with open(os.path.join(folder, name), encoding="utf-8-sig") as handle:
                text = handle.read()
            if "Cv2.MatchTemplate(" not in text:
                continue
            text = text.replace("Cv2.MatchTemplate(", "BetterGenshinImpact.Mac.FastMatch.MatchTemplate(")
            target = "MT_" + rel.replace("/", "_").replace(".cs", ".g.cs")
            header = f"// <auto-generated> Copy of upstream {rel} with Cv2.MatchTemplate routed to FastMatch by scripts/extract-upstream-members.py. Do not edit. </auto-generated>\n"
            with open(os.path.join(OUT, target), "w", encoding="utf-8") as handle:
                handle.write(header + text)
            rewritten.append(rel)
    props = ["<Project>", "  <!-- Generated by scripts/extract-upstream-members.py: originals replaced by MT_*.g.cs copies. -->", "  <ItemGroup>"]
    props += [f'    <UpstreamExclude Include="$(U){rel}" />' for rel in sorted(rewritten)]
    props += ["  </ItemGroup>", "</Project>", ""]
    with open(os.path.join(OUT, "MatchTemplatePatches.props"), "w", encoding="utf-8") as handle:
        handle.write("\n".join(props))
    print(f"MatchTemplate routed to FastMatch in {len(rewritten)} files")


def main():
    os.makedirs(OUT, exist_ok=True)
    for stale in os.listdir(OUT):
        if stale.startswith("MT_"):
            os.remove(os.path.join(OUT, stale))
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
    generate_match_template_patches()
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
