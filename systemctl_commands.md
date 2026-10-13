# systemctl commands

## 1. List all currently running services

```sh
systemctl list-units --type=service --state=running
```

## 2. List all loaded services (active and inactive)

```sh
systemctl list-units --type=service
```

## 3. Check the status of a specific service

```sh
systemctl status piavpn.service
```

## 4. List services configured to start on boot

```sh
systemctl list-unit-files --type=service --state=enabled
```

## 5. Check running user-level services

```sh
systemctl --user list-units --type=service --state=running
```

## 6. View failed services

```sh
systemctl --failed
```
