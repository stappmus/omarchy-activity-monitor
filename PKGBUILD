# Maintainer: Kristoffer Haugland <stappmus at gmail dot com>

pkgname=omarchy-activity-monitor-power-helper
pkgver=2.1.1
pkgrel=1
pkgdesc="Optional root-only native RAPL reader for the Omarchy Activity Monitor plugin"
arch=('x86_64' 'aarch64')
url="https://github.com/stappmus/omarchy-activity-monitor"
license=('MIT')
depends=('gcc-libs' 'glibc' 'sudo')
makedepends=('gcc' 'make')
options=('!debug')
source=(
  'activity-sampler.cpp'
  'Makefile'
  'stappmus-activity-monitor.sudoers'
  'README.md'
  'LICENSE'
)
sha256sums=(
  '37645efc700fa02a6aa6b20ca3435701ca40354384342bf59387fb4ef93cc842'
  '6bf0a9b76c12992f418bcffcea673c98d299c9445bae5b6cb83a3708eee5663c'
  'e248f015e89bc7f3df4714e7d1e0248c4ac9cc4b4642dda6aa428741b6c4f2ca'
  '5361f1c5a85862e878d351c915f16fab3fecd967ed9afb48c9db55400e3112a6'
  'dd56ead2d3379b1d8298bbd1b905188b21894c46312ea4186b2afde9b03b3184'
)

build() {
  make activity-sampler
}

check() {
  [[ $(./activity-sampler --version) == 'activity-sampler 2.1.1' ]]
  grep -Fxq \
    '%wheel ALL=(root) NOPASSWD: /usr/lib/stappmus-activity-monitor/activity-sampler --activity-process-power-reader' \
    stappmus-activity-monitor.sudoers
  if command -v visudo >/dev/null 2>&1; then
    visudo -cf stappmus-activity-monitor.sudoers >/dev/null
  fi
}

package() {
  install -Dm755 activity-sampler \
    "$pkgdir/usr/lib/stappmus-activity-monitor/activity-sampler"
  install -Dm440 stappmus-activity-monitor.sudoers \
    "$pkgdir/etc/sudoers.d/stappmus-activity-monitor"
  install -Dm644 README.md \
    "$pkgdir/usr/share/doc/$pkgname/README.md"
  install -Dm644 LICENSE \
    "$pkgdir/usr/share/licenses/$pkgname/LICENSE"
}
