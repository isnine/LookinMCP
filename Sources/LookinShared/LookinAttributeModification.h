
//
//  LookinAttributeModification.h
//  LookinMCP
//
//  Represents a request to modify an attribute on a view or layer.
//  Sent as the payload for request type 204 (InbuiltAttrModification).
//

#import <Foundation/Foundation.h>
#import "LookinAttrType.h"

@interface LookinAttributeModification : NSObject <NSSecureCoding>

/// OID of the target view or layer.
@property(nonatomic, assign) unsigned long targetOid;

/// The setter selector to invoke (e.g. @selector(setHidden:)).
@property(nonatomic, assign) SEL setterSelector;

/// Determines how to interpret `value` on the server side.
@property(nonatomic, assign) LookinAttrType attrType;

/// The new value. Type depends on attrType:
///  - LookinAttrTypeUIColor: NSArray<NSNumber *> with 4 RGBA floats (0.0-1.0)
///  - LookinAttrTypeCGRect/CGPoint/CGSize: NSValue
///  - LookinAttrTypeBOOL/Int/Float/Double: NSNumber
///  - LookinAttrTypeNSString: NSString
///  - LookinAttrTypeUIEdgeInsets: NSValue
@property(nonatomic, strong) id value;

/// Client version string for compatibility checks.
@property(nonatomic, copy) NSString *clientReadableVersion;

@end
