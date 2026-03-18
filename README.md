<h1 align="center">ar.sis's conf</h1>
<p align="center">
  <img src="docs/BD09068F832247CD9DD5ED2273F76F7CEBCB441A92CED8A076E213D7A4202EF0.webp" alt="girl" width="400">
  <br>
</p>

## Install

### `kana@host`

```sh
curl -fsSL get.ardotsis.com/conf | bash -s -- init kana
```

You'll need:

- Public key for remote SSH.
- Configure local `~/.ssh/config` file. *1
- Registry generated public key on Git. *1

*1 See remote `~/conf_secret` file.

## Test

### Windows

Run container example

```powershell
.\scripts\run_container.ps1 -Os debian -Params @("--debug", "--show-log", "init", "kana", "uwu") -CleanStart
```

Execute in container example

```powershell
.\scripts\exec_docker.ps1 -Os debian -Username kana -Exec zsh
```
