import importlib.util
import pathlib
import sys
import unittest

sys.dont_write_bytecode = True
SPEC = importlib.util.spec_from_file_location(
    'review', pathlib.Path(__file__).resolve().parents[1] / 'scripts/review-runtime-security.py')
REVIEW = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(REVIEW)


class ExactOpenPGPProof(unittest.TestCase):
    def setUp(self):
        self.finding = {'VulnerabilityID': 'GO-2026-5932', 'PkgName': 'golang.org/x/crypto',
                        'InstalledVersion': 'v0.57.0', 'Severity': 'UNKNOWN',
                        'PkgIdentifier': {'PURL': REVIEW.CRYPTO_PURL}}
        self.report = {'SchemaVersion': 2, 'Results': [{
            'Target': 'usr/local/bin/gomplate', 'Vulnerabilities': [self.finding]}]}
        self.deps = 'github.com/hairyhenderson/gomplate/v5/cmd/gomplate\ngolang.org/x/crypto/ssh\n'
        self.gom = 'dep golang.org/x/crypto v0.57.0 h1:test\ndep go.opentelemetry.io/otel/sdk v1.45.0 h1:test'
        self.docker = REVIEW.DOCKER_SHA256 + '  /usr/local/bin/docker'

    def review(self):
        return REVIEW.review(self.report, self.deps, self.gom, self.docker, 'sha256:test')

    def test_exact_package_absence_filters_only_one_advisory(self):
        effective, vex = self.review()
        self.assertEqual(effective['Results'][0]['Vulnerabilities'], [])
        self.assertEqual(len(self.report['Results'][0]['Vulnerabilities']), 1)
        self.assertEqual(vex['statements'][1]['justification'], 'vulnerable_code_not_present')

    def test_any_openpgp_package_refuses_proof(self):
        for name in ('golang.org/x/crypto/openpgp', 'golang.org/x/crypto/openpgp/packet'):
            self.deps += name + '\n'
            with self.assertRaises(ValueError):
                self.review()

    def test_other_binary_and_new_identity_are_never_filtered(self):
        self.report['Results'][0]['Target'] = 'usr/local/bin/docker'
        self.assertEqual(len(self.review()[0]['Results'][0]['Vulnerabilities']), 1)
        self.report['Results'][0]['Target'] = 'usr/local/bin/gomplate'
        self.finding['VulnerabilityID'] = 'ANOTHER'
        self.assertEqual(len(self.review()[0]['Results'][0]['Vulnerabilities']), 1)

    def test_changed_purl_or_fixed_version_is_never_filtered(self):
        self.finding['FixedVersion'] = 'v0.58.0'
        self.assertEqual(len(self.review()[0]['Results'][0]['Vulnerabilities']), 1)
        del self.finding['FixedVersion']
        self.finding['PkgIdentifier']['PURL'] = 'pkg:golang/golang.org/x/crypto@v0.58.0'
        self.assertEqual(len(self.review()[0]['Results'][0]['Vulnerabilities']), 1)

    def test_old_otel_or_missing_proof_refuses_release(self):
        self.gom = self.gom.replace('v1.45.0', 'v1.44.0')
        with self.assertRaises(ValueError):
            self.review()

    def test_changed_docker_bytes_refuse_mitigation(self):
        self.docker = '0' * 64 + '  /usr/local/bin/docker'
        with self.assertRaises(ValueError):
            self.review()

    def test_distribution_exception_is_exact_and_does_not_hide_new_fixes(self):
        self.report['Results'][0]['Target'] = 'usr/local/bin/docker'
        self.report['Results'][0]['Vulnerabilities'] = [{
            'VulnerabilityID': 'CVE-2026-85747', 'PkgName': 'github.com/docker/distribution',
            'InstalledVersion': 'v2.8.3+incompatible', 'Severity': 'MEDIUM',
            'PkgIdentifier': {'PURL': REVIEW.DISTRIBUTION_PURL}}]
        self.assertEqual(self.review()[0]['Results'][0]['Vulnerabilities'], [])
        self.report['Results'][0]['Vulnerabilities'][0]['FixedVersion'] = '2.8.4'
        self.assertEqual(len(self.review()[0]['Results'][0]['Vulnerabilities']), 1)
        self.report['Results'][0]['Target'] = 'usr/local/bin/another-product'
        self.assertEqual(len(self.review()[0]['Results'][0]['Vulnerabilities']), 1)


if __name__ == '__main__':
    unittest.main()
