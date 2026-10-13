#!/usr/bin/env python3
"""Configure an existing, provisioned container; no generated/demo Apple identity."""
import argparse, plistlib, re
from pathlib import Path
p=argparse.ArgumentParser()
p.add_argument('--container', required=True, help='Existing iCloud container from your Apple Developer account')
a=p.parse_args()
if not re.fullmatch(r'iCloud\.[A-Za-z0-9.-]+',a.container): p.error('Expected an existing iCloud.* container identifier')
root=Path(__file__).resolve().parent.parent
info=root/'App/Info.plist'
with info.open('rb') as f: data=plistlib.load(f)
data['WebKWebCloudKitContainer']=a.container
modes=data.setdefault('UIBackgroundModes',[])
if 'remote-notification' not in modes: modes.append('remote-notification')
with info.open('wb') as f: plistlib.dump(data,f)
entitlements=root/'App/WebKWeb.entitlements'
with entitlements.open('rb') as f: data=plistlib.load(f)
data['com.apple.developer.icloud-container-identifiers']=[a.container]
data['com.apple.developer.icloud-services']=['CloudKit']
data['aps-environment']='$(APS_ENVIRONMENT)'
with entitlements.open('wb') as f: plistlib.dump(data,f)
print('Configured',a.container,'in app plist/entitlements. Enable iCloud+Push capabilities and App Group for your team, regenerate project and provision the app. Then enable sync in Settings and restart.')
