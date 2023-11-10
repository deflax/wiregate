Hello,

To be able to access the resources on our development infrastructure, you will need to set up a VPN profile.

To install the necessary client application, please visit the following page to obtain packages for the operating system your device is currently using:

https://www.wireguard.com/install/

Please take care of the configuration files and QR images as equivalent to a secure password.

For Windows, MacOS, Android and iOS simply import profile.conf or profile_alltraffic.conf file using the import tunnel function of the Wireguard software. 

You may choose to import both versions and switch between them, where the `alltraffic` version pushes all network routes through the endpoint, which is useful for example if a third party system requires a whitelisted company address or to switch geographic policy. The tradeoff is the limited bandwidth and delay of the endpoint for every network request, which could affect some resource intensive applications.

The connected device follows the remote network policy for the routed traffic and DNS requests.

For Linux you may use the wg-rapid script `sudo cp linux/wg-rapid /usr/local/bin`. Then copy either profile.conf file or the profile_alltraffic.conf version of it as /etc/wireguard/office.conf and start with `wg-rapid office` Please not that the linux script has built-in capability to switch between preselected routes, so it doesn't matter which one of them you choose to copy in this case.

Using a VPN client is somewhat platform and infrastructure specific, you may always contact #team-sysops for further assistance.

