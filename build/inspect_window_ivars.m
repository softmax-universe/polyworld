#import <AppKit/AppKit.h>
#import <objc/runtime.h>
int main() { @autoreleasepool { unsigned count; Ivar *ivars=class_copyIvarList([NSWindow class], &count); for(unsigned i=0;i<count;i++) printf("%s %s %td\n",ivar_getName(ivars[i]),ivar_getTypeEncoding(ivars[i]),ivar_getOffset(ivars[i])); free(ivars); } }
