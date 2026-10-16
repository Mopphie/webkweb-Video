#!/usr/bin/env python3
"""Runner-only TestFlight build numbering/verification. No third-party packages.

Uses the existing ASC key, OpenSSL and Python's standard library. Never logs key
material, JWTs, signing profiles, tester identities or API response bodies.
"""
import argparse
import base64
import json
import os
import plistlib
import re
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import zipfile
from pathlib import Path

API = 'https://api.appstoreconnect.apple.com'
APP_ID = '6822711093'
BUNDLE_ID = 'de.mopphie.devntube'


class APIError(RuntimeError):
    def __init__(self, status):
        self.status = status
        super().__init__(f'App Store Connect HTTP {status}; response body and credentials withheld')


def b64url(data):
    return base64.urlsafe_b64encode(data).rstrip(b'=').decode('ascii')


def raw_signature(der):
    """Convert OpenSSL's DER ECDSA signature into the JWT R || S format."""
    if len(der) < 8 or der[0] != 0x30 or der[1] != len(der) - 2:
        raise ValueError('Invalid ES256 signature sequence')
    offset, values = 2, []
    for _ in range(2):
        if offset + 2 > len(der) or der[offset] != 2:
            raise ValueError('Invalid ES256 signature integer')
        length = der[offset + 1]
        value = der[offset + 2:offset + 2 + length]
        if len(value) != length or not value or value[0] & 0x80:
            raise ValueError('Invalid ES256 signature bounds')
        value = value.lstrip(b'\0') or b'\0'
        if len(value) > 32:
            raise ValueError('ES256 signature exceeds P-256 size')
        values.append(value.rjust(32, b'\0'))
        offset += length + 2
    if offset != len(der):
        raise ValueError('Unexpected ES256 signature trailing bytes')
    return b''.join(values)


def token(key_id, issuer, key_file, now=None):
    now = int(time.time() if now is None else now)
    header = b64url(json.dumps({'alg': 'ES256', 'kid': key_id, 'typ': 'JWT'}, separators=(',', ':')).encode())
    claims = b64url(json.dumps({'iss': issuer, 'iat': now - 5, 'exp': now + 600,
                               'aud': 'appstoreconnect-v1'}, separators=(',', ':')).encode())
    signing_input = (header + '.' + claims).encode('ascii')
    try:
        signature = subprocess.check_output(['openssl', 'dgst', '-sha256', '-sign', str(key_file)],
                                            input=signing_input, stderr=subprocess.DEVNULL)
    except subprocess.CalledProcessError:
        raise RuntimeError('ASC key could not sign an ES256 token') from None
    return signing_input.decode() + '.' + b64url(raw_signature(signature))


class Client:
    def __init__(self):
        self.key_id = os.environ.get('APP_STORE_CONNECT_KEY_ID', '')
        self.issuer = os.environ.get('APP_STORE_CONNECT_ISSUER_ID', '')
        self.key_file = Path(os.environ.get('ASC_KEY_PATH', '/nonexistent'))
        if not self.key_id or not self.issuer or not self.key_file.is_file():
            raise RuntimeError('Missing runner-local App Store Connect key configuration')

    def request(self, path, query=None, method='GET', body=None):
        url = urllib.parse.urljoin(API, path)
        parsed = urllib.parse.urlsplit(url)
        if parsed.scheme != 'https' or parsed.netloc != 'api.appstoreconnect.apple.com' or not parsed.path.startswith('/v1/'):
            raise RuntimeError('Rejected unexpected App Store Connect endpoint')
        if query:
            url += '?' + urllib.parse.urlencode(query)
        payload = None if body is None else json.dumps(body).encode()
        for attempt in range(4):
            request = urllib.request.Request(url, data=payload, method=method,
                headers={'Authorization': 'Bearer ' + token(self.key_id, self.issuer, self.key_file),
                         'Content-Type': 'application/json', 'Accept': 'application/json'})
            try:
                with urllib.request.urlopen(request, timeout=45) as response:
                    data = response.read()
                    return json.loads(data) if data else {}
            except urllib.error.HTTPError as error:
                if error.code in (429, 500, 502, 503, 504) and attempt < 3:
                    time.sleep(2 ** attempt)
                    continue
                raise APIError(error.code) from None
            except urllib.error.URLError:
                if attempt < 3:
                    time.sleep(2 ** attempt)
                    continue
                raise RuntimeError('App Store Connect network request failed') from None

    def records(self, path, query=None):
        result = []
        while path:
            page = self.request(path, query)
            if not isinstance(page.get('data'), list):
                raise RuntimeError('App Store Connect returned an unexpected collection')
            result.extend(page['data'])
            path, query = page.get('links', {}).get('next'), None
        return result


def builds(client, app_id, version=None):
    query = {'filter[app]': app_id, 'limit': 200, 'sort': '-uploadedDate'}
    if version is not None:
        query['filter[version]'] = str(version)
    return client.records('/v1/builds', query)


def build_version(build):
    value = build.get('attributes', {}).get('version', '')
    if not re.fullmatch(r'\d+(?:\.\d+){0,2}', value):
        raise RuntimeError('An existing ASC build has an unsupported version format')
    return tuple(int(part) for part in value.split('.'))


def next_build(client, app_id, minimum=3):
    app = client.request('/v1/apps/' + app_id)['data']
    if app.get('attributes', {}).get('bundleId') != BUNDLE_ID:
        raise RuntimeError('ASC app ID does not match the expected bundle identifier')
    existing = builds(client, app_id)
    highest = max((build_version(build)[0] for build in existing), default=0)
    previous = [build for build in existing if build.get('attributes', {}).get('processingState') == 'VALID'
                and not build.get('attributes', {}).get('expired', False)]
    last = max(previous, key=build_version) if previous else None
    return {'build_number': max(minimum, highest + 1), 'previous_build_id': last['id'] if last else ''}


def verify_ipa(path, number):
    with zipfile.ZipFile(path) as archive:
        names = archive.namelist()
        apps = [name for name in names if re.fullmatch(r'Payload/[^/]+\.app/Info\.plist', name)]
        if len(apps) != 1:
            raise RuntimeError('Exported IPA must contain exactly one app')
        app = plistlib.loads(archive.read(apps[0]))
        widgets = [name for name in names if re.fullmatch(r'Payload/[^/]+\.app/PlugIns/[^/]+\.appex/Info\.plist', name)]
        info = [app] + [plistlib.loads(archive.read(name)) for name in widgets]
        if {item.get('CFBundleIdentifier') for item in info} != {BUNDLE_ID, BUNDLE_ID + '.favorites'} or len(info) != 2:
            raise RuntimeError('Exported IPA app/widget identifiers do not match')
        if any(str(item.get('CFBundleVersion')) != str(number) for item in info):
            raise RuntimeError('App and widget must use the selected ASC build number')
        version = app.get('CFBundleShortVersionString')
        if not version or any(item.get('CFBundleShortVersionString') != version for item in info):
            raise RuntimeError('App and widget marketing versions differ')
    return {'marketing_version': version, 'verified_build_number': number}


def wait_for_valid(client, app_id, number, timeout, sleep=time.sleep):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        found = builds(client, app_id, number)
        if len(found) > 1:
            raise RuntimeError('ASC returned multiple builds for the unique selected number')
        if found:
            build = found[0]
            state = build.get('attributes', {}).get('processingState')
            if state == 'VALID':
                return build
            if state in ('FAILED', 'INVALID'):
                raise RuntimeError('Uploaded build processing failed: ' + state)
            print('Apple processing state:', state, flush=True)
        else:
            print('Waiting for uploaded build to appear in App Store Connect', flush=True)
        sleep(15)
    raise RuntimeError('Uploaded build did not become VALID before the verification deadline')


def inherit_internal_groups(client, build_id, previous_id):
    if not previous_id:
        return 'No previous valid build: no existing group membership was changed'
    try:
        previous = client.records('/v1/builds/' + previous_id + '/betaGroups', {'limit': 200})
        internal = [group for group in previous if group.get('attributes', {}).get('isInternalGroup') is True]
        current = {group['id'] for group in client.records('/v1/builds/' + build_id + '/betaGroups', {'limit': 200})}
        for group in internal:
            if group['id'] not in current:
                client.request('/v1/betaGroups/' + group['id'] + '/relationships/builds', method='POST',
                               body={'data': [{'type': 'builds', 'id': build_id}]})
        verified = {group['id'] for group in client.records('/v1/builds/' + build_id + '/betaGroups', {'limit': 200})}
        if any(group['id'] not in verified for group in internal):
            raise RuntimeError('Existing internal beta-group membership could not be verified')
        return f'Existing internal groups inherited and verified: {len(internal)}; no testers invited or groups created'
    except APIError as error:
        if error.status == 403:
            return 'WARNING: API key cannot manage/read beta groups; existing tester availability needs manual confirmation'
        raise


def wait_for_internal_availability(client, build_id, timeout, sleep=time.sleep):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        try:
            detail = client.request('/v1/builds/' + build_id + '/buildBetaDetail')['data']
            state = detail.get('attributes', {}).get('internalBuildState')
        except APIError as error:
            if error.status != 404:
                raise
            state = 'PROCESSING'
        if state in ('READY_FOR_BETA_TESTING', 'IN_BETA_TESTING'):
            return state
        if state in ('MISSING_EXPORT_COMPLIANCE', 'EXPIRED', 'PROCESSING_EXCEPTION'):
            raise RuntimeError('Internal TestFlight availability requires attention: ' + state)
        print('Internal TestFlight state:', state, flush=True)
        sleep(15)
    raise RuntimeError('Build is VALID but internal TestFlight availability was not confirmed before deadline')


def emit(values):
    target = os.environ.get('GITHUB_OUTPUT')
    if target:
        with Path(target).open('a', encoding='utf-8') as output:
            for key, value in values.items():
                if '\n' in str(value) or '\r' in str(value):
                    raise RuntimeError('Rejected multiline workflow output')
                output.write(f'{key}={value}\n')
    print(json.dumps(values, ensure_ascii=False))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='command', required=True)
    number = sub.add_parser('next-build'); number.add_argument('--app-id', default=APP_ID)
    number.add_argument('--minimum', type=int, default=3)
    ipa = sub.add_parser('verify-ipa'); ipa.add_argument('--ipa', required=True)
    ipa.add_argument('--build-number', type=int, required=True)
    verify = sub.add_parser('verify'); verify.add_argument('--app-id', default=APP_ID)
    verify.add_argument('--build-number', type=int, required=True)
    verify.add_argument('--previous-build-id', default='')
    verify.add_argument('--timeout', type=int, default=1800)
    args = parser.parse_args()
    if args.command == 'verify-ipa':
        emit(verify_ipa(args.ipa, args.build_number)); return
    client = Client()
    if args.command == 'next-build':
        emit(next_build(client, args.app_id, args.minimum)); return
    build = wait_for_valid(client, args.app_id, args.build_number, args.timeout)
    groups = inherit_internal_groups(client, build['id'], args.previous_build_id)
    available = wait_for_internal_availability(client, build['id'], min(args.timeout, 600))
    emit({'build_id': build['id'], 'build_number': args.build_number,
          'processing_state': 'VALID', 'internal_state': available, 'groups': groups})


if __name__ == '__main__':
    try:
        main()
    except (RuntimeError, ValueError, KeyError, OSError, zipfile.BadZipFile) as error:
        print('TestFlight verification failed: ' + str(error), file=sys.stderr)
        sys.exit(1)
