# Puck

Puck is original. Not an exploit. Not a hypervisor. Not Linux.

On iOS 27, Developer Mode can pair with an app that advertises as a
pairable host (`_remotepairing-pairable-host._tcp`). That is the same
public path SideInstaller and StikPair use.

The handshake uses [idevice](https://github.com/jkcoxson/idevice) (MIT)
when the native library is linked. mDNS is published with NSNetService
so the app does not need Apple’s multicast entitlement.

The pairing record is this device’s computer identity. Private keys stay
on the phone.

The Home Screen pointer is AssistiveTouch. Pairing does not hide it.
