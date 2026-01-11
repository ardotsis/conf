<h1 align="center">ar.sis's dotfiles</h1>

<p align="center">
  <img src="docs/BD09068F832247CD9DD5ED2273F76F7CEBCB441A92CED8A076E213D7A4202EF0.webp" alt="girl" width="400">
</p>
<br>

> [!WARNING]
> This project is still work in progress. So please do not expect to work.

## Install

### `ardotsis@vultr`

```sh
curl -fsSL get.ardotsis.com/df | bash -s -- -h vultr
```

### `ardotsis@windows`

```batch
.\install.sh
```

## Test

### `install.sh` on Docker (Windows)

```powershell
.\scripts\test_debian.bat "--host vultr --username kana --local --docker" --build
.\scripts\test_debian.bat "--host vultr --username kana --local --docker" --cleanup
```
