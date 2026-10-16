#!/usr/bin/env python3
"""Validate two decoded distribution profiles and write export options (macOS only).

Never logs certificate, private key, password, or profile contents. Inputs are
runner-local temporary files; UUIDs are emitted as GitHub step outputs.
"""
import datetime
import hashlib
import os
import plistlib
import subprocess
import sys
from pathlib import Path

TEAM = 'HUN9MS832X'
GROUP = 'group.de.mopphie.devntube'
BUNDLES = ('de.mopphie.devntube', 'de.mopphie.devntube.favorites')


def fail(message):
    raise SystemExit('Signing preflight failed: ' + message)


def profile(path, bundle, certificate_hash):
    try:
        decoded = subprocess.check_output(['security', 'cms', '-D', '-i', str(path)], stderr=subprocess.DEVNULL)
        data = plistlib.loads(decoded)
        ent = data['Entitlements']
        assert data['TeamIdentifier'] == [TEAM]
        assert ent['application-identifier'] == TEAM + '.' + bundle
        assert ent['com.apple.developer.team-identifier'] == TEAM
        assert ent['com.apple.security.application-groups'] == [GROUP]
        assert ent['get-task-allow'] is False
        assert 'ProvisionedDevices' not in data and not data.get('ProvisionsAllDevices')
        assert data['ExpirationDate'] > datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None)
        assert certificate_hash in {hashlib.sha256(c).hexdigest() for c in data['DeveloperCertificates']}
        uuid = data['UUID']
        assert isinstance(uuid, str) and uuid
        return uuid
    except (AssertionError, KeyError, TypeError, ValueError, subprocess.CalledProcessError) as exc:
        fail('invalid/expired profile or certificate mismatch for ' + bundle + ' (' + type(exc).__name__ + ')')


def main():
    if len(sys.argv) != 5:
        fail('expected app and widget profiles, certificate p12, output directory')
    app, widget, p12, out = map(Path, sys.argv[1:])
    try:
        pem = subprocess.check_output(
            ['openssl', 'pkcs12', '-in', str(p12), '-clcerts', '-nokeys',
             '-passin', 'env:APPLE_CERTIFICATE_PASSWORD'], stderr=subprocess.DEVNULL)
        der = subprocess.check_output(['openssl', 'x509', '-outform', 'DER'], input=pem,
                                      stderr=subprocess.DEVNULL)
    except subprocess.CalledProcessError:
        fail('distribution certificate/password is unusable')
    certificate_hash = hashlib.sha256(der).hexdigest()
    uuids = [profile(path, bundle, certificate_hash)
             for path, bundle in zip((app, widget), BUNDLES)]
    if len(set(uuids)) != len(BUNDLES):
        fail('app and widget must use separate profiles')
    options = {'method': 'app-store-connect', 'destination': 'export',
               'manageAppVersionAndBuildNumber': False,
               'signingStyle': 'manual', 'teamID': TEAM,
               'signingCertificate': 'Apple Distribution',
               'provisioningProfiles': dict(zip(BUNDLES, uuids))}
    out.mkdir(parents=True, exist_ok=True)
    with (out / 'ExportOptions.plist').open('wb') as f:
        plistlib.dump(options, f)
    with Path(os.environ['GITHUB_OUTPUT']).open('a', encoding='utf-8') as f:
        f.write('app_uuid=' + uuids[0] + '\nwidget_uuid=' + uuids[1] + '\n')
    print('Signing preflight passed for separate app and widget distribution profiles.')


if __name__ == '__main__':
    main()
