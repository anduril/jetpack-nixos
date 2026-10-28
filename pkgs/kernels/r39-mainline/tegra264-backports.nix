{ fetchpatch }:
map (patch: { name = patch.name; inherit patch; }) [
  (fetchpatch {
    name = "tegra-i2c-separate-fast-fastplus-timings.patch";
    url = "https://github.com/torvalds/linux/commit/8b80b61e6f4fea1fab4f48ed6af2d9b8946f8049.patch";
    hash = "sha256-aAcrXgNnQlNcJ/NhpRlswqPOjVV3d9IJncZYmKJaqt0=";
  })
  (fetchpatch {
    name = "tegra-i2c-update-tegra256-timings.patch";
    url = "https://github.com/torvalds/linux/commit/81d4c5350f0148543bd4541a6d1fb06d9c835aeb.patch";
    hash = "sha256-0l/CjhUqUeB/+6Sdtxr509996QGlgpH6QbI/gjYko4M=";
  })
  (fetchpatch {
    name = "tegra-i2c-high-speed-mode.patch";
    url = "https://github.com/torvalds/linux/commit/978b3ccbbac326cc5fe48c98a0440bdc79d9fd93.patch";
    hash = "sha256-uQTX/Y+3Xig2KpmevfGKdEr1btPKiJiO0EFP7VjbSVo=";
  })
  (fetchpatch {
    name = "tegra-i2c-software-mutex.patch";
    url = "https://github.com/torvalds/linux/commit/6077cfd716fbd4d1f2a3702e49ae8bf65c072685.patch";
    hash = "sha256-T3LCabIU9ZAm4HyQiFqfNBAXA03CnNuY9fqHGAXsn0w=";
  })
  (fetchpatch {
    name = "tegra-i2c-tegra264-support.patch";
    url = "https://github.com/torvalds/linux/commit/1ac9e16dd226a26a479c7392c9ec28f1c9eec61c.patch";
    hash = "sha256-oj/MABa8EvzrvRFcLQ9caqeUndyM2RI8Xy/iGTlGA6I=";
  })
  (fetchpatch {
    name = "tegra-i2c-mutex-runtime-pm.patch";
    url = "https://github.com/torvalds/linux/commit/57cf4e8d6a57dc2ef5810f4852a23ba4c71b74bb.patch";
    hash = "sha256-okEttYUSP3PW/Drjm4G5VeYpYTGDDhDFLWqPTz2JKKA=";
  })
  (fetchpatch {
    name = "tegra-pmc-optional-aotag.patch";
    url = "https://github.com/torvalds/linux/commit/1c458bbe4b335d1675c47d64df0c8cd34961d2bf.patch";
    hash = "sha256-wm5BU+Svj8xiqu6wwIL8QbbR431flTVaHpDJVuCDWc4=";
  })
  (fetchpatch {
    name = "tegra-dma-optional-reset.patch";
    url = "https://github.com/torvalds/linux/commit/680e1b928a6adc1b2d95038ffe9c9887ceafd478.patch";
    hash = "sha256-9oj7YyWwMbFALidXOYAcPp0ymakjA9OD4+LSYjuaOho=";
  })
  (fetchpatch {
    name = "tegra-dma-register-offsets.patch";
    url = "https://github.com/torvalds/linux/commit/5000beabae65310ec81db40dcda181b0a6192ff3.patch";
    hash = "sha256-bNq4xFORDbiKjb2s97wtoYSsd7SP/XwoUXw/XmkAsgs=";
  })
  (fetchpatch {
    name = "tegra-dma-address-width.patch";
    url = "https://github.com/torvalds/linux/commit/286632b9bf1cf239482d54b592cc1d5bbd5ec783.patch";
    hash = "sha256-xFF7LvuM4SJeXfg8VpljmwVZLALXJUKS6WVU4WKsUoA=";
  })
  (fetchpatch {
    name = "of-dma-managed-registration.patch";
    url = "https://github.com/torvalds/linux/commit/3a005126c9d7f30093627a6f329656c358e16b3a.patch";
    hash = "sha256-SuViMFCiMH60yjJ9klyYUdbHwMCXbmpyLoE0LsFru9o=";
  })
  (fetchpatch {
    name = "tegra-dma-managed-registration.patch";
    url = "https://github.com/torvalds/linux/commit/45921a3282d642038d92737fab24107522324bd4.patch";
    hash = "sha256-EVfAKYj5G10OtdeuC80g5GiJXB9AneLIlpmgZKUvSsI=";
  })
  (fetchpatch {
    name = "tegra-dma-iommu-map.patch";
    url = "https://github.com/torvalds/linux/commit/321c0a15f027b83b20ed37717191a2187c9e2eb7.patch";
    hash = "sha256-qYOoMrqAjAU1KYouTF4qcJtFwjX0EXFoqcwqVV0FgKs=";
  })
  (fetchpatch {
    name = "tegra-dma-tegra264-support.patch";
    url = "https://github.com/torvalds/linux/commit/b236b7973808195fd9c471492bee0041148b823e.patch";
    hash = "sha256-J7S/3fdhuMQQo2FaFEx7q13Lmtq/U+cZgXNPI5SX9KA=";
  })
] ++ [
  {
    name = "tegra264-usb-phy";
    patch = ./tegra264-usb-phy.mbox;
  }
  {
    name = "tegra264-usb-host";
    patch = ./tegra264-usb-host.mbox;
  }
  {
    name = "tegra264-usb-device";
    patch = ./tegra264-usb-device.mbox;
  }
]
