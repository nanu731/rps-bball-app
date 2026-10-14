#!/usr/bin/env python3
"""Run actual native journeys in an isolated copy; never edit/reset the original app.

An operator owns Simulator while this runs. The isolated app/container is reused;
synthetic records and private screenshots/results are retained, never deleted.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import signal
import subprocess
import sys
import time
from datetime import datetime, timezone

APP_ID = "com.narayanlekhi.TeamStats.UIAcceptance"
DEVELOPER = "/Applications/Xcode.app/Contents/Developer"


def replace_exact(text, old, new, count):
    if text.count(old) != count:
        raise RuntimeError("Unexpected project structure; original project is unchanged")
    return text.replace(old, new)


def prepare(root, destination, account_setup=False):
    source = root / "TeamStats"
    original = source / "TeamStats.xcodeproj/project.pbxproj"
    project = original.read_text()
    test_name = "TeamStatsTests" if account_setup else "TeamStatsUITests"
    if not account_setup:
        project = replace_exact(project, "com.apple.product-type.bundle.unit-test",
                                "com.apple.product-type.bundle.ui-testing", 1)
        project = project.replace("TeamStatsTests", test_name)
    project = replace_exact(project, "PRODUCT_BUNDLE_IDENTIFIER = com.narayanlekhi.TeamStats;",
                            f"PRODUCT_BUNDLE_IDENTIFIER = {APP_ID};", 2)
    if not account_setup:
        project = replace_exact(project, 'BUNDLE_LOADER = "$(TEST_HOST)";',
                                "TEST_TARGET_NAME = TeamStats;", 2)
        host = 'TEST_HOST = "$(BUILT_PRODUCTS_DIR)/TeamStats.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/TeamStats";'
        project = replace_exact(project, host, "", 2)
    if "CC0000000000000000000010" not in project or "PBXFileSystemSynchronizedRootGroup" not in project:
        raise RuntimeError("Expected synchronized test target is unavailable")
    lock = source / "TeamStats.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
    tests = sorted((source / test_name).glob("UIAcceptance*SetupTests.swift")) if account_setup else sorted((source / test_name).glob("*.swift"))
    inputs = [original, lock] + tests + sorted((source / "TeamStats").rglob("*"))
    if any(path.is_symlink() for path in inputs):
        raise RuntimeError("Symlinked inputs are not supported")
    hashes = {str(path.relative_to(root)): hashlib.sha256(path.read_bytes()).hexdigest()
              for path in inputs if path.is_file()}
    shutil.copytree(source / "TeamStats", destination / "TeamStats")
    (destination / test_name).mkdir()
    for test_source in tests:
        shutil.copy2(test_source, destination / test_name / test_source.name)
    copied = destination / "TeamStats.xcodeproj"
    copied.mkdir()
    (copied / "project.pbxproj").write_text(project)
    package = copied / "project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
    package.parent.mkdir(parents=True); shutil.copy2(lock, package)
    scheme = copied / "xcshareddata/xcschemes/TeamStats.xcscheme"
    scheme.parent.mkdir(parents=True)
    app = '<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="8EDFB4AA30777C7C00F9B480" BuildableName="TeamStats.app" BlueprintName="TeamStats" ReferencedContainer="container:TeamStats.xcodeproj"/>'
    test = f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="CC0000000000000000000010" BuildableName="{test_name}.xctest" BlueprintName="{test_name}" ReferencedContainer="container:TeamStats.xcodeproj"/>'
    scheme.write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2640" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{app}</BuildActionEntry></BuildActionEntries></BuildAction>
<TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.PosixSpawn" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO" parallelizable="NO">{test}</TestableReference></Testables></TestAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.PosixSpawn"><BuildableProductRunnable runnableDebuggingMode="0">{app}</BuildableProductRunnable></LaunchAction>
</Scheme>''')
    return hashes


def resolve_paths(value, products):
    if isinstance(value, str):
        return value.replace("__TESTROOT__", str(products))
    if isinstance(value, list):
        return [resolve_paths(item, products) for item in value]
    if isinstance(value, dict):
        return {key: resolve_paths(item, products) for key, item in value.items()}
    return value


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--device", required=True, help="Existing booted simulator UUID")
    parser.add_argument("--only-test", action="append", default=[], help="Class/test method after TeamStatsUITests/")
    parser.add_argument("--package-cache", type=Path, help="Existing Xcode SourcePackages directory")
    parser.add_argument("--prepare-only", action="store_true")
    parser.add_argument("--derived-data", type=Path, help="Reusable dedicated UI-test derived cache; never cleaned")
    parser.add_argument("--account-fixture", type=Path, help="Opt-in actual local account setup in the isolated app host, using an ignored five-field synthetic fixture")
    parser.add_argument("--connected-fixture", type=Path, help="Ignored synthetic names/IDs for actual connected UI navigation; contains no credentials")
    parser.add_argument("--media-fixture", type=Path, help="Ignored synthetic IDs for authorized local clip retention setup in the isolated app host")
    parser.add_argument("--media-ui-fixture", type=Path, help="Ignored synthetic IDs for actual rendered retained-media checks")
    parser.add_argument("--scouting-ui-fixture", type=Path, help="Ignored synthetic IDs for actual published PDF navigation")
    parser.add_argument("--photo-ui-fixture", type=Path, help="Ignored synthetic game/count and observed Photos asset label")
    parser.add_argument("--offline-api-root", help="Exact unavailable loopback API for the full-app offline test; the test verifies unavailability")
    parser.add_argument("--access-phase", choices=["viewer-before-retain", "viewer-revoked", "signout", "owner-restored"], help="Explicit phase after actual operator-controlled local Auth/access changes")
    args = parser.parse_args()
    if args.access_phase and (not args.connected_fixture or not args.media_ui_fixture or args.account_fixture or args.media_fixture):
        parser.error("Access phases require coupled rendered fixtures and no app-host setup")
    if (args.account_fixture and args.media_fixture) or ((args.account_fixture or args.media_fixture) and (args.connected_fixture or args.media_ui_fixture or args.scouting_ui_fixture or args.photo_ui_fixture)):
        parser.error("App-host setup and rendered journeys are separate runs")
    app_host_setup = bool(args.account_fixture or args.media_fixture)
    if not re.fullmatch(r"[0-9A-Fa-f-]{36}", args.device):
        parser.error("Expected a simulator UUID")
    root = Path(__file__).resolve().parents[1]
    output = root / ".scratch/teamstats-completion/native-ui" / datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    if subprocess.run(["git", "-C", str(root), "check-ignore", "--quiet", str(output)],
                      stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode:
        parser.error("Private evidence destination must be ignored by Git")
    output.mkdir(parents=True, mode=0o700)
    env = os.environ.copy(); env["DEVELOPER_DIR"] = DEVELOPER
    env["PATH"] = DEVELOPER + "/usr/bin:" + env.get("PATH", "/usr/bin:/bin")
    evidence = {"device": args.device, "appID": APP_ID, "stages": [], "result": "not run"}

    def run(stage, command, timeout):
        started = time.monotonic()
        timed_out = False
        with (output / (stage + ".local.log")).open("w") as log:
            process = subprocess.Popen(command, env=env, stdout=log, stderr=subprocess.STDOUT)
            try:
                code = process.wait(timeout=timeout)
            except subprocess.TimeoutExpired:
                timed_out = True
                process.send_signal(signal.SIGINT)
                try:
                    code = process.wait(timeout=20)
                except subprocess.TimeoutExpired:
                    process.terminate(); code = process.wait(timeout=10)
                evidence["timedOutStage"] = stage
        evidence["stages"].append({"stage": stage, "exit": code, "seconds": round(time.monotonic() - started, 2)})
        print(f"{stage}: exit {code}", flush=True)
        if timed_out or code:
            raise RuntimeError(stage + " did not pass; inspect the private log/result")

    try:
        evidence["revision"] = subprocess.check_output(["git", "-C", str(root), "rev-parse", "HEAD"], text=True).strip()
        project = output / "project"; project.mkdir()
        evidence["sourceSHA256"] = prepare(root, project, app_host_setup)
        if args.prepare_only:
            evidence["result"] = "prepared only"; return 0
        devices = json.loads(subprocess.check_output(["/usr/bin/xcrun", "simctl", "list", "devices", "booted", "--json"], env=env))
        selected = [(runtime, d) for runtime, entries in devices["devices"].items()
                    for d in entries if d["udid"] == args.device]
        if len(selected) != 1:
            raise RuntimeError("The requested simulator must already be booted")
        evidence.update(runtime=selected[0][0], deviceName=selected[0][1]["name"])
        derived = (args.derived_data or root / ".scratch/teamstats-completion/UI-derived").resolve()
        evidence["derivedData"] = str(derived)
        xcode = DEVELOPER + "/usr/bin/xcodebuild"
        command = [xcode, "build-for-testing", "-project", str(project / "TeamStats.xcodeproj"), "-scheme", "TeamStats", "-destination", "platform=iOS Simulator,id=" + args.device, "-derivedDataPath", str(derived), "-onlyUsePackageVersionsFromResolvedFile"]
        if args.package_cache:
            command += ["-clonedSourcePackagesDirPath", str(args.package_cache.resolve())]
        run("build", command, 1800)
        products = derived / "Build/Products"
        for name in (["TeamStats.app"] if app_host_setup else ["TeamStats.app", "TeamStatsUITests-Runner.app"]):
            run("install-" + name, ["/usr/bin/xcrun", "simctl", "install", args.device, str(products / "Debug-iphonesimulator" / name)], 60)
        run("launch", ["/usr/bin/xcrun", "simctl", "launch", args.device, APP_ID], 60)
        plans = list(products.glob("*.xctestrun"))
        if len(plans) != 1:
            raise RuntimeError("Expected exactly one generated simulator test plan")
        plan = resolve_paths(plistlib.loads(plans[0].read_bytes()), products)
        test_name = "TeamStatsTests" if app_host_setup else "TeamStatsUITests"
        target = plan[test_name]
        target["UseDestinationArtifacts"] = False
        target.setdefault("EnvironmentVariables", {}).update(DEVELOPER_DIR=DEVELOPER, PATH=env["PATH"])
        if args.account_fixture:
            fixture_path = args.account_fixture.resolve()
            if subprocess.run(["git", "-C", str(root), "check-ignore", "--quiet", str(fixture_path)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode:
                raise RuntimeError("Account fixture must stay ignored by Git")
            fixture = json.loads(fixture_path.read_text())
            fields = {"apiRoot", "publishableKey", "syntheticEmail", "syntheticOwnerUUID", "mailpitURL"}
            if set(fixture) != fields:
                raise RuntimeError("Only the five public/synthetic account fields are permitted")
            target["EnvironmentVariables"]["TEAMSTATS_UI_ACCOUNT_FIXTURE"] = json.dumps(fixture)
        if args.connected_fixture:
            fixture_path = args.connected_fixture.resolve()
            if subprocess.run(["git", "-C", str(root), "check-ignore", "--quiet", str(fixture_path)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode:
                raise RuntimeError("Connected fixture must stay ignored by Git")
            fixture = json.loads(fixture_path.read_text())
            if set(fixture) != {"syntheticActorUUID", "teamName", "publishedPlayTitle", "localGameOpponent", "sharedGameOpponent"}:
                raise RuntimeError("Connected fixture permits only synthetic names/IDs")
            target["EnvironmentVariables"]["TEAMSTATS_CONNECTED_UI_FIXTURE"] = json.dumps(fixture)
        if args.media_fixture or args.media_ui_fixture:
            fixture_path = (args.media_fixture or args.media_ui_fixture).resolve()
            if subprocess.run(["git", "-C", str(root), "check-ignore", "--quiet", str(fixture_path)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode:
                raise RuntimeError("Media fixture must stay ignored by Git")
            fixture = json.loads(fixture_path.read_text())
            if set(fixture) != {"syntheticActorUUID", "syntheticTeamID", "syntheticPlayID", "publishedClipVersionID", "publishedClipTitle"}:
                raise RuntimeError("Media fixture permits only synthetic names/IDs")
            if args.connected_fixture and json.loads(target["EnvironmentVariables"]["TEAMSTATS_CONNECTED_UI_FIXTURE"])["syntheticActorUUID"].lower() != fixture["syntheticActorUUID"].lower():
                raise RuntimeError("Rendered fixtures must use the same synthetic actor")
            target["EnvironmentVariables"]["TEAMSTATS_UI_MEDIA_FIXTURE"] = json.dumps(fixture)
        if args.scouting_ui_fixture:
            fixture_path = args.scouting_ui_fixture.resolve()
            if subprocess.run(["git", "-C", str(root), "check-ignore", "--quiet", str(fixture_path)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode:
                raise RuntimeError("Scouting fixture must stay ignored by Git")
            fixture = json.loads(fixture_path.read_text())
            if set(fixture) != {"syntheticActorUUID", "syntheticTeamID", "syntheticGameID", "publishedReportVersionID", "publishedReportTitle"}:
                raise RuntimeError("Scouting fixture permits only synthetic names/IDs")
            if not args.connected_fixture or json.loads(target["EnvironmentVariables"]["TEAMSTATS_CONNECTED_UI_FIXTURE"])["syntheticActorUUID"].lower() != fixture["syntheticActorUUID"].lower():
                raise RuntimeError("Scouting navigation requires the same synthetic actor")
            target["EnvironmentVariables"]["TEAMSTATS_UI_SCOUTING_FIXTURE"] = json.dumps(fixture)
        if args.photo_ui_fixture:
            fixture_path = args.photo_ui_fixture.resolve()
            if subprocess.run(["git", "-C", str(root), "check-ignore", "--quiet", str(fixture_path)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode:
                raise RuntimeError("Photo fixture must stay ignored by Git")
            fixture = json.loads(fixture_path.read_text())
            if set(fixture) != {"gameOpponent", "pickerAssetLabel", "recognizedLine"} or not fixture["gameOpponent"].startswith("TEST ONLY") or fixture["recognizedLine"] != "7":
                raise RuntimeError("Photo fixture permits only a synthetic game/count and observed asset label")
            target["EnvironmentVariables"]["TEAMSTATS_UI_PHOTO_FIXTURE"] = json.dumps(fixture)
        if args.access_phase:
            target["EnvironmentVariables"]["TEAMSTATS_UI_ACCESS_PHASE"] = args.access_phase
        if args.offline_api_root:
            if not args.media_ui_fixture or not re.fullmatch(r"http://127\.0\.0\.1:[0-9]{1,5}", args.offline_api_root):
                raise RuntimeError("Offline checks require the exact loopback media fixture API")
            target["EnvironmentVariables"]["TEAMSTATS_UI_OFFLINE_API_ROOT"] = args.offline_api_root
        manifest = output / "scoped.local.xctestrun"; manifest.write_bytes(plistlib.dumps(plan))
        command = [xcode, "test-without-building", "-xctestrun", str(manifest), "-destination", "platform=iOS Simulator,id=" + args.device, "-parallel-testing-enabled", "NO", "-resultBundlePath", str(output / "acceptance.xcresult")]
        default = ["LocalAcceptanceTests"]
        if args.account_fixture: default = ["UIAcceptanceSetupTests/testPrepareVerifiedLocalAccountForRenderedAcceptance"]
        if args.media_fixture: default = ["UIAcceptanceMediaSetupTests/testRetainExistingApprovedLocalClipForRenderedAcceptance"]
        if args.media_ui_fixture: default = ["ConnectedMediaAcceptanceTests/testActualRetainedVideoControls"]
        if args.connected_fixture: default = ["ConnectedAcceptanceTests/testVerifiedTeamNavigationAndPublishedMovement"]
        selection = args.only_test or default
        for selected in selection:
            command.append("-only-testing:" + test_name + "/" + selected)
        bound = 300 if len(selection) == 1 and "/" in selection[0] else 1800
        evidence.update(tests=selection, testTimeoutSeconds=bound)
        run("test", command, bound)
        evidence["result"] = "test command passed"; return 0
    except (RuntimeError, subprocess.SubprocessError, OSError, KeyError) as error:
        evidence["result"] = "blocked or failed"; evidence["reason"] = str(error)
        print("Harness stopped:", str(error), flush=True); return 1
    finally:
        (output / "evidence.local.json").write_text(json.dumps(evidence, indent=2) + "\n")
        for path in output.rglob("*"):
            path.chmod(path.stat().st_mode & 0o700)
        print("Private evidence:", output, flush=True)


if __name__ == "__main__":
    sys.exit(main())
