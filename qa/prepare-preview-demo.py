"""Package an isolated, in-memory preview demo from a Debug build."""
import pathlib
import plistlib
import shutil
import subprocess
import sys

source = pathlib.Path(sys.argv[1]).resolve()
if not (source / "Contents" / "MacOS" / "Maccy.debug.dylib").is_file():
    raise SystemExit("A Debug build is required for the isolated, in-memory demo.")
output = pathlib.Path(__file__).resolve().parent / "artifacts" / "Applications.noindex" / "Maccy预览测试.app"
if output.exists():
    raise SystemExit(f"Demo already exists: {output}")
output.parent.mkdir(parents=True, exist_ok=True)
shutil.copytree(source, output, symlinks=True)
info = output / "Contents" / "Info.plist"
properties = plistlib.loads(info.read_bytes())
properties.update(CFBundleIdentifier="today.findspring.MaccyPreview",
                  CFBundleName="Maccy Preview", CFBundleDisplayName="Maccy 预览测试")
info.write_bytes(plistlib.dumps(properties))
subprocess.run(["swift", str(pathlib.Path(__file__).with_name("generate-preview-fixtures.swift")),
                str(output / "Contents" / "Resources" / "PreviewFixtures")], check=True)
subprocess.run(["codesign", "--force", "--deep", "--sign", "-", str(output)], check=True)
subprocess.run(["codesign", "--verify", "--deep", "--strict", str(output)], check=True)
print(output)
