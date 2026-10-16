import datetime
import hashlib
import importlib.util
import os
from pathlib import Path
import plistlib
import sys
import tempfile
import unittest
from unittest.mock import patch

path = Path(__file__).resolve().parents[1] / 'ci-signing.py'
spec = importlib.util.spec_from_file_location('signing', path)
signing = importlib.util.module_from_spec(spec)
spec.loader.exec_module(signing)
CERT = b'public mock certificate bytes, not a key'


def profile(bundle, uuid):
    return plistlib.dumps({'TeamIdentifier': [signing.TEAM], 'UUID': uuid,
        'ExpirationDate': datetime.datetime(2100, 1, 1), 'DeveloperCertificates': [CERT],
        'Entitlements': {'application-identifier': signing.TEAM + '.' + bundle,
            'com.apple.developer.team-identifier': signing.TEAM,
            'com.apple.security.application-groups': [signing.GROUP], 'get-task-allow': False}})


class SigningTests(unittest.TestCase):
    def test_three_profiles_export_and_output_without_system_signing(self):
        with tempfile.TemporaryDirectory() as folder:
            output = Path(folder)/'output'; output.write_text('')
            profiles = [profile(bundle, 'mock-profile-' + str(i)) for i, bundle in enumerate(signing.BUNDLES)]
            with patch.object(sys, 'argv', ['ci-signing.py', 'app.profile', 'widget.profile', 'share.profile', 'certificate.p12', folder]), \
                 patch.dict(os.environ, {'GITHUB_OUTPUT': str(output)}), \
                 patch.object(signing.subprocess, 'check_output', side_effect=[b'mock PEM', CERT] + profiles):
                signing.main()
            result = plistlib.loads((Path(folder)/'ExportOptions.plist').read_bytes())
            self.assertEqual(set(result['provisioningProfiles']), set(signing.BUNDLES))
            self.assertIn('share_uuid=mock-profile-2', output.read_text())

    def test_share_profile_cannot_reuse_widget_application_identifier(self):
        with patch.object(signing.subprocess, 'check_output', return_value=profile(signing.BUNDLES[1], 'mock-widget')):
            with self.assertRaises(SystemExit):
                signing.profile(Path('mock.profile'), signing.BUNDLES[2], hashlib.sha256(CERT).hexdigest())

    def test_three_profiles_must_have_distinct_identifiers(self):
        with tempfile.TemporaryDirectory() as folder:
            profiles = [profile(bundle, 'same-mock-profile') for bundle in signing.BUNDLES]
            with patch.object(sys, 'argv', ['ci-signing.py', 'app', 'widget', 'share', 'p12', folder]), \
                 patch.object(signing.subprocess, 'check_output', side_effect=[b'mock PEM', CERT] + profiles):
                with self.assertRaises(SystemExit): signing.main()


if __name__ == '__main__': unittest.main()
