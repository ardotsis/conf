<h1 align="center">ar.sis's conf</h1>
<p align="center">
  <img src="docs/BD09068F832247CD9DD5ED2273F76F7CEBCB441A92CED8A076E213D7A4202EF0.webp" alt="girl" width="400">
  <br>
  <em>i love you, kana.</em>
</p>

## Install

### `kana@host`

```sh
curl -fsSL get.ardotsis.com/conf | bash -s -- -l install kana
```

You'll need:

- Public key for remote SSH.
- Configure local `~/.ssh/config` file. *1
- Registry generated public key on Git. *1

*1 See remote `~/conf_secret` file.

## Test

### Windows

Run container

```powershell
.\scripts\run_container.ps1 -Os debian -Params @("-dk","-d", "-l", "-luv", "kana", "install", "kana", "uwu") -Verbose
```

Execute in container

```powershell
.\scripts\exec_docker.ps1 -Os debian -Username kana -Exec zsh
```
