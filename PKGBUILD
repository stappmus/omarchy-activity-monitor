# Maintainer: Kristoffer Haugland <stappmus at gmail dot com>

pkgname=omarchy-activity-monitor-power-helper
pkgver=2.2.0
pkgrel=1
pkgdesc="Optional root-only native RAPL reader for the Omarchy Activity Monitor plugin"
arch=('x86_64')
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
  'ee530f14fbbf7c0954806b27ee1a1f63b30d5c936d7985f4a16b2bafb5879d58'
  '2ea69385047c3a1d1893378e2866a464cba7ae28040c0add8a3eaa80f94700a3'
  'e248f015e89bc7f3df4714e7d1e0248c4ac9cc4b4642dda6aa428741b6c4f2ca'
  'f3bcbf2f88afeb933c535d3cddc3f6b6431ddfe3ed080239d36375c4833d135c'
  'dd56ead2d3379b1d8298bbd1b905188b21894c46312ea4186b2afde9b03b3184'
)

build() {
  make activity-sampler
}

check() {
  [[ $(./activity-sampler --version) == 'activity-sampler 2.2.0' ]]
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
