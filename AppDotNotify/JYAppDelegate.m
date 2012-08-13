//
//  JYAppDelegate.m
//  AppDotNotify
//
//  Created by James Yopp on 2012/08/12.
//  Copyright (c) 2012年 James Yopp. All rights reserved.
//

#import "JYAppDelegate.h"

@interface JYAppDelegate () {
	NSStatusItem *statusItem;
	
	dispatch_source_t timer;
	
	NSNumber *userId;
	NSString *userName;
	NSString *userRealName;
}

@property (nonatomic) NSString *lastMentionId;

@end

@implementation JYAppDelegate

- (void) awakeFromNib {
}

- (void) applicationWillFinishLaunching:(NSNotification *)notification {
	// Register handlers for startup events
	[[NSUserNotificationCenter defaultUserNotificationCenter] setDelegate:self];
	[[NSAppleEventManager sharedAppleEventManager] setEventHandler:self
													   andSelector:@selector(receivedURL:withReplyEvent:)
													 forEventClass:kInternetEventClass
														andEventID:kAEGetURL];
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
	// Register a menu
	statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSSquareStatusItemLength];
	[statusItem setImage:[NSImage imageNamed:@"status_icon.png"]];
	[statusItem setHighlightMode:YES];
	[statusItem setMenu:statusMenu];
	// Check the presence of the API key.
	NSString *storedKey = [[NSUserDefaults standardUserDefaults] objectForKey:@"api_key"];
	if ([storedKey length] < 20) {
		[self authenticate];
		[statusItem setImage:[NSImage imageNamed:@"status_error.png"]];
	} else {
		self.apiKey = storedKey;
		[self getUserData];
	}
}

#pragma mark - Authentication and URL handling

- (void) authenticate {
	NSString *urlString = [NSString stringWithFormat:
						   @"https://alpha.app.net/oauth/authenticate?client_id=Qu4hS34E8dNBpfmNuHhNYfQXC8zgCf9Q" \
						   "&response_type=token" \
						   "&redirect_uri=com.jyopp.osx.appdotnotify://api-key/" \
						   "&scope=stream"];
	NSURL *url = [NSURL URLWithString:urlString];
	[[NSWorkspace sharedWorkspace] openURL:url];
}

- (void) receivedURL: (NSAppleEventDescriptor*)event withReplyEvent: (NSAppleEventDescriptor*)replyEvent
{
	NSString *url = [[event paramDescriptorForKeyword:keyDirectObject] stringValue];
	NSRange tkIdRange = [url rangeOfString:@"#access_token="];
	if (tkIdRange.location != NSNotFound) {
		self.apiKey = [url substringFromIndex:NSMaxRange(tkIdRange)];
		[[NSUserDefaults standardUserDefaults] setObject:self.apiKey forKey:@"api_key"];
		[[NSUserDefaults standardUserDefaults] synchronize];
		[statusItem setImage:[NSImage imageNamed:@"status_icon.png"]];
		[self getUserData];
	}
}

#pragma mark - Notification Center

- (void) showMessageForUser: (NSString*)username body:(NSString*)body url:(NSString*)postURL
{
	NSUserNotification *note = [[NSUserNotification alloc] init];
	note.title = [NSString stringWithFormat:@"@%@ on app.net:", username];
	note.informativeText = body;
	note.actionButtonTitle = @"Reply";
	note.userInfo = @{ @"url" : (postURL ?: @"https://alpha.app.net") };
	[[NSUserNotificationCenter defaultUserNotificationCenter] deliverNotification:note];
}

- (void)userNotificationCenter:(NSUserNotificationCenter *)center didActivateNotification:(NSUserNotification *)notification
{
	[center removeDeliveredNotification:notification];
	switch (notification.activationType) {
		case NSUserNotificationActivationTypeActionButtonClicked:
			NSLog(@"Reply Button was clicked -> quick reply");
			break;
		case NSUserNotificationActivationTypeContentsClicked:
			NSLog(@"Notification body was clicked -> redirect to item");
			[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:notification.userInfo[@"url"]]];
			break;
		default:
			NSLog(@"Notfiication appears to have been dismissed!");
			break;
	}
}

#pragma mark - Persistent Properties

- (void) setLastMentionId:(NSString *)lastMentionId {
	[[NSUserDefaults standardUserDefaults] setObject:lastMentionId forKey:@"last_mention"];
	[[NSUserDefaults standardUserDefaults] synchronize];
}

- (NSString*) lastMentionId {
	NSString *rVal = [[NSUserDefaults standardUserDefaults] stringForKey:@"last_mention"] ?: @"0";
	NSLog(@"Using lastMentionId %@", rVal);
	return rVal;
}

#pragma mark - Timers

- (void) getUserData
{
	NSURL *pollURL = [NSURL URLWithString:@"stream/0/users/me" relativeToURL:[NSURL URLWithString:@"https://alpha-api.app.net"]];
	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
		NSMutableURLRequest *r = [[NSMutableURLRequest alloc] initWithURL:pollURL cachePolicy:NSURLCacheStorageNotAllowed timeoutInterval:15.0];
		[r setAllHTTPHeaderFields:@{ @"Authorization": [NSString stringWithFormat:@"Bearer %@", self.apiKey] }];
		NSURLResponse *response = nil;
		NSError *error = nil;
		NSData *remoteContent = [NSURLConnection sendSynchronousRequest:r returningResponse:&response error:&error];
		if (error == nil) {
			NSDictionary *jsonData = [NSJSONSerialization JSONObjectWithData:remoteContent options:0 error:&error];
			if (error == nil) {
				userName = jsonData[@"username"];
				userRealName = jsonData[@"name"];
				userId = jsonData[@"id"];
				NSLog(@"I know who you are! %@ / %@ (%@)", userName, userRealName, userId);
				[self startTimer];
			} else {
				NSLog(@"ERROR parsing JSON: %@", error);
			}
		} else {
			NSLog(@"ERROR getting content: %@", error);
			[self authenticate];
		}
	});
}

- (void) startTimer
{
	if (!timer) {
		__block dispatch_time_t lastFired = dispatch_walltime(NULL, 0);
		timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0));
		
		dispatch_source_set_event_handler(timer, ^{
			dispatch_time_t t = dispatch_walltime(NULL, 0);
			if ((t - lastFired) >= 15ull * NSEC_PER_SEC) {
				[self check];
				lastFired = t;
			}
		});
		dispatch_source_set_timer(timer, DISPATCH_TIME_NOW, 15ull * NSEC_PER_SEC, 9000ull);
	}
	if (timer) dispatch_resume(timer);
}

- (void) stopTimer
{
	if (timer) dispatch_suspend(timer);
}

- (void) check
{
	// This should be called on a background thread.
	NSURL *pollURL = [NSURL URLWithString:[NSString stringWithFormat:@"stream/0/users/%@/mentions", userId]
							relativeToURL:[NSURL URLWithString:@"https://alpha-api.app.net"]];
	NSMutableURLRequest *r = [[NSMutableURLRequest alloc] initWithURL:pollURL cachePolicy:NSURLCacheStorageNotAllowed timeoutInterval:15.0];
	[r setAllHTTPHeaderFields:@{ @"Authorization": [NSString stringWithFormat:@"Bearer %@", self.apiKey],
								 @"min_id": self.lastMentionId }];
	NSURLResponse *response = nil;
	NSError *error = nil;
	NSData *remoteContent = [NSURLConnection sendSynchronousRequest:r returningResponse:&response error:&error];
	if (error == nil) {
		NSLog(@"Got response %@", response);
		NSInteger lastMention = [self.lastMentionId integerValue];
		NSArray *jsonData = [NSJSONSerialization JSONObjectWithData:remoteContent options:0 error:&error];
		if (error == nil) {
			NSLog(@"Got %ld Mentions", jsonData.count);
			NSString *newestId = jsonData[0][@"id"];
			if (newestId) {
				self.lastMentionId = newestId;
			}
			for (NSDictionary *mention in jsonData) {
				NSString *text = mention[@"text"];
				NSString *user = mention[@"user"][@"name"];
				NSString *username = mention[@"user"][@"username"];
				NSString *postId = mention[@"id"];
				if (postId && ([postId integerValue] > lastMention)) {
					NSString *postURLString = [NSString stringWithFormat:@"https://alpha.app.net/%@/post/%@", username, postId];
					dispatch_async(dispatch_get_main_queue(), ^{
						[self showMessageForUser:user body:text url:postURLString];
						NSLog(@"[%@] Mentioned by %@: %@", postId, user, text);
					});
				}
			}
		} else {
			NSLog(@"ERROR parsing JSON: %@", error);
			[self stopTimer];
		}
	} else {
		NSLog(@"ERROR getting content: %@", error);
		[self stopTimer];
	}
}

@end
