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
@property (nonatomic) NSString *apiKey;

@end

@implementation JYAppDelegate

@synthesize lastMentionId = _lastMentionId, apiKey = _apiKey;

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
	if (!self.apiKey) {
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
			[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:notification.userInfo[@"url"]]];
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
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	_lastMentionId = lastMentionId;
	if (lastMentionId) {
		[defaults setObject:lastMentionId forKey:@"last_mention"];
	} else {
		[defaults removeObjectForKey:@"last_mention"];
	}
	[defaults synchronize];
}

- (NSString*) lastMentionId {
	if (!_lastMentionId) {
		_lastMentionId = [[NSUserDefaults standardUserDefaults] stringForKey:@"last_mention"] ?: @"0";
		NSLog(@"Read lastMentionId %@", _lastMentionId);
	}
	return _lastMentionId;
}

- (void) setApiKey:(NSString *)apiKey {
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	_apiKey = apiKey;
	if (apiKey) {
		[defaults setObject:apiKey forKey:@"api_key"];
	} else {
		[defaults removeObjectForKey:@"api_key"];
	}
	[defaults synchronize];
}

- (NSString*) apiKey {
	if (!_apiKey) {
		_apiKey = [[NSUserDefaults standardUserDefaults] stringForKey:@"api_key"];
		NSLog(@"Read API Key %@", _apiKey);
	}
	return _apiKey;
}

#pragma mark - Timers

- (id) getJSONForAPIRequest: (NSURLRequest*)request
{
	[[NSURLCache sharedURLCache] removeCachedResponseForRequest:request];
	BOOL mustReauthenticate = NO;
	NSURLResponse *response = nil;
	NSError *error = nil;
	NSData *remoteContent = [NSURLConnection sendSynchronousRequest:request returningResponse:&response error:&error];
	if (error == nil) {
		if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
			NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse*)response;
			switch ([httpResponse statusCode]) {
				case 200: {
					id jsonData = [NSJSONSerialization JSONObjectWithData:remoteContent options:0 error:&error];
					if (!error) {
						return jsonData;
					}
				}
					break;
				case 404:
					NSLog(@"Not Found!");
					break;
				case 403:
					NSLog(@"Unauthorized!");
					mustReauthenticate = YES;
					break;
				default:
					NSLog(@"Got unusable response: %lu", [httpResponse statusCode]);
					break;
				
			}
		}
	} else {
		NSLog(@"ERROR getting content: %@", error);
	}
	if (mustReauthenticate) {
		[self performSelectorOnMainThread:@selector(authenticate) withObject:nil waitUntilDone:NO];
	}
	return nil;
}

- (void) getUserData
{
	NSURL *pollURL = [NSURL URLWithString:@"stream/0/users/me" relativeToURL:[NSURL URLWithString:@"https://alpha-api.app.net"]];
	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
		NSMutableURLRequest *r = [[NSMutableURLRequest alloc] initWithURL:pollURL cachePolicy:NSURLCacheStorageNotAllowed timeoutInterval:15.0];
		[r setAllHTTPHeaderFields:@{ @"Authorization": [NSString stringWithFormat:@"Bearer %@", self.apiKey] }];
		
		NSDictionary *jsonData = [self getJSONForAPIRequest:r];
		if (jsonData) {
			userName = jsonData[@"username"];
			userRealName = jsonData[@"name"];
			userId = jsonData[@"id"];
			NSLog(@"I know who you are! %@ / %@ (%@)", userName, userRealName, userId);
			[self startTimer];
		}
	});
}

- (void) startTimer
{
	static const dispatch_time_t interval = 15ull * NSEC_PER_SEC;
	static const dispatch_time_t jitter = 9000ull;
	if (!timer) {
		__block dispatch_time_t lastFired = dispatch_walltime(NULL, 0);
		timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0));
		
		dispatch_source_set_event_handler(timer, ^{
			dispatch_time_t t = dispatch_walltime(NULL, 0);
			if ((t - lastFired) >= (interval - jitter)) {
				[self check];
				lastFired = t;
			}
		});
		dispatch_source_set_timer(timer, DISPATCH_TIME_NOW, interval, jitter);
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
	
	NSInteger lastMention = [self.lastMentionId integerValue];
	NSArray *jsonData = [self getJSONForAPIRequest:r];
	if (jsonData) {
		
		NSString *newestId = jsonData[0][@"id"];
		if ([newestId compare:self.lastMentionId options:NSNumericSearch] > 0) {
			self.lastMentionId = newestId;
		} else {
			NSLog(@"No new mentions (%lu in list)", jsonData.count);
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
	}
}

@end
