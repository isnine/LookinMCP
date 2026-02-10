#ifdef SHOULD_COMPILE_LOOKIN_SERVER

//
//  LookinAttributeModification.m
//  LookinMCP
//
//  NSSecureCoding implementation matching LookinServer's expected decoding.
//

#import "LookinAttributeModification.h"

@implementation LookinAttributeModification

#pragma mark - NSSecureCoding

+ (BOOL)supportsSecureCoding {
    return YES;
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeObject:@(self.targetOid) forKey:@"targetOid"];
    [coder encodeObject:NSStringFromSelector(self.setterSelector) forKey:@"setterSelector"];
    [coder encodeInteger:self.attrType forKey:@"attrType"];
    [coder encodeObject:self.value forKey:@"value"];
    [coder encodeObject:self.clientReadableVersion forKey:@"clientReadableVersion"];
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    if (self = [super init]) {
        self.targetOid = [[coder decodeObjectForKey:@"targetOid"] unsignedLongValue];
        NSString *selStr = [coder decodeObjectForKey:@"setterSelector"];
        if (selStr) {
            self.setterSelector = NSSelectorFromString(selStr);
        }
        self.attrType = [coder decodeIntegerForKey:@"attrType"];
        self.value = [coder decodeObjectForKey:@"value"];
        self.clientReadableVersion = [coder decodeObjectForKey:@"clientReadableVersion"];
    }
    return self;
}

@end

#endif /* SHOULD_COMPILE_LOOKIN_SERVER */
