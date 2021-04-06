//
//  QRCodeScanningViewController.h
//  flutter_dong_scan
//
//  Created by hsk on 2021/4/6.
//

#import <UIKit/UIKit.h>
#import "SDScanConfig.h"
NS_ASSUME_NONNULL_BEGIN

@interface QRCodeScanningViewController : UIViewController
- (instancetype)initWithConfig:(SDScanConfig *)scanConfig;
@end

NS_ASSUME_NONNULL_END
