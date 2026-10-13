# PIA (Private Internet Access) install

1. Install the client and start its service:

   ```sh
   paru -Syu piavpn-bin
   sudo systemctl enable --now piavpn.service
   sudo systemctl start piavpn.service
   ```

2. Check the service is running:

   ```sh
   sudo systemctl status piavpn.service
   ```

3. Open PIA and log in.
