{ fetchgit, l4tVersion }:
fetchgit {
  url = "https://nv-tegra.nvidia.com/r/tegra/optee-src/nv-optee";
  rev = "jetson_${l4tVersion}";
  sha256 = "sha256-44RBXFNUlqZoq3OY/OFwhiU4Qxi4xQNmetFmlrr6jzY=";
}
