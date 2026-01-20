<h1 align="center">ar.sis's conf</h1>
<p align="center">
  <img src="docs/BD09068F832247CD9DD5ED2273F76F7CEBCB441A92CED8A076E213D7A4202EF0.webp" alt="girl" width="400">
</p>

## Install

### `ardotsis@vultr`

```sh
curl -fsSL get.ardotsis.com/df | bash -s -- -h vultr
```

> [!NOTE]
> After installation, check the `~/dotfiles-data/secret` file to configure the client's settings.

### `ardotsis@windows`

```batch
git clone https://github.com/ardotsis/dotfiles ~\.dotfiles
cd ~\.dotfiles
.\install.ps1
```

## Test

### Test `install.sh` on Docker (Windows)

```powershell
.\scripts\test_debian.bat "--host vultr --debug --docker" --build
```
