"""Review exact runtime evidence; never suppress a whole module or severity."""
import copy
import importlib.util
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
EVIDENCE = ROOT / 'dist/security-runtime'
CRYPTO_PURL = 'pkg:golang/golang.org/x/crypto@v0.57.0'
SPEC = importlib.util.spec_from_file_location(
    'policy', ROOT / 'scripts/enforce-runtime-vulnerabilities.py')
POLICY = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(POLICY)


def module_version(info, name):
    matches = [line.split()[2] for line in info.splitlines()
               if len(line.split()) >= 3
               and line.split()[:2] == ['dep', name]]
    if len(matches) != 1:
        raise ValueError('missing or duplicate build module: ' + name)
    return matches[0]


def review(report, dependencies, gomplate_info, docker_info, image_id):
    imports = dependencies.splitlines()
    if ('github.com/hairyhenderson/gomplate/v5/cmd/gomplate' not in imports
            or any(name == 'golang.org/x/crypto/openpgp'
                   or name.startswith('golang.org/x/crypto/openpgp/')
                   for name in imports)):
        raise ValueError('gomplate OpenPGP package-absence proof failed')
    if module_version(gomplate_info, 'golang.org/x/crypto') != 'v0.57.0':
        raise ValueError('gomplate crypto identity changed')
    for info, modules in (
        (gomplate_info, ['go.opentelemetry.io/otel/sdk']),
        (docker_info, ['go.opentelemetry.io/otel/sdk',
                       'go.opentelemetry.io/otel/exporters/otlp/otlptrace',
                       'go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracegrpc']),
    ):
        for module in modules:
            if module_version(info, module) != 'v1.45.0':
                raise ValueError('OpenTelemetry security pin changed')
    effective = copy.deepcopy(report)
    removed = []
    for result in effective.get('Results') or []:
        retained = []
        for finding in result.get('Vulnerabilities') or []:
            if (result.get('Target') == 'usr/local/bin/gomplate'
                    and finding.get('VulnerabilityID') == 'GO-2026-5932'
                    and finding.get('PkgName') == 'golang.org/x/crypto'
                    and finding.get('InstalledVersion') == 'v0.57.0'
                    and finding.get('Severity') == 'UNKNOWN'
                    and not finding.get('FixedVersion')
                    and (finding.get('PkgIdentifier') or {}).get('PURL') == CRYPTO_PURL):
                removed.append(finding)
            else:
                retained.append(finding)
        if 'Vulnerabilities' in result:
            result['Vulnerabilities'] = retained
    if len(removed) > 1:
        raise ValueError('duplicate OpenPGP finding')
    vex = {
        '@context': 'https://openvex.dev/ns/v0.2.0',
        '@id': 'https://github.com/PastureStack/system-image-preloader/security/openpgp/' + image_id,
        'author': 'PastureStack', 'timestamp': '2026-10-23T00:00:00Z', 'version': 1,
        'statements': [],
    }
    if removed:
        vex['statements'].append({
            'vulnerability': {'@id': 'https://pkg.go.dev/vuln/GO-2026-5932',
                              'name': 'GO-2026-5932'},
            'products': [{'@id': image_id,
                          'subcomponents': [{'@id': CRYPTO_PURL}]}],
            'status': 'not_affected', 'justification': 'vulnerable_code_not_present',
            'impact_statement': 'Exact built gomplate imports no golang.org/x/crypto/openpgp package; '
                                'the Go advisory affects only that deprecated package subtree.',
        })
    return effective, vex


def main():
    report = json.loads((EVIDENCE / 'system-image-preloader-security.json').read_text())
    images = json.loads((EVIDENCE / 'images.json').read_text())
    if len(images) != 1 or report.get('Metadata', {}).get('ImageID') != images[0]['Id']:
        raise ValueError('scan does not identify the exact built image')
    image_id = images[0]['Id']
    effective, vex = review(
        report, (EVIDENCE / 'gomplate-dependencies.txt').read_text(),
        (EVIDENCE / 'gomplate-buildinfo.txt').read_text(),
        (EVIDENCE / 'docker-buildinfo.txt').read_text(), image_id)
    ledger = json.loads((ROOT / '.github/runtime-unfixed.json').read_text())
    errors = POLICY.violations(effective, ledger, 'PastureStack/system-image-preloader')
    (EVIDENCE / 'system-image-preloader-security-effective.json').write_text(
        json.dumps(effective, indent=2) + '\n')
    (EVIDENCE / 'system-image-preloader.openvex.json').write_text(
        json.dumps(vex, indent=2) + '\n')
    if errors:
        raise SystemExit('Runtime security policy failed:\n' + '\n'.join(errors))
    print('RUNTIME_FULL_SEVERITY_AND_EXACT_OPENPGP_PROOF_OK')


if __name__ == '__main__':
    main()
