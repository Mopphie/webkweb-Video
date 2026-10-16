"""Provisioning policy tests with mock API records; no Apple account access."""
import base64
import hashlib
import importlib.util
from pathlib import Path
import plistlib
import tempfile
import unittest
from unittest.mock import Mock, patch

spec = importlib.util.spec_from_file_location('provision_share', Path(__file__).resolve().parents[1] / 'provision-share.py')
setup = importlib.util.module_from_spec(spec)
spec.loader.exec_module(setup)
CERT = b'public mock certificate'
CERTIFICATE = {'id': 'matching-certificate', 'attributes': {'certificateContent': base64.b64encode(CERT).decode()}}
BUNDLE = {'id': 'share-bundle', 'attributes': {'identifier': setup.BUNDLE}}
PROFILE = {'id': 'profile', 'attributes': {'profileType': 'IOS_APP_STORE', 'profileState': 'ACTIVE', 'profileContent': base64.b64encode(b'mock profile').decode()}}


class ShareProvisioningTests(unittest.TestCase):
    def run_setup(self, client, root, bootstrap=False, group=True):
        with patch.object(setup.asc, 'Client', return_value=client), \
             patch.object(setup, 'certificate_digest', return_value=hashlib.sha256(CERT).hexdigest()), \
             patch.object(setup.subprocess, 'check_output', return_value=plistlib.dumps({'Entitlements': {
                 'com.apple.security.application-groups': [setup.signing.GROUP] if group else []}})):
            setup.run(Path(root) / 'mock.p12', Path(root) / 'share.profile', bootstrap)

    def test_missing_matching_certificate_cannot_create_or_replace_assets(self):
        client = Mock(); client.records.return_value = []
        with tempfile.TemporaryDirectory() as root:
            with self.assertRaises(RuntimeError): self.run_setup(client, root, True)
        client.request.assert_not_called()

    def test_normal_release_cannot_register_missing_extension(self):
        client = Mock(); client.records.side_effect = [[CERTIFICATE], []]
        with tempfile.TemporaryDirectory() as root:
            with self.assertRaises(RuntimeError): self.run_setup(client, root)
        client.request.assert_not_called()

    def test_existing_profile_requires_exact_share_validation_without_mutation(self):
        client = Mock(); client.records.side_effect = [[CERTIFICATE], [BUNDLE], [PROFILE]]
        with tempfile.TemporaryDirectory() as root, patch.object(setup.signing, 'profile') as validate:
            self.run_setup(client, root)
            validate.assert_called_once_with(Path(root) / 'share.profile', setup.BUNDLE, hashlib.sha256(CERT).hexdigest())
        client.request.assert_not_called()

    def test_invalid_generated_profile_is_not_retained_or_claimed_valid(self):
        development = {'attributes': dict(PROFILE['attributes'], profileType='IOS_APP_DEVELOPMENT')}
        client = Mock(); client.records.side_effect = [[CERTIFICATE], [BUNDLE], [development]]
        client.request.return_value = {'data': PROFILE}
        with tempfile.TemporaryDirectory() as root, patch.object(setup.signing, 'profile', side_effect=SystemExit('invalid entitlement')):
            with self.assertRaises(RuntimeError): self.run_setup(client, root)
            self.assertFalse((Path(root) / 'share.profile').exists())
        body = client.request.call_args.kwargs['body']['data']
        self.assertEqual(body['attributes']['profileType'], 'IOS_APP_STORE')
        self.assertEqual(body['relationships']['bundleId']['data']['id'], BUNDLE['id'])
        self.assertEqual(body['relationships']['certificates']['data'][0]['id'], CERTIFICATE['id'])

    def test_missing_app_group_does_not_generate_more_invalid_profiles(self):
        client = Mock(); client.records.side_effect = [[CERTIFICATE], [BUNDLE], [PROFILE]]
        with tempfile.TemporaryDirectory() as root, patch.object(setup.signing, 'profile', side_effect=SystemExit('missing group')):
            with self.assertRaises(RuntimeError): self.run_setup(client, root, group=False)
            self.assertFalse((Path(root) / 'share.profile').exists())
        client.request.assert_not_called()

    def test_authorized_bootstrap_targets_only_share_and_never_revokes(self):
        client = Mock(); client.records.side_effect = [[CERTIFICATE], [], [PROFILE]]
        client.request.return_value = {'data': BUNDLE}; client.key_file = Path('mock.p8'); client.key_id = 'mock-id'; client.issuer = 'mock-issuer'
        with tempfile.TemporaryDirectory() as root, patch.object(setup.signing, 'profile'), \
             patch.object(setup.subprocess, 'run', return_value=Mock(returncode=0)) as xcode:
            self.run_setup(client, root, True)
        command = xcode.call_args.args[0]
        self.assertIn('-allowProvisioningUpdates', command)
        self.assertEqual(command[command.index('-target') + 1], 'ShareExtension')
        self.assertIn('REGISTER_APP_GROUPS=YES', command)
        client.request.assert_called_once()
        body = client.request.call_args.kwargs['body']['data']
        self.assertEqual(body['attributes']['identifier'], setup.BUNDLE)
        self.assertEqual(client.request.call_args.kwargs['method'], 'POST')


if __name__ == '__main__': unittest.main()
