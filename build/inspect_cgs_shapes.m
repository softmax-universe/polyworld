#import <AppKit/AppKit.h>
#import <objc/runtime.h>
int main() {
  @autoreleasepool {
    Class classes[] = {[NSWindow class], NSClassFromString(@"NSCGSWindow")};
    for (unsigned c=0;c<2;c++) {
      unsigned count=0;
      Method *methods=class_copyMethodList(classes[c], &count);
      for (unsigned i=0;i<count;i++) {
        const char *name=sel_getName(method_getName(methods[i]));
        NSString *string=@(name);
        if ([string rangeOfString:@"confin" options:NSCaseInsensitiveSearch].location != NSNotFound || [string rangeOfString:@"clip" options:NSCaseInsensitiveSearch].location != NSNotFound || [string rangeOfString:@"shape" options:NSCaseInsensitiveSearch].location != NSNotFound)
          printf("%s %s %s\n",class_getName(classes[c]),name,method_getTypeEncoding(methods[i]));
      }
      free(methods);
    }
  }
}
