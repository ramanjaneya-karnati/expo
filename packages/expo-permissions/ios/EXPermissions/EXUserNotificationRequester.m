// Copyright © 2018 650 Industries. All rights reserved.

#import <EXPermissions/EXUserNotificationRequester.h>
#import <UIKit/UIKit.h>
#import <EXPermissions/EXPermissions.h>
#import <EXPermissionsInterface/EXUserNotificationCenterProxyInterface.h>

@interface EXUserNotificationRequester ()

@property (nonatomic, strong) EXPromiseResolveBlock resolve;
@property (nonatomic, strong) EXPromiseRejectBlock reject;
@property (nonatomic, weak) id<EXPermissionRequesterDelegate> delegate;
@property (nonatomic, weak) EXModuleRegistry *moduleRegistry;

@end

@implementation EXUserNotificationRequester

- (instancetype)initWithModuleRegistry:(EXModuleRegistry *)moduleRegistry {
  if (self = [super init]) {
    _moduleRegistry = moduleRegistry;
  }
  return self;
}

+ (id<EXUserNotificationCenterProxyInterface>)getCenterWithModuleRegistry:(EXModuleRegistry *) moduleRegistry {
  return [moduleRegistry getModuleImplementingProtocol:@protocol(EXUserNotificationCenterProxyInterface)];
}

+ (NSDictionary *)permissionsWithModuleRegistry:(EXModuleRegistry *)moduleRegistry
{
  dispatch_assert_queue_not(dispatch_get_main_queue());
  dispatch_semaphore_t sem = dispatch_semaphore_create(0);
  __block BOOL allowsSound;
  __block BOOL allowsAlert;
  __block BOOL allowsBadge;
  __block EXPermissionStatus status;

  [[EXUserNotificationRequester getCenterWithModuleRegistry:moduleRegistry] getNotificationSettingsWithCompletionHandler:^(UNNotificationSettings *settings) {
    allowsSound = settings.soundSetting == UNNotificationSettingEnabled;
    allowsAlert = settings.alertSetting == UNNotificationSettingEnabled;
    allowsBadge = settings.badgeSetting == UNNotificationSettingEnabled;

    status = EXPermissionStatusUndetermined;

    if (settings.authorizationStatus == UNAuthorizationStatusAuthorized) {
      status = EXPermissionStatusGranted;
    } else if (settings.authorizationStatus == UNAuthorizationStatusDenied) {
      status = EXPermissionStatusDenied;
    } else {
      status = EXPermissionStatusUndetermined;
    }
    dispatch_semaphore_signal(sem);
  }];

  dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);

  return @{
           @"status": [EXPermissions permissionStringForStatus:status],
           @"allowsSound": @(allowsSound),
           @"allowsAlert": @(allowsAlert),
           @"allowsBadge": @(allowsBadge),
           @"expires": EXPermissionExpiresNever,
           };
}

- (void)setDelegate:(id<EXPermissionRequesterDelegate>)delegate
{
  _delegate = delegate;
}

- (void)requestPermissionsWithResolver:(EXPromiseResolveBlock)resolve rejecter:(EXPromiseRejectBlock)reject
{
  if (_resolve != nil || _reject != nil) {
    reject(@"E_AWAIT_PROMISE", @"Another request for the same permission is already being handled.", nil);
    return;
  }

  _resolve = resolve;
  _reject = reject;

  __weak EXUserNotificationRequester *weakSelf = self;

  UNAuthorizationOptions options = UNAuthorizationOptionAlert + UNAuthorizationOptionSound + UNAuthorizationOptionBadge;
  id<EXUserNotificationCenterProxyInterface> notificationCenter = [EXUserNotificationRequester getCenterWithModuleRegistry:_moduleRegistry];
  [notificationCenter requestAuthorizationWithOptions:options completionHandler:^(BOOL granted, NSError * _Nullable error) {
    id<EXPermissionsModule> permissionsModule = [weakSelf.moduleRegistry getModuleImplementingProtocol:@protocol(EXPermissionsModule)];
    NSAssert(permissionsModule, @"Permissions module is required to properly consume result.");
    dispatch_async(permissionsModule.methodQueue, ^{
      [weakSelf _consumeResolverWithCurrentPermissions];
    });
  }];
}

- (void)_consumeResolverWithCurrentPermissions
{
  if (_resolve) {
    _resolve([[self class] permissionsWithModuleRegistry:_moduleRegistry]);
    _resolve = nil;
    _reject = nil;
  }
  if (_delegate) {
    [_delegate permissionRequesterDidFinish:self];
  }
}

@end
