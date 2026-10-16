import base64
import importlib.util
import json
import os
import plistlib
import subprocess
import tempfile
import unittest
import zipfile
from pathlib import Path
from unittest.mock import Mock

SCRIPTS = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('asc', SCRIPTS / 'app-store-connect.py')
asc = importlib.util.module_from_spec(spec)
spec.loader.exec_module(asc)


def build(number, state='VALID', identifier=None):
    return {'id': identifier or 'build-' + number,
            'attributes': {'version': number, 'processingState': state, 'expired': False}}


class ConnectTests(unittest.TestCase):
    def test_next_build_counts_invalid_uploads_and_keeps_valid_group_source(self):
        client = Mock()
        client.request.return_value = {'data': {'attributes': {'bundleId': asc.BUNDLE_ID}}}
        client.records.return_value = [build('2'), build('8', 'INVALID'), build('7', 'PROCESSING')]
        self.assertEqual(asc.next_build(client, asc.APP_ID), {'build_number': 9, 'previous_build_id': 'build-2'})

    def test_known_uploaded_build_two_sets_floor_without_ignoring_api(self):
        client = Mock()
        client.request.return_value = {'data': {'attributes': {'bundleId': asc.BUNDLE_ID}}}
        client.records.return_value = []
        self.assertEqual(asc.next_build(client, asc.APP_ID)['build_number'], 3)
        client.records.assert_called_once()
        client.request.return_value = {'data': {'attributes': {'bundleId': 'wrong.app'}}}
        with self.assertRaises(RuntimeError):
            asc.next_build(client, asc.APP_ID)

    def test_pagination_reads_all_build_pages(self):
        client = asc.Client.__new__(asc.Client)
        client.request = Mock(side_effect=[{'data': [build('1')], 'links': {'next': asc.API + '/v1/builds?cursor=2'}},
                                           {'data': [build('20')], 'links': {}}])
        self.assertEqual([item['attributes']['version'] for item in client.records('/v1/builds', {'limit': 200})], ['1', '20'])
        self.assertIsNone(client.request.call_args_list[1].args[1])

    def test_real_es256_jwt_uses_raw_signature_and_verifies_with_openssl(self):
        with tempfile.TemporaryDirectory() as folder:
            key, public, signature = (Path(folder) / name for name in ('test.p8', 'public.pem', 'signature.der'))
            subprocess.run(['openssl', 'genpkey', '-algorithm', 'EC', '-pkeyopt', 'ec_paramgen_curve:P-256', '-out', str(key)],
                           check=True, capture_output=True)
            subprocess.run(['openssl', 'pkey', '-in', str(key), '-pubout', '-out', str(public)], check=True, capture_output=True)
            value = asc.token('TESTKEY', 'test-issuer', key, now=1000)
            header, claims, encoded = value.split('.')
            decoded = lambda text: base64.urlsafe_b64decode(text + '=' * (-len(text) % 4))
            self.assertEqual(json.loads(decoded(header))['alg'], 'ES256')
            self.assertEqual(json.loads(decoded(claims))['exp'], 1600)
            raw = decoded(encoded); self.assertEqual(len(raw), 64)
            integers = []
            for half in (raw[:32], raw[32:]):
                integer = half.lstrip(b'\0') or b'\0'
                if integer[0] & 0x80: integer = b'\0' + integer
                integers.append(b'\x02' + bytes([len(integer)]) + integer)
            body = b''.join(integers); signature.write_bytes(b'\x30' + bytes([len(body)]) + body)
            result = subprocess.run(['openssl', 'dgst', '-sha256', '-verify', str(public), '-signature', str(signature)],
                                    input=(header + '.' + claims).encode(), capture_output=True)
            self.assertEqual(result.returncode, 0)

    def test_ipa_requires_matching_app_and_widget_build_numbers(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'test.ipa'
            def write(widget_number):
                with zipfile.ZipFile(path, 'w') as archive:
                    for suffix, bundle, number in (('Info.plist', asc.BUNDLE_ID, '3'),
                            ('PlugIns/Favorites.appex/Info.plist', asc.BUNDLE_ID + '.favorites', widget_number)):
                        archive.writestr('Payload/App.app/' + suffix, plistlib.dumps({'CFBundleIdentifier': bundle,
                            'CFBundleVersion': number, 'CFBundleShortVersionString': '0.1.0'}))
            write('3'); self.assertEqual(asc.verify_ipa(path, 3)['marketing_version'], '0.1.0')
            write('2')
            with self.assertRaises(RuntimeError): asc.verify_ipa(path, 3)

    def test_ipa_rejects_missing_widget_or_any_unexpected_extension(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder)/'mock.ipa'
            for missing_widget, extra in [(True, False), (False, True)]:
                with zipfile.ZipFile(path, 'w') as archive:
                    values = [('Info.plist', asc.BUNDLE_ID, '3')]
                    if not missing_widget: values.append(('PlugIns/Favorites.appex/Info.plist', asc.BUNDLE_ID + '.favorites', '3'))
                    if extra: values.append(('PlugIns/Unexpected.appex/Info.plist', asc.BUNDLE_ID + '.share', '3'))
                    for name, bundle, number in values:
                        archive.writestr('Payload/App.app/' + name, plistlib.dumps({'CFBundleIdentifier': bundle, 'CFBundleVersion': number, 'CFBundleShortVersionString': '0.1.0'}))
                with self.assertRaises(RuntimeError): asc.verify_ipa(path, 3)

    def test_processing_waits_for_valid_and_rejects_failed(self):
        client = Mock()
        client.records.side_effect = [[], [build('3', 'PROCESSING')], [build('3')]]
        self.assertEqual(asc.wait_for_valid(client, asc.APP_ID, 3, 1, sleep=lambda _: None)['id'], 'build-3')
        client.records.side_effect = [[build('3', 'INVALID')]]
        with self.assertRaises(RuntimeError): asc.wait_for_valid(client, asc.APP_ID, 3, 1, sleep=lambda _: None)

    def test_only_existing_internal_groups_are_inherited(self):
        internal = {'id': 'internal', 'attributes': {'isInternalGroup': True}}
        external = {'id': 'external', 'attributes': {'isInternalGroup': False}}
        client = Mock(); client.records.side_effect = [[internal, external], [], [internal]]
        self.assertIn('verified: 1', asc.inherit_internal_groups(client, 'new', 'old'))
        self.assertEqual([(args.args[0], args.args[1]) for args in client.records.call_args_list], [
            ('/v1/betaGroups', {'filter[builds]': 'old', 'limit': 200}),
            ('/v1/betaGroups', {'filter[builds]': 'new', 'limit': 200}),
            ('/v1/betaGroups', {'filter[builds]': 'new', 'limit': 200})])
        client.request.assert_called_once_with('/v1/betaGroups/internal/relationships/builds', method='POST',
                                               body={'data': [{'type': 'builds', 'id': 'new'}]})

    def test_group_permission_denial_is_not_claimed_as_verified(self):
        client = Mock(); client.records.side_effect = asc.APIError(403)
        self.assertTrue(asc.inherit_internal_groups(client, 'new', 'old').startswith('WARNING:'))

    def test_valid_build_also_requires_internal_availability(self):
        client = Mock(); client.request.side_effect = [{'data': {'attributes': {'internalBuildState': 'PROCESSING'}}},
                                                    {'data': {'attributes': {'internalBuildState': 'IN_BETA_TESTING'}}}]
        self.assertEqual(asc.wait_for_internal_availability(client, 'new', 1, sleep=lambda _: None), 'IN_BETA_TESTING')
        client.request.side_effect = [{'data': {'attributes': {'internalBuildState': 'MISSING_EXPORT_COMPLIANCE'}}}]
        with self.assertRaises(RuntimeError): asc.wait_for_internal_availability(client, 'new', 1, sleep=lambda _: None)

    def test_upload_guard_allows_only_exact_push_branch_or_confirmed_dispatch(self):
        workflow = (SCRIPTS.parent / '.github/workflows/testflight.yml').read_text()
        intent = workflow.split('      - name: Check explicit release intent\n', 1)[1].split('      - uses:', 1)[0]
        script = '\n'.join(line[10:] for line in intent.split('        run: |\n', 1)[1].splitlines())
        with tempfile.TemporaryDirectory() as folder:
            def run(event, ref, mode='', confirmation=''):
                output = Path(folder) / 'output'; output.write_text('')
                env = dict(os.environ, EVENT_NAME=event, EVENT_REF=ref, MODE=mode,
                           CONFIRM_UPLOAD=confirmation, GITHUB_OUTPUT=str(output))
                result = subprocess.run(['bash', '-c', script], env=env, capture_output=True)
                return result.returncode, output.read_text()
            self.assertEqual(run('push', 'refs/heads/codex/testflight-2026-10-16'), (0, 'mode=upload\nupload=true\n'))
            for ref in ('refs/heads/main', 'refs/heads/dev', 'refs/heads/codex/testflight-2026-10-160'):
                self.assertNotEqual(run('push', ref)[0], 0)
            self.assertNotEqual(run('workflow_dispatch', 'refs/heads/main', 'upload', 'yes')[0], 0)
            self.assertEqual(run('workflow_dispatch', 'refs/heads/main', 'upload', 'UPLOAD')[0], 0)
            self.assertIn('upload=false', run('workflow_dispatch', 'refs/heads/main', 'build-only')[1])


if __name__ == '__main__':
    unittest.main()
