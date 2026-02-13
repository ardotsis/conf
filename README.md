<h1 align="center">ar.sis's conf</h1>
<p align="center">
  <img src="docs/BD09068F832247CD9DD5ED2273F76F7CEBCB441A92CED8A076E213D7A4202EF0.webp" alt="girl" width="400">
  <br>
  <em>everything about ar.sis</em>
</p>

## Install

### `ardotsis@vultr`

```sh
curl -fsSL get.ardotsis.com/conf | bash -s -- install ardotsis
```

## Test

### Windows

Build

```powershell
.\scripts\run_test.ps1 -Os debian -Params @("-d", "-dk", "-l", "-luv", "haruka", "install", "kana", "vultr") -Verbose
```

Enter container

```powershell
.\scripts\enter_docker.ps1 -Os debian -Username kana
```
