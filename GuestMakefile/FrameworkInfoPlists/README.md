These are the framework bundle metadata files used when assembling the guest
root filesystem. They were copied from the iOS 10.3.3 (14G60) system image
and converted to XML so clean builds do not require that multi-gigabyte image
to be mounted.

`pack-ramdisk.sh` still supports `IOS_SYSTEM_ROOT` as an explicit override for
refreshing or testing metadata from another mounted system image. Set
`FRAMEWORK_INFO_ROOT` to use another metadata snapshot without mounting an
image.
