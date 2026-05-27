# Objective-C Proxy

## Design
The guest will have pre-generated host classes, while the host will dynamically register guest classes.
Each object, if referenced, stores the corresponding pointer of the other side of the world.
When calling objc_msgSend, it will convert all objc pointers to their corresponding pointers before passing them to the other side of the world.
Do note that guest has its own objc runtime which was borrowed from iOS 10 ramdisk 

### Guest world

### Host world

### TODO
- Validate that overridden methods using category on guest works properly
- Implement `[NSString initWithFormat:]` and stuff using it
