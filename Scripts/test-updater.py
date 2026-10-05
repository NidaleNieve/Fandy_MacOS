#!/usr/bin/env python3
"""Local signed Sparkle fixture; never registers a fan helper or uses Fandy data."""
from pathlib import Path
import sys, importlib.util, json, plistlib, subprocess, tempfile, threading, http.server, functools, time, re, uuid
root=Path(__file__).resolve().parent.parent
spec=importlib.util.spec_from_file_location('dist',root/'Scripts/distribute.py'); dist=importlib.util.module_from_spec(spec);spec.loader.exec_module(dist)
corrupt = '--corrupt' in sys.argv
manual = '--manual' in sys.argv
pending = '--install-pending' in sys.argv
fallback = '--fallback-installer' in sys.argv
notarized = '--notarize-fixture' in sys.argv
# This fixture has no fan helper and uses a separate defaults domain.
subprocess.run(['xcrun','swiftc','-swift-version','6','-F',str(root/'build/SparkleTools'),'-framework','Sparkle','-framework','AppKit',str(root/'Sources/FandyApp/AcceptedUpdateDriver.swift'),str(root/'Tests/UpdaterIntegration/Fixture.swift'),'-o',str(root/'build/SparkleTools/UpdateFixture'),'-Xlinker','-rpath','-Xlinker','@executable_path/../Frameworks'],check=True)
evidence=root/('build/UpdaterTamperQualification' if corrupt else 'build/UpdaterPendingQualification' if pending else 'build/UpdaterManualQualification' if manual else 'build/UpdaterQualification');evidence.mkdir(exist_ok=True)
# Install fixtures outside Documents/FileProvider scope and isolate each run.
work=Path(tempfile.mkdtemp(prefix='fandy-updater-test-',dir='/private/tmp'))
requests=[]
class Quiet(http.server.SimpleHTTPRequestHandler):
 def log_message(self,*a): pass
 def do_GET(self):
  requests.append(self.path);super().do_GET()
server=http.server.ThreadingHTTPServer(('127.0.0.1',0),functools.partial(Quiet,directory=str(work)))
threading.Thread(target=server.serve_forever,daemon=True).start()
port=server.server_address[1];identity=dist.developer_identity()
fixture_id='is.dsr.fandy.update-fixture.'+uuid.uuid4().hex
current=work/'current/FandyUpdaterFixture.app';nextapp=work/'next/FandyUpdaterFixture.app'
for app,version in [(current,'11'),(nextapp,'12')]:
 (app/'Contents/MacOS').mkdir(parents=True,exist_ok=True);(app/'Contents/Frameworks').mkdir(exist_ok=True)
 subprocess.run(['ditto',str(root/'build/SparkleTools/UpdateFixture'),str(app/'Contents/MacOS/UpdateFixture')],check=True)
 subprocess.run(['ditto',str(root/'build/SparkleTools/Sparkle.framework'),str(app/'Contents/Frameworks/Sparkle.framework')],check=True)
 info=dict(CFBundleIdentifier=fixture_id,CFBundleExecutable='UpdateFixture',CFBundleName='FandyUpdaterFixture',CFBundleVersion=version,CFBundleShortVersionString='0.2.'+version,CFBundlePackageType='APPL',LSMinimumSystemVersion='15.0',LSUIElement=True,SUFeedURL=f'http://127.0.0.1:{port}/appcast.xml',SUPublicEDKey='r1rhWlckhD4L2XF7jj3KacSd85dJHO3VKeR7bTRGbK8=',SUEnableAutomaticChecks=True,SUAutomaticallyUpdate=not manual,FandyFixtureManualCheck=manual,FandyFixtureInstallPending=pending,SUEnableSystemProfiling=False,SUVerifyUpdateBeforeExtraction=True,SUScheduledCheckInterval=604800,SUScheduledImpatientCheckInterval=1209600,NSAppTransportSecurity={'NSAllowsArbitraryLoads':True})
 (app/'Contents/Info.plist').write_bytes(plistlib.dumps(info))
 dist.sign_updater(app,identity)
 if fallback:
  # Isolated fixture only: exercise Sparkle's supported non-atomic fallback.
  # A distinct installer identity prevents atomic exchange on this host.
  subprocess.run(['codesign','--force','--sign','-','--options','runtime',str(app/'Contents/Frameworks/Sparkle.framework/Versions/B/Autoupdate')],check=True,capture_output=True)
  dist.sign(app/'Contents/Frameworks/Sparkle.framework',identity,'org.sparkle-project.Sparkle')
 dist.sign(app,identity,fixture_id);dist.PACKAGE.run(['codesign','--verify','--deep','--strict',app])
 if notarized:
  submission=work/('current.zip' if version=='11' else 'next.zip')
  subprocess.run(['ditto','-c','-k','--keepParent',str(app),str(submission)],check=True)
  dist.notarize(submission,'FandyNotary')
  dist.PACKAGE.run(['xcrun','stapler','staple',app])
  dist.PACKAGE.run(['spctl','--assess','--type','execute',app])
archive=work/'fixture.zip';subprocess.run(['ditto','-c','-k','--keepParent',str(nextapp),str(archive)],check=True)
signed=subprocess.run([str(root/'build/SparkleTools/bin/sign_update'),'--account','is.dsr.fandy',str(archive)],capture_output=True,text=True,check=True,timeout=120).stdout
signature=re.search(r'sparkle:edSignature="([^"]+)"',signed)[1]
if corrupt:
 data=bytearray(archive.read_bytes());data[len(data)//2]^=1;archive.write_bytes(data)
xml=f'''<?xml version="1.0" encoding="utf-8"?><rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><title>Isolated test</title><item><title>Test build 12</title><sparkle:version>12</sparkle:version><sparkle:shortVersionString>0.2.12</sparkle:shortVersionString><sparkle:minimumSystemVersion>15.0</sparkle:minimumSystemVersion><enclosure url="http://127.0.0.1:{port}/fixture.zip" length="{archive.stat().st_size}" type="application/octet-stream" sparkle:edSignature="{signature}"/></item></channel></rss>'''
(work/'appcast.xml').write_text(xml)
log=work/'integration.log'
with log.open('w') as out:
 p=subprocess.Popen([str(current/'Contents/MacOS/UpdateFixture')],stdout=out,stderr=out)
 try: code=p.wait(timeout=60)
 except subprocess.TimeoutExpired: p.terminate();raise RuntimeError('Fixture timeout')
deadline=time.monotonic()+(0 if corrupt else 45)
while time.monotonic()<deadline:
 if plistlib.loads((current/'Contents/Info.plist').read_bytes())['CFBundleVersion']=='12': break
 time.sleep(.25)
text=log.read_text();updated=plistlib.loads((current/'Contents/Info.plist').read_bytes())['CFBundleVersion']=='12'
report={'fixtureOnly':True,'notarizedFixture':notarized,'fallbackInstaller':fallback,'productionDefaultsUntouched':True,'containsFanHelper':False,'archiveSigned':True,'exitCode':code,'archiveRequested': '/fixture.zip' in requests, 'feedRequested': '/appcast.xml' in requests,'manualCheck':manual,'resumedStagedUpdate':'install-staged-without-prompt' in text,'singleConfirmation': 'ready-without-second-confirmation' in text,'installOnQuit':'pending-on-quit' in text,'quitBoundary':'quit-boundary' in text,'replacedBuild12':updated,'tamperedArchiveRejected':corrupt and ('rejected:' in text or 'error:' in text) and not updated}
(evidence/'integration.log').write_text(text)
(evidence/'report.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report));server.shutdown()
if corrupt:
 if code!=2 or updated or '/fixture.zip' not in requests: raise SystemExit(1)
elif code or not updated or '/fixture.zip' not in requests or (manual and 'ready-without-second-confirmation' not in text) or (pending and 'install-staged-without-prompt' not in text): raise SystemExit(1)
