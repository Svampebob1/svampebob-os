#!/usr/bin/env bash
set -euo pipefail

# Container-bygg (f.eks. blue-build/GitHub Actions RUN) setter ikke alltid
# HOME. rpm-makroene (%_topdir, brukt av rpm selv og rpmbuild) avhenger av
# HOME — uten den havner byggetreet på /rpmbuild i stedet for /root/rpmbuild.
# Gjør det eksplisitt og likt i alle miljøer.
export HOME="${HOME:-/root}"

version="1.43.1"
revision="1.svampebob1"

dnf install -y \
    dnf-plugins-core \
    rpm-build \
    curl \
    tar \
    ca-certificates

topdir="${HOME}/rpmbuild"
# Opprett byggetreet eksplisitt i stedet for å stole på rpmdev-setuptree,
# slik at det alltid havner under ${topdir}.
mkdir -p "${topdir}"/{BUILD,BUILDROOT,RPMS,SOURCES,SPECS,SRPMS}

# Hent og kontroller den eksakte upstream-versjonen.
curl -fL \
    "https://gitlab.gnome.org/World/Phosh/squeekboard/-/archive/v${version}/squeekboard-v${version}.tar.bz2" \
    -o "${topdir}/SOURCES/squeekboard-v${version}.tar.bz2"

echo '7fc32d518af9a204f9ff3597ce9f728c7d981868ddc84e55477bc847c7dfab3771c453a5bcf9f1f1a5d767a57e1e3509e841903bc9653321d6dfe264f3a02300' \
    "${topdir}/SOURCES/squeekboard-v${version}.tar.bz2" |
    sha512sum -c -

# Patch brukt av Fedora for zbus 4-kompatibilitet.
curl -fL \
    "https://gitlab.gnome.org/World/Phosh/squeekboard/-/merge_requests/709.patch" \
    -o "${topdir}/SOURCES/709.patch"

# Fedora 42 er siste branch med en fullstendig spec-fil.
curl -fL \
    "https://src.fedoraproject.org/rpms/squeekboard/raw/f42/f/squeekboard.spec" \
    -o "${topdir}/SPECS/squeekboard.spec"

curl -fL \
    "https://src.fedoraproject.org/rpms/squeekboard/raw/f42/f/squeekboard.desktop" \
    -o "${topdir}/SOURCES/squeekboard.desktop"

# Installer C-/Meson-avhengighetene fra den opprinnelige spec-filen.
dnf builddep -y "${topdir}/SPECS/squeekboard.spec"

rm -rf "/tmp/squeekboard-v${version}"
# Lag en låst og vendored Rust-avhengighetspakke.
tar -C /tmp -xf "${topdir}/SOURCES/squeekboard-v${version}.tar.bz2"

cd "/tmp/squeekboard-v${version}"
patch -p1 < "${topdir}/SOURCES/709.patch"
rm -rf "${topdir}/SOURCES/vendor"
# cargo vendor lager både vendor/ og Cargo.lock.
cargo vendor \
    --versioned-dirs \
    --respect-source-config \
    "${topdir}/SOURCES/vendor"

tar -C "${topdir}/SOURCES" \
    -czf "${topdir}/SOURCES/squeekboard-${version}-vendor.tar.gz" \
    vendor

cp Cargo.lock "${topdir}/SOURCES/Cargo.lock"

# Endre til en privat, reproduserbar versjonsmerking.
# Dette unngår %autorelease-rpmautospec ved direkte rpmbuild.
sed -i \
    -e "s/^Release:.*/Release: ${revision}%{?dist}/" \
    "${topdir}/SPECS/squeekboard.spec"

# Bruk vendor-pakken i stedet for Fedoras Rust-crate-pakker.
python3 - "${topdir}/SPECS/squeekboard.spec" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()


def sub(old: str, new: str) -> None:
    """Erstatt eksakt tekst, men feil høyt hvis Fedora har endret spec-fila."""
    global text
    if old not in text:
        raise SystemExit(f"FEIL: Fant ikke forventet tekst i spec-fila: {old!r}")
    text = text.replace(old, new)


sub(
    "Source1:\tsqueekboard.desktop\n",
    "Source1:\tsqueekboard.desktop\n"
    "Source2:\tsqueekboard-%{version}-vendor.tar.gz\n"
    "Source3:\tCargo.lock\n",
)

sub(
    "Patch:\t\t%{url}/-/merge_requests/709.patch",
    "Patch0:\t\t%{url}/-/merge_requests/709.patch",
)

sub(
    "BuildRequires:\trust-packaging\n",
    "BuildRequires:\trust\n"
    "BuildRequires:\tcargo\n",
)

# Pakk ut både hovedkilden (Source0) og vendor-arkivet (Source2).
# Source3 er Cargo.lock og må kopieres etter at kilden er pakket ut.
sub(
    "%autosetup -p1 -n %{name}-v%{version}",
    "%autosetup -p1 -n %{name}-v%{version} -a2\ncp %{SOURCE3} Cargo.lock",
)

sub(
    "rm -f Cargo.lock\n"
    "%generate_buildrequires\n"
    "%cargo_generate_buildrequires -a\n",
    "",
)

sub(
    "%meson\n",
    "%meson -Dtests=false\n",
)

sub(
    "%cargo_license_summary\n"
    "%{cargo_license} > LICENSE.dependencies\n",
    "%cargo_vendor_manifest\n",
)

sub(
    "%license COPYING LICENSE.dependencies",
    "%license COPYING cargo-vendor.txt",
)

# Oppbevar den genererte lock-filen i byggekatalogen.
sub(
    "%prep\n",
    "%prep\ncp %{SOURCE3} Cargo.lock\n",
)

# %cargo_prep peker crates-io mot den tomme systemregistret
# /usr/share/cargo/registry. Overstyr det slik at cargo bruker
# vendor-katalogen som ble pakket ut med -a2.
sub(
    "%cargo_prep\n",
    "%cargo_prep\n"
    "mkdir -p .cargo\n"
    "cat > .cargo/config <<EOF\n"
    "[source.crates-io]\n"
    "replace-with = \"vendored-sources\"\n"
    "\n"
    "[source.vendored-sources]\n"
    "directory = \"vendor\"\n"
    "\n"
    "[net]\n"
    "offline = true\n"
    "EOF\n",
)

path.write_text(text)
PY

# Vis endringene, slik at CI-loggen dokumenterer hva som ble bygget.
rpm -q --specfile "${topdir}/SPECS/squeekboard.spec"
rpmbuild -ba "${topdir}/SPECS/squeekboard.spec"

shopt -s nullglob
rpms=("${topdir}"/RPMS/*/squeekboard-[0-9]*.rpm)

if ((${#rpms[@]} != 1)); then
    echo "Forventet nøyaktig én squeekboard-RPM, fant ${#rpms[@]}" >&2
    find "${topdir}/RPMS" -type f -name '*.rpm' >&2
    exit 1
fi

mkdir -p /tmp/rpms
cp -- "${rpms[0]}" /tmp/rpms/squeekboard-custom.rpm

# Verifiser at filen faktisk er squeekboard, og vis intern versjon.
rpm --query --package \
    --queryformat '%{NAME} %{VERSION}-%{RELEASE}.%{ARCH}\n' \
    /tmp/rpms/squeekboard-custom.rpm


ls -lh /tmp/rpms/squeekboard-custom.rpm
