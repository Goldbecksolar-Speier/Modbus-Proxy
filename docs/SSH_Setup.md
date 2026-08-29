# SSH Key-Auth Setup (RUTX11, Dropbear)

Ziel: SSH und SCP ohne Passwort-Prompts (Voraussetzung fuer die Installer).

## 1. Key auf dem Windows-PC erzeugen

```powershell
ssh-keygen -t rsa -b 4096 -f "$env:USERPROFILE\.ssh\rutx11_key"
```

## 2. Public Key auf den Router kopieren

```powershell
scp -o StrictHostKeyChecking=no "$env:USERPROFILE\.ssh\rutx11_key.pub" root@<ROUTER-IP>:/tmp/key.pub
```

## 3. Key auf dem Router aktivieren

```sh
mkdir -p /etc/dropbear
cat /tmp/key.pub > /etc/dropbear/authorized_keys
chmod 600 /etc/dropbear/authorized_keys
/etc/init.d/dropbear restart
```

## 4. Test

```powershell
ssh -i "$env:USERPROFILE\.ssh\rutx11_key" root@<ROUTER-IP> "echo OK"
```

## 5. Optional: Passwort-Login deaktivieren

Erst wenn der Key-Login sicher funktioniert! In `/etc/config/dropbear`:

```
option PasswordAuth 'off'
option RootPasswordAuth 'off'
```

Danach `/etc/init.d/dropbear restart`.

**Hinweis:** Private Keys (`rutx11_key`) niemals ins Repository committen!
