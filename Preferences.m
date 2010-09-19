//
//  Preferences.m
//  MacDroidNotifier
//
//  Created by Rodrigo Damazio on 27/12/09.
//

#import "Preferences.h"
#import "Notification.h"
#import "StartupItem.h"

NSString *const kPreferencesPairedDevicesKey = @"pairedDevices";
NSString *const kPreferencesPairingRequiredKey = @"pairingRequired";
NSString *const kPreferencesListenUdpKey = @"listenWifi";
NSString *const kPreferencesListenTcpKey = @"listenTcp";
NSString *const kPreferencesListenBluetoothKey = @"listenBluetooth";
NSString *const kPreferencesListenUsbKey = @"listenUsb";

NSString *const kPreferencesRingKey = @"ring";
NSString *const kPreferencesSmsKey = @"sms";
NSString *const kPreferencesMmsKey = @"mms";
NSString *const kPreferencesBatteryKey = @"battery";
NSString *const kPreferencesVoicemailKey = @"voicemail";
NSString *const kPreferencesPingKey = @"ping";
NSString *const kPreferencesUserKey = @"user";

NSString *const kPreferencesDisplayKey = @"display";
NSString *const kPreferencesMuteKey = @"mute";
NSString *const kPreferencesExecuteKey = @"execute";
NSString *const kPreferencesExecuteActionKey = @"executeAction";
NSString *const kPreferencesCopyKey = @"copy";

const NSInteger kPairingNotRequired = 0;
const NSInteger kPairingRequired = 1;

@implementation Preferences

+ (void)setBool:(BOOL)value
     forTypeKey:(NSString *)typeKey
   forActionKey:(NSString *)actionKey
   inDictionary:(NSMutableDictionary *)dict {
  NSString *key = [NSString stringWithFormat:@"%@.%@", typeKey, actionKey];
  [dict setObject:[NSNumber numberWithBool:value] forKey:key];
}

+ (void)initialize {
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

  NSMutableDictionary *settings =
      [NSMutableDictionary dictionaryWithObjectsAndKeys:
          [NSArray array], kPreferencesPairedDevicesKey,
          [NSNumber numberWithInteger:kPairingNotRequired], kPreferencesPairingRequiredKey,
          [NSNumber numberWithBool:YES], kPreferencesListenUdpKey,
          [NSNumber numberWithBool:YES], kPreferencesListenTcpKey,
          [NSNumber numberWithBool:YES], kPreferencesListenBluetoothKey,
          [NSNumber numberWithBool:NO],  kPreferencesListenUsbKey,
          nil];

  // Set defaults for actions
  [self setBool:YES
     forTypeKey:kPreferencesRingKey
   forActionKey:kPreferencesDisplayKey
   inDictionary:settings];
  [self setBool:YES
     forTypeKey:kPreferencesRingKey
   forActionKey:kPreferencesMuteKey
   inDictionary:settings];
  [self setBool:YES
     forTypeKey:kPreferencesSmsKey
   forActionKey:kPreferencesDisplayKey
   inDictionary:settings];
  [self setBool:YES
     forTypeKey:kPreferencesMmsKey
   forActionKey:kPreferencesDisplayKey
   inDictionary:settings];
  [self setBool:YES
     forTypeKey:kPreferencesBatteryKey
   forActionKey:kPreferencesDisplayKey
   inDictionary:settings];
  [self setBool:YES
     forTypeKey:kPreferencesPingKey
   forActionKey:kPreferencesDisplayKey
   inDictionary:settings];
  [self setBool:YES
     forTypeKey:kPreferencesVoicemailKey
   forActionKey:kPreferencesDisplayKey
   inDictionary:settings];
  [self setBool:YES
     forTypeKey:kPreferencesUserKey
   forActionKey:kPreferencesDisplayKey
   inDictionary:settings];

  [[NSUserDefaults standardUserDefaults] registerDefaults:settings];
  [[NSUserDefaults standardUserDefaults] synchronize];
  [pool release];
}

- (void)awakeFromNib {
  [self updateDevicesMenuWithDefaults:[NSUserDefaults standardUserDefaults]];
}

- (id)init {
  if (self = [super init]) {
    isPairing = NO;
  }
  return self;
}

- (void)updatePairingUI {
  NSInteger selectedTag = [pairingRadioGroup selectedTag];
  BOOL enablePairingUI = (selectedTag == kPairingRequired) ? YES : NO;

  [pairedDevicesView setEnabled:enablePairingUI];
  [addPairedDeviceButton setEnabled:enablePairingUI];
  [removePairedDeviceButton setEnabled:enablePairingUI];
}

- (void)updateExecuteAction {
  NSString *targetName = [[NSUserDefaults standardUserDefaults] objectForKey:kPreferencesExecuteActionKey];
  NSString *displayedString = nil;
  if (targetName != nil) {
    displayedString = [NSString stringWithFormat:
        NSLocalizedString(@"Executes: %@", @"Text for UI element which shows what will be executed for notifications"),
        [targetName lastPathComponent]];
  } else {
    displayedString = NSLocalizedString(@"Executes: nothing (click \"...\" to pick target)",
        @"Text for UI element when no execution target has been selected");
  }
  [executedName setStringValue:displayedString];
}

- (void)showDialog:(id)sender {
  [NSApp activateIgnoringOtherApps:YES];
  [prefsWindow makeKeyAndOrderFront:sender];
  [self updatePairingUI];
  [self updateExecuteAction];
  [startupItem forceValueUpdate];
}

- (void)windowWillClose:(NSNotification *)note {
  if ([note object] == prefsWindow) {
    [prefsWindow endEditingFor:nil];

    // Save the updated preferences
    NSLog(@"Saving preferences");
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];

    // If pairing required but no devices paired, switch to no pairing required
    if ([ud integerForKey:kPreferencesPairingRequiredKey] == kPairingRequired &&
        [[ud arrayForKey:kPreferencesPairedDevicesKey] count] == 0) {
      NSLog(@"Pairing set to required but no devices paired, switching to not required.");
      [ud setInteger:kPairingNotRequired forKey:kPreferencesPairingRequiredKey];
    }

    [ud synchronize];
    [self updateDevicesMenuWithDefaults:ud];
  }
}

- (IBAction)pairingRequiredToggled:(id)sender {
  [self updatePairingUI];
}

- (IBAction)addPairedDeviceClicked:(id)sender {
  // Save notification settings since we'll now listen for notifications
  [[NSUserDefaults standardUserDefaults] synchronize];

  isPairing = YES;
  [NSApp beginSheet:pairingSheet
     modalForWindow:prefsWindow
      modalDelegate:self
     didEndSelector:@selector(didEndPairing:returnCode:contextInfo:)
        contextInfo:0];
}

- (void)handlePairingNotification:(Notification *)notification {
  // Only let through if we're in pairing mode
  if (!isPairing) {
    return;
  }

  // Only let ping notifications through
  if ([notification type] != PING) {
    return;
  }

  @synchronized(self) {
    // Ensure the device is not already in the paired devices list
    NSString *deviceId = [notification deviceId];
    for (id pairedDeviceId in [pairedDevicesModel arrangedObjects]) {
      NSDictionary *pairedDevice = pairedDeviceId;
      if ([[pairedDevice objectForKey:@"deviceId"] isEqualToString:deviceId]) {
        NSLog(@"Tried to pair with device %@ - already paired.", deviceId);
        return;
      }
    }

    NSDictionary *newDevice =
        [NSDictionary dictionaryWithObjectsAndKeys:deviceId, @"deviceId",
                                              @"New device", @"deviceName",
                                              nil];
    [pairedDevicesModel addObject:newDevice];
  }
  [NSApp endSheet:pairingSheet];
}

- (IBAction)cancelPairing:(id)sender {
  [NSApp endSheet:pairingSheet];
}

- (void)didEndPairing:(NSWindow *)sheet
          returnCode:(int)success
          contextInfo:(void *)rowInfo {
  [sheet orderOut:self];
  isPairing = NO;
}

- (NSString *)applicationsDirectory {
  NSMutableArray *paths = [NSMutableArray array];
  [paths addObjectsFromArray:NSSearchPathForDirectoriesInDomains(NSApplicationDirectory, NSUserDomainMask, NO)];
  [paths addObjectsFromArray:NSSearchPathForDirectoriesInDomains(NSApplicationDirectory, NSLocalDomainMask, NO)];

  for (NSString *path in paths) {
    BOOL isDir;
    if ([[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDir] && isDir) {
      return path;
    }
  }

  return nil;
}

- (IBAction)selectExecuteAction:(id)sender {
  NSOpenPanel *openPanel = [NSOpenPanel openPanel];
  [openPanel setCanChooseFiles:YES];
  [openPanel setCanChooseDirectories:NO];
  [openPanel setResolvesAliases:YES];
  [openPanel setAllowsMultipleSelection:NO];
  [openPanel setTitle:NSLocalizedString(@"Choose application to execute",
                                        @"Title of execution target selection dialog")];
  [openPanel setMessage:NSLocalizedString(
      @"Choose an application, script or file to be opened when a notification arrives.",
      @"Description shown in execution target selection dialog")];

  NSInteger result = [openPanel runModalForDirectory:[self applicationsDirectory]
                                                file:nil
                                               types:nil];
  if (result == NSOKButton) {
    NSString *targetName = [[openPanel filenames] objectAtIndex:0];
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    [ud setObject:targetName forKey:kPreferencesExecuteActionKey];
    [self updateExecuteAction];
  }
}

- (void)updateDevicesMenuWithDefaults:(NSUserDefaults *)defaults {
  [mainMenu removeItemAtIndex:0];
/* TODO: Re-enable commands
  // Clear previous paired devices
  while ([mainMenu numberOfItems]) {
    NSMenuItem *item = [mainMenu itemAtIndex:0];

    if ([item isSeparatorItem])
      break;

    [mainMenu removeItemAtIndex:0];
  }

  // Populate the paired devices into the menu
  NSArray *pairedDevices = [defaults arrayForKey:kPreferencesPairedDevicesKey];
  for (uint i = 0; i < [pairedDevices count]; i++) {
    NSDictionary *pairedDevice = [pairedDevices objectAtIndex:i];    
    NSString *pairedDeviceId = [pairedDevice objectForKey:@"deviceId"];
    NSString *pairedDeviceName = [pairedDevice objectForKey:@"deviceName"];

    // Add the menu item
    NSMenuItem *deviceMenuItem =
        [[[NSMenuItem alloc] initWithTitle:pairedDeviceName
                                   action:NULL
                            keyEquivalent:@""] autorelease];
    [mainMenu insertItem:deviceMenuItem atIndex:0];

    // Add the submenu
    NSMenu *deviceMenu = [deviceMenuTemplate copy];
    [deviceMenuItem setSubmenu:deviceMenu];

    // Tag all the submenu items
    NSArray *items = [deviceMenu itemArray];
    for (NSMenuItem *item in items) {
      [item setRepresentedObject:pairedDeviceId];
    }
  }
 */
}  

@end