//
//  JYAppDelegate.h
//  AppDotNotify
//
//  Created by James Yopp on 2012/08/12.
//  Copyright (c) 2012年 James Yopp. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface JYAppDelegate : NSObject <NSApplicationDelegate, NSUserNotificationCenterDelegate> {
	IBOutlet NSMenu *statusMenu;
}

@property (assign) IBOutlet NSWindow *window;
@property NSString* apiKey;

@end