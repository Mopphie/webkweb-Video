#!/usr/bin/env python3
"""Portable *non-Apple-SDK* checks. Never claims an iOS build or XCTest passed.

Run from any OS: python Scripts/check-portable.py [--swift-frontend PATH].
Writes raw TAP and a machine-readable local report under ignored build/reports/.
No network, GitHub Actions, credentials, signing, simulator, or uploads.
"""
from __future__ import annotations
import argparse, ast, datetime, json, plistlib, re, shutil, subprocess, sys
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
REPORT=ROOT/'build'/'reports'


def command(args):
    return subprocess.run([str(a) for a in args],cwd=ROOT,text=True,capture_output=True)


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--swift-frontend',help='Optional Swift frontend for syntax-only parsing (never Apple SDK typechecking)')
    args=parser.parse_args()
    REPORT.mkdir(parents=True,exist_ok=True)
    checks=[]
    def record(name,status,detail):checks.append({'check':name,'status':status,'detail':detail})

    node=shutil.which('node')
    tests=sorted((ROOT/'Tests').glob('*.test.cjs'))
    if not node or not tests:record('JavaScript tests','FAIL','Node or .test.cjs files missing')
    else:
        result=command([node,'--test',*tests])
        (REPORT/'node-tests.tap').write_text(result.stdout+result.stderr,encoding='utf8')
        pass_match=re.search(r'\bpass\s+(\d+)',result.stdout)
        fail_match=re.search(r'\bfail\s+(\d+)',result.stdout)
        count_match=re.search(r'\btests\s+(\d+)',result.stdout)
        status='PASS' if result.returncode==0 and pass_match and fail_match and int(fail_match[1])==0 else 'FAIL'
        record('JavaScript tests',status,{'passed':int(pass_match[1]) if pass_match else None,
             'total':int(count_match[1]) if count_match else None,'exit':result.returncode,'raw':str(REPORT/'node-tests.tap')})

    swift_files=sorted(p for section in ('App','Shared','Widgets','Tests') for p in (ROOT/section).rglob('*.swift'))
    frontend=args.swift_frontend or shutil.which('swift-frontend')
    if frontend:
        errors=[]
        for path in swift_files:
            for mode in ([],['-D','WEBKWEB_NO_DOWNLOADS']):
                result=command([frontend,'-frontend','-parse',*mode,path])
                if result.returncode:errors.append({'file':str(path.relative_to(ROOT)),'mode':mode or ['Debug'],
                                                     'diagnostic':(result.stderr+result.stdout)[:1200]})
        record('Swift syntax only','FAIL' if errors else 'PASS',{'checked':len(swift_files),'errors':errors,
               'modes':['Debug','Release no-downloads'],
               'note':'Parser does not typecheck SwiftUI, WebKit, SDK or XCTest.'})
    else:record('Swift syntax only','NOT_RUN',{'checked':0,'available':len(swift_files)})

    resource_files=sorted(ROOT.rglob('*.plist'))+sorted(ROOT.rglob('*.xcprivacy'))
    plist_errors=[]
    for path in resource_files:
        try:plistlib.loads(path.read_bytes())
        except Exception as exc:plist_errors.append(f'{path.relative_to(ROOT)}: {exc}')
    record('Plist and privacy manifest parse','FAIL' if plist_errors else 'PASS',
           {'checked':len(resource_files),'errors':plist_errors})
    try:
        app=plistlib.loads((ROOT/'App'/'WebKWeb.entitlements').read_bytes())
        widget=plistlib.loads((ROOT/'Widgets'/'FavoritesWidget.entitlements').read_bytes())
        group='com.apple.security.application-groups'
        assert app[group]==widget[group] and len(app[group])==1
        assert 'com.apple.developer.icloud-container-identifiers' not in app
        record('Unprovisioned iCloud disabled and matching App Groups','PASS','Source configuration only; not an Apple entitlement/provisioning verification')
    except (AssertionError,KeyError) as exc:
        record('Unprovisioned iCloud disabled and matching App Groups','FAIL',repr(exc))
    try:
        import yaml
        project=yaml.safe_load((ROOT/'project.yml').read_text(encoding='utf8'))
        assert int(project['options']['xcodeVersion'].split('.')[0])>=26
        assert project['targets']['WebKWeb']['settings']['base']['PRODUCT_BUNDLE_IDENTIFIER']
        record('Project YAML parse and Xcode minimum','PASS','XcodeGen generation/build NOT performed')
        flag='WEBKWEB_NO_DOWNLOADS'
        app_release=project['targets']['WebKWeb']['settings']['configs']['Release']['SWIFT_ACTIVE_COMPILATION_CONDITIONS']
        tests_release=project['targets']['WebKWebTests']['settings']['configs']['Release']['SWIFT_ACTIVE_COMPILATION_CONDITIONS']
        guarded=[ROOT/p for p in ('App/Downloads.swift','App/BrowserView.swift','App/PlayerViews.swift','Tests/QueueTests.swift')]
        assert flag in app_release and flag in tests_release and all(flag in p.read_text(encoding='utf8') for p in guarded)
        record('Release no-downloads source configuration','PASS','Build flag/source guards verified; a Mac binary build remains required')
    except ImportError:record('Project YAML parse and Xcode minimum','NOT_RUN','PyYAML not available')
    except Exception as exc:record('Project YAML parse and Xcode minimum','FAIL',str(exc))

    try:
        ast.parse((ROOT/'Scripts'/'configure-cloudkit.py').read_text(encoding='utf8'))
        record('CloudKit helper Python syntax','PASS','No container configured')
    except SyntaxError as exc:record('CloudKit helper Python syntax','FAIL',str(exc))
    bash=shutil.which('bash')
    if bash:
        result=command([bash,'-n',ROOT/'Scripts'/'check-macos.sh'])
        record('macOS script shell syntax','PASS' if result.returncode==0 else 'FAIL',result.stderr[:1200])
    else:record('macOS script shell syntax','NOT_RUN','Bash not installed')

    definitions=sum(len(re.findall(r'\bfunc\s+test\w+\s*\(',p.read_text(encoding='utf8'))) for p in (ROOT/'Tests').glob('*.swift'))
    record('Native XCTest definitions','NOT_RUN',{'definitions':definitions,'reason':'Requires Mac, Xcode 26, iOS simulator/device'})
    info=plistlib.loads((ROOT/'App'/'Info.plist').read_bytes())
    missing=[k for k in ('WebKWebPrivacyURL','WebKWebSupportURL','WebKWebOperatorContact') if not info.get(k)]
    record('Public release contacts','BLOCKED',{'empty_keys':missing} if missing else 'Bundle fields populated; manually verify real public endpoints')
    now=datetime.datetime.now().astimezone().isoformat(timespec='seconds')
    report={'created_at':now,'os':sys.platform,'checks':checks,'native_build':'NOT_RUN',
            'xctest':'NOT_RUN','signed_archive':'NOT_CREATED','github_actions':'NOT_USED'}
    target=REPORT/'portable-check.json'
    target.write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf8')
    for check in checks:print(f"{check['status']}: {check['check']} – {check['detail']}")
    print(f'REPORT {target}')
    return 1 if any(c['status']=='FAIL' for c in checks) else 0

if __name__=='__main__':raise SystemExit(main())
