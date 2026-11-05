"""Frozen, version-matched A/B diagnostics. Never installs a product app."""
from pathlib import Path
import subprocess, shutil, argparse

root = Path(__file__).resolve().parents[2]
p = argparse.ArgumentParser()
p.add_argument('modes', nargs='+', choices=['normal', 'activity', 'ack', 'rate20', 'rate40', 'balanced', 'maxbalanced'])
a = p.parse_args()
version = (root/'VERSION').read_text().strip()
folder = root/'build'/('tuning-'+version)
baseline = folder/'baseline-source'
ui = (root/'Sources/UI.swift').read_text()
ui = ui.replace('private var frames = 0', 'var diagnosticCaptures = 0, diagnosticDrops = 0, diagnosticEncoded = 0\n    private var frames = 0', 1)
ui = ui.replace('self.videoBytes += data.count', 'self.diagnosticEncoded += 1; self.videoBytes += data.count', 1)
ui = ui.replace('self.busy = false; self.encodeLatest(); self.applyWhenDrained()', 'self.diagnosticDrops += 1; self.busy = false; self.encodeLatest(); self.applyWhenDrained()', 1)
ui = ui.replace('self.latest.offer((pixel, monotonicNS()))', 'self.diagnosticCaptures += 1; self.latest.offer((pixel, monotonicNS()))', 1)
main = (root/'Tests/Investigate/Sender/main.swift').read_text().replace('engine.stop()', 'engine.queue.sync { print("PIPELINE captures=\\(engine.diagnosticCaptures) encoded=\\(engine.diagnosticEncoded) drops=\\(engine.diagnosticDrops)") }\nengine.stop()', 1)
for mode in a.modes:
    source = folder/mode
    source.mkdir(parents=True, exist_ok=True)
    shutil.copytree(root/'Sources', source/'Sources', dirs_exist_ok=True)
    variant = ui
    if mode != 'activity':
        variant = variant.replace('self.streamActivity.start();', '')
    if mode in ('balanced', 'maxbalanced'):
        variant = variant.replace('? 32 : nil', '? 36 : nil')
    (source/'Sources/UI.swift').write_text(variant)
    protocol = (baseline/'Protocol.swift').read_text()
    if mode == 'ack':
        protocol = protocol.replace('tcp.noDelay = true;', 'tcp.noDelay = true; tcp.disableAckStretching = true;')
    (source/'Sources/Protocol.swift').write_text(protocol)
    latency = (baseline/'Latency.swift').read_text()
    if mode in ('rate20', 'balanced', 'rate40', 'maxbalanced'):
        start = 40_000_000 if mode in ('rate40', 'maxbalanced') else 20_000_000
        latency = latency.replace('ceiling >= 20_000_000 ? 12_000_000 : 6_000_000', 'ceiling >= 20_000_000 ? '+str(start)+' : 6_000_000')
    (source/'Sources/Latency.swift').write_text(latency)
    (source/'main.swift').write_text(main)
    common = [str(source/'Sources'/x) for x in ['DesktopControl.swift', 'Recovery.swift', 'Preferences.swift', 'Protocol.swift', 'Cursor.swift', 'Pairing.swift', 'Pointer.swift', 'Latency.swift', 'Video.swift', 'UI.swift']] + [str(root/'build/Version.swift')]
    args = ['xcrun','swiftc','-module-cache-path',str(root/'build/ModuleCache'),'-swift-version','5','-O']
    tag = 'tune-'+mode
    subprocess.run(args+['-target','arm64-apple-macosx13.0','-D','SENDER','-D','DIAGNOSTIC_SCENE']+common+[str(source/'Sources/Capture.swift'),str(root/'build/VirtualDisplay-arm64.o'),'-import-objc-header',str(source/'Sources/VirtualDisplay.h'),str(root/'Tests/Investigate/Scene.swift'),str(source/'main.swift'),'-o',str(root/'build'/('PerfSender-'+tag))],check=True)
    subprocess.run(args+['-target','x86_64-apple-macosx10.15','-D','REAL_ROUTE_DIAGNOSTIC']+common+[str(root/'Tests/Investigate/RealReceiver/main.swift'),'-o',str(root/'build'/('RealReceiver-'+tag))],check=True)
    subprocess.run(['python3',str(root/'Tests/Investigate/bundle.py'),tag,version,'PerfSender-'+tag,'RealReceiver-'+tag],check=True)
    print('BUILT',tag,flush=True)
