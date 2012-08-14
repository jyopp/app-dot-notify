//
//  ADNAppDelegate.h
//  AppDotNotify
//
//  Created by James Yopp on 2012/08/12.
//  Copyright (c) 2012年 James Yopp. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface ADNAppDelegate : NSObject <NSApplicationDelegate, NSUserNotificationCenterDelegate> {
	IBOutlet NSMenu *statusMenu;
	IBOutlet NSMenu *pollingSubmenu;
}

- (IBAction)selectPollingInterval:(NSMenuItem*)sender;

@end
