#!/usr/bin/env python3
"""Authorized runner-local Share signing setup using public ASC/Xcode interfaces.

No credential/profile output, revocation, new App Group, or account/contract changes.
The existing distribution certificate must match. Xcode may create signing assets
needed by this extension; all runner-local keys and profiles are removed by CI.
"""
import argparse
import base64
import hashlib
import importlib.util
import os
from pathlib import Path
import subprocess
import sys
import tempfile

spec = importlib.util.spec_from_file_location('asc', Path(__file__).with_name('app-store-connect.py'))
asc = importlib.util.module_from_spec(spec)
spec.loader.exec_module(asc)
signing_spec = importlib.util.spec_from_file_location('signing', Path(__file__).with_name('ci-signing.py'))
signing = importlib.util.module_from_spec(signing_spec)
signing_spec.loader.exec_module(signing)
BUNDLE = 'de.mopphie.devntube.share'


def certificate_digest(p12):
    pem = subprocess.check_output(['openssl', 'pkcs12', '-in', str(p12), '-clcerts', '-nokeys',
                                   '-passin', 'env:APPLE_CERTIFICATE_PASSWORD'], stderr=subprocess.DEVNULL)
    der = subprocess.check_output(['openssl', 'x509', '-outform', 'DER'], input=pem, stderr=subprocess.DEVNULL)
    return hashlib.sha256(der).hexdigest()


def run(p12, output, bootstrap):
    client = asc.Client()
    digest = certificate_digest(p12)
    certs = client.records('/v1/certificates', {'limit': 200})
    cert = next((c for c in certs if hashlib.sha256(base64.b64decode(c['attributes'].get('certificateContent', ''))).hexdigest() == digest), None)
    if cert is None:
        raise RuntimeError('Existing distribution certificate is not accessible to this Apple key; nothing revoked or replaced')
    bundles = client.records('/v1/bundleIds', {'filter[identifier]': BUNDLE, 'limit': 10})
    if not bundles:
        if not bootstrap:
            raise RuntimeError('Share registration requires the authorized setup workflow')
        bundle = client.request('/v1/bundleIds', method='POST', body={'data': {'type': 'bundleIds', 'attributes': {
            'identifier': BUNDLE, 'name': 'DevnTube Share Extension', 'platform': 'IOS'}}})['data']
        print('Registered the authorized Share bundle ID.')
    else:
        bundle = bundles[0]
    bundle_id = bundle['id']
    print('Reading registered Share capabilities.', flush=True)
    capabilities = client.records('/v1/bundleIds/' + bundle_id + '/bundleIdCapabilities', {'limit': 50})
    if not any(c['attributes'].get('capabilityType') == 'APP_GROUPS' for c in capabilities):
        if not bootstrap:
            raise RuntimeError('Share App Groups capability is missing; run authorized setup')
        # The public API can reject provisioning of App Groups. Let Xcode,
        # which also associates the existing group, configure this capability.
        print('Xcode must enable and associate the existing App Group.', flush=True)
    if bootstrap:
        # Xcode is the supported route to associate the already existing App
        # Group. This relationship is not exposed in the public ASC REST API.
        command = ['xcodebuild', '-project', 'WebKWeb.xcodeproj', '-target', 'ShareExtension',
                   '-configuration', 'Release', '-sdk', 'iphoneos', '-allowProvisioningUpdates',
                   '-authenticationKeyPath', str(client.key_file), '-authenticationKeyID', client.key_id,
                   '-authenticationKeyIssuerID', client.issuer, 'CODE_SIGN_STYLE=Automatic',
                   'DEVELOPMENT_TEAM=' + signing.TEAM, 'CODE_SIGN_IDENTITY=Apple Development',
                   'PROVISIONING_PROFILE_SPECIFIER=', 'REGISTER_APP_GROUPS=YES', 'build']
        print('Starting authorized Xcode automatic signing for Share only.', flush=True)
        with tempfile.TemporaryFile() as log:
            code = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, check=False).returncode
            print('Xcode Share signing setup exit status:', code)
            if code:
                log.seek(0); text = log.read().decode('utf-8', errors='replace')
                for needle, message in (
                    ('No Accounts', 'Xcode reports no usable developer account.'),
                    ('does not have permission', 'Apple key has insufficient provisioning permission.'),
                    ('no registered devices', 'No development devices are registered.'),
                    ('Failed Registering Bundle Identifier', 'Xcode could not register the bundle identifier.'),
                    ('does not support the App Groups capability', 'The selected profile lacks App Groups.'),
                    ("doesn't include the", 'The selected profile lacks required entitlements.'),
                    ('requires a provisioning profile', 'Xcode could not obtain a provisioning profile.'),
                    ('not available for this team', 'Required signing capability is unavailable to this team.'),
                    ('401', 'Apple authentication was rejected.'),
                    ('403', 'Apple provisioning access was rejected.')):
                    if needle.lower() in text.lower(): print(message)
    profiles = client.records('/v1/bundleIds/' + bundle_id + '/profiles', {'limit': 200})
    # Prefer a previously generated, still valid profile; never revoke profiles.
    for candidate in profiles:
        attrs = candidate['attributes']
        if attrs.get('profileType') != 'IOS_APP_STORE' or attrs.get('profileState') != 'ACTIVE':
            continue
        if not attrs.get('profileContent'):
            attrs = client.request('/v1/profiles/' + candidate['id'])['data']['attributes']
        try:
            output.write_bytes(base64.b64decode(attrs['profileContent'], validate=True)); output.chmod(0o600)
            signing.profile(output, BUNDLE, digest)
            print('Existing Share distribution profile passed entitlement and certificate validation.')
            return
        except (SystemExit, KeyError, ValueError):
            output.unlink(missing_ok=True)
    created = client.request('/v1/profiles', method='POST', body={'data': {'type': 'profiles', 'attributes': {
        'name': 'DevnTube Share App Store ' + os.environ.get('GITHUB_RUN_ID', 'authorized-setup'), 'profileType': 'IOS_APP_STORE'},
        'relationships': {'bundleId': {'data': {'type': 'bundleIds', 'id': bundle_id}},
                          'certificates': {'data': [{'type': 'certificates', 'id': cert['id']}]}}}})['data']
    attrs = created['attributes']
    if not attrs.get('profileContent'):
        attrs = client.request('/v1/profiles/' + created['id'])['data']['attributes']
    output.write_bytes(base64.b64decode(attrs['profileContent'], validate=True)); output.chmod(0o600)
    try:
        signing.profile(output, BUNDLE, digest)
    except SystemExit:
        output.unlink(missing_ok=True)
        raise RuntimeError('Apple generated a profile without the required existing App Group or matching signing rights; Apple portal/Xcode association remains necessary') from None
    print('Created Share App Store profile; team, bundle, existing App Group, certificate and expiry validated.')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--p12', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--bootstrap', action='store_true')
    args = parser.parse_args()
    try:
        run(args.p12, args.output, args.bootstrap)
    except asc.APIError as error:
        print('::error::Apple Share signing setup returned HTTP', error.status)
        sys.exit(1)
    except (RuntimeError, subprocess.CalledProcessError, ValueError, KeyError) as error:
        print('::error::' + (str(error) if isinstance(error, RuntimeError) else 'Share signing validation failed; credential details withheld'))
        sys.exit(1)


if __name__ == '__main__':
    main()
