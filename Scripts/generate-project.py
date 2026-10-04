#!/usr/bin/env python3
"""Small deterministic Xcode project; no generator dependency or downloaded code."""
from pathlib import Path
import hashlib,json,subprocess
root=Path(__file__).resolve().parent.parent
objects={}
# Preserve the signing choices made in Xcode when adding/regenerating source references.
project_path=root/'Fandy.xcodeproj/project.pbxproj'
previous_objects={}
if project_path.exists():
 converted=subprocess.run(['plutil','-convert','json','-o','-',str(project_path)],check=True,capture_output=True,text=True)
 previous_objects=json.loads(converted.stdout)['objects']
signing_keys={'DEVELOPMENT_TEAM','CODE_SIGN_IDENTITY','CODE_SIGN_STYLE','PROVISIONING_PROFILE','PROVISIONING_PROFILE_SPECIFIER','CODE_SIGN_ENTITLEMENTS'}
def preserve_local_signing(name,kind,previous):
 # Migrate Xcode's inline selections to ignored, per-configuration includes.
 # Build configuration remains effective locally without publishing identity/profile values.
 folder=root/'Config/Signing';folder.mkdir(parents=True,exist_ok=True)
 defaults=root/'Config/Signing.xcconfig'
 if not defaults.exists():
  defaults.write_text('CODE_SIGN_STYLE = Automatic\nCODE_SIGN_IDENTITY = Apple Development\n#include? "Signing.local.xcconfig"\n')
 filename=f'{name}.{kind}.xcconfig'
 (folder/filename).write_text(f'#include "../Signing.xcconfig"\n#include? "{name}.{kind}.local.xcconfig"\n')
 selected={key:val for key,val in previous.items() if key.split('[')[0] in signing_keys}
 if selected:
  private=folder/f'{name}.{kind}.local.xcconfig'
  existing=private.read_text() if private.exists() else '// Private signing selections. Do not commit.\n'
  lines=[]
  for key,val in sorted(selected.items()):
   if not isinstance(val,str) or any(c in key+val for c in '\r\n'):
    raise ValueError('Unsupported signing setting; leave the existing project unchanged')
   lines.append(f'{key} = {val}\n')
  private.write_text(existing+''.join(lines));private.chmod(0o600)
 return str((folder/filename).relative_to(root))
def uid(name): return hashlib.sha256(name.encode()).hexdigest()[:24].upper()
def add(key,isa,**fields):
 ident=uid(key);objects[ident]={'isa':isa,**fields};return ident
# OpenStep plist serializer: references are bare IDs, strings are quoted.
def value(v,level=0):
 pad='\t'*(level+1);close='\t'*level
 if isinstance(v,dict):
  if not v:return '{}'
  return '{\n'+''.join(f'{pad}{json.dumps(k)} = {value(x,level+1)};\n' for k,x in v.items())+close+'}'
 if isinstance(v,list):
  if not v:return '()'
  return '(\n'+''.join(pad+value(x,level+1)+',\n' for x in v)+close+')'
 if isinstance(v,int):return str(v)
 if v in objects or (len(v)==24 and all(c in '0123456789ABCDEF' for c in v)):return v
 return json.dumps(v)
files={}
for path in sorted(root.glob('Sources/**/*.swift')):
 rel=str(path.relative_to(root));files[rel]=add(rel,'PBXFileReference',lastKnownFileType='sourcecode.swift',path=rel,sourceTree='<group>')
plist=add('launchd-plist','PBXFileReference',lastKnownFileType='text.plist.xml',path='Config/is.dsr.fandy.fan-helper.plist',sourceTree='<group>')
notices=add('notices','PBXFileReference',lastKnownFileType='text',path='THIRD_PARTY_NOTICES.md',sourceTree='<group>')
licenses=add('licenses','PBXFileReference',lastKnownFileType='folder',path='docs/licenses',sourceTree='<group>')
info=add('app-plist','PBXFileReference',lastKnownFileType='text.plist.xml',path='Config/App-Info.plist',sourceTree='<group>')
appProduct=add('app-product','PBXFileReference',explicitFileType='wrapper.application',path='Fandy.app',sourceTree='BUILT_PRODUCTS_DIR')
helperProduct=add('helper-product','PBXFileReference',explicitFileType='compiled.mach-o.executable',path='FandyFanHelper',sourceTree='BUILT_PRODUCTS_DIR')
products=add('products','PBXGroup',children=[appProduct,helperProduct],name='Products',sourceTree='<group>')
main=add('main-group','PBXGroup',children=list(files.values())+[plist,info,notices,licenses,products],sourceTree='<group>')
package=add('package','XCLocalSwiftPackageReference',relativePath='.')
projectID=uid('project');helperID=uid('helper-target')
common={'MACOSX_DEPLOYMENT_TARGET':'15.0','SDKROOT':'macosx','ARCHS':'arm64','SWIFT_VERSION':'6.0','CLANG_ENABLE_MODULES':'YES','ENABLE_HARDENED_RUNTIME':'YES','ENABLE_APP_SANDBOX':'NO','CODE_SIGN_INJECT_BASE_ENTITLEMENTS':'NO','SWIFT_STRICT_CONCURRENCY':'complete'}
def configs(name,extra):
 refs=[]
 for kind in ['Debug','Release']:
  settings={**common,**extra,'SWIFT_OPTIMIZATION_LEVEL':'-Onone' if kind=='Debug' else '-O','DEBUG_INFORMATION_FORMAT':'dwarf' if kind=='Debug' else 'dwarf-with-dsym','SWIFT_ACTIVE_COMPILATION_CONDITIONS':'DEBUG' if kind=='Debug' else ''}
  previous=previous_objects.get(uid(name+'-'+kind),{}).get('buildSettings',{})
  signing=preserve_local_signing(name,kind,previous)
  reference=add('signing-'+name+'-'+kind,'PBXFileReference',lastKnownFileType='text.xcconfig',path=signing,sourceTree='<group>')
  objects[main]['children'].append(reference)
  refs.append(add(name+'-'+kind,'XCBuildConfiguration',buildSettings=settings,baseConfigurationReference=reference,name=kind))
 return add(name+'-configs','XCConfigurationList',buildConfigurations=refs,defaultConfigurationIsVisible=0,defaultConfigurationName='Debug')
projectConfigs=configs('project',{})
targets=[]
for name,folder,product,ptype,bundle in [('Fandy','FandyApp',appProduct,'com.apple.product-type.application','is.dsr.fandy'),('FandyFanHelper','FandyHelper',helperProduct,'com.apple.product-type.tool','is.dsr.fandy.fan-helper')]:
 targetID=uid('app-target' if folder=='FandyApp' else 'helper-target')
 sourceBuild=[add('build-'+rel,'PBXBuildFile',fileRef=ref) for rel,ref in files.items() if rel.startswith('Sources/'+folder+'/')]
 sources=add(name+'-sources','PBXSourcesBuildPhase',buildActionMask=2147483647,files=sourceBuild,runOnlyForDeploymentPostprocessing=0)
 dependencies=[];packageDeps=[];frameworkBuild=[]
 for lib in ['FandyCore','FandyHardware']:
  dep=add(name+'-'+lib,'XCSwiftPackageProductDependency',package=package,productName=lib);packageDeps.append(dep)
  frameworkBuild.append(add(name+'-link-'+lib,'PBXBuildFile',productRef=dep))
 frameworks=add(name+'-frameworks','PBXFrameworksBuildPhase',buildActionMask=2147483647,files=frameworkBuild,runOnlyForDeploymentPostprocessing=0)
 phases=[sources,frameworks]
 extra={'PRODUCT_NAME':name,'PRODUCT_BUNDLE_IDENTIFIER':bundle,'SKIP_INSTALL':'NO'}
 if folder=='FandyApp':
  extra.update({'INFOPLIST_FILE':'Config/App-Info.plist','GENERATE_INFOPLIST_FILE':'NO'})
  noticebuild=add('notice-build','PBXBuildFile',fileRef=notices)
  licensebuild=add('license-build','PBXBuildFile',fileRef=licenses)
  phases.append(add('app-resources','PBXResourcesBuildPhase',buildActionMask=2147483647,files=[noticebuild,licensebuild],runOnlyForDeploymentPostprocessing=0))
  phases.append(add('app-icon','PBXShellScriptBuildPhase',buildActionMask=2147483647,files=[],
      inputPaths=['$(SRCROOT)/Scripts/generate-icon.swift'],
      outputPaths=['$(TARGET_BUILD_DIR)/$(UNLOCALIZED_RESOURCES_FOLDER_PATH)/Fandy.icns'],
      name='Generate App Icon',shellPath='/bin/sh',
      shellScript='xcrun swift -module-cache-path "$TARGET_TEMP_DIR/IconModuleCache" "$SRCROOT/Scripts/generate-icon.swift" "$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/Fandy.icns"\n',
      runOnlyForDeploymentPostprocessing=0))
  proxy=add('helper-proxy','PBXContainerItemProxy',containerPortal=projectID,proxyType=1,remoteGlobalIDString=helperID,remoteInfo='FandyFanHelper')
  dependencies=[add('helper-dependency','PBXTargetDependency',target=helperID,targetProxy=proxy)]
  embed=add('helper-embed','PBXBuildFile',fileRef=helperProduct,settings={'ATTRIBUTES':['CodeSignOnCopy']})
  plistbuild=add('plist-build','PBXBuildFile',fileRef=plist)
  for what,path,build in [('Helper','Contents/Library/HelperTools',embed),('Launch Daemon','Contents/Library/LaunchDaemons',plistbuild)]:
   phases.append(add('copy-'+what,'PBXCopyFilesBuildPhase',buildActionMask=2147483647,dstPath=path,dstSubfolderSpec=1,files=[build],name='Embed '+what,runOnlyForDeploymentPostprocessing=0))
 else:extra.update({'OTHER_CODE_SIGN_FLAGS':'--identifier is.dsr.fandy.fan-helper','INSTALL_PATH':'/usr/local/libexec'})
 configsID=configs(name,extra)
 add('app-target' if folder=='FandyApp' else 'helper-target','PBXNativeTarget',buildConfigurationList=configsID,buildPhases=phases,buildRules=[],dependencies=dependencies,name=name,packageProductDependencies=packageDeps,productName=name,productReference=product,productType=ptype)
 targets.append(targetID)
add('project','PBXProject',attributes={'BuildIndependentTargetsInParallel':'YES','LastUpgradeCheck':'2700'},buildConfigurationList=projectConfigs,compatibilityVersion='Xcode 16.0',developmentRegion='en',hasScannedForEncodings=0,knownRegions=['en','Base'],mainGroup=main,productRefGroup=products,projectDirPath='',projectRoot='',packageReferences=[package],targets=targets)
folder=root/'Fandy.xcodeproj';folder.mkdir(exist_ok=True)
(folder/'project.pbxproj').write_text('// !$*UTF8*$!\n'+value({'archiveVersion':1,'classes':{},'objectVersion':77,'objects':objects,'rootObject':projectID})+'\n')
schemes=folder/'xcshareddata/xcschemes';schemes.mkdir(parents=True,exist_ok=True)
(schemes/'Fandy.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2700" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{uid('app-target')}" BuildableName="Fandy.app" BlueprintName="Fandy" ReferencedContainer="container:Fandy.xcodeproj"/></BuildActionEntry></BuildActionEntries></BuildAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="YES" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="NO"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{uid('app-target')}" BuildableName="Fandy.app" BlueprintName="Fandy" ReferencedContainer="container:Fandy.xcodeproj"/></BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release"/><AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>''')
print('Generated Fandy.xcodeproj')
