//
//  ADNAppDelegate.m
//  AppDotNotify
//
//  Created by James Yopp on 2012/08/12.
//  Copyright (c) 2012年 James Yopp. All rights reserved.
//

#import "ADNAppDelegate.h"

static dispatch_queue_t serialAPIQueue;

@interface ADNAppDelegate () {
	NSStatusItem *statusItem;
	
	dispatch_source_t timer;
	BOOL timerIsActive;
	dispatch_time_t interval;
	
	NSDictionary *userJSON;
	
	BOOL _doMentions_loaded;
	BOOL _doStream_loaded;
}

@property (nonatomic) NSString *lastMentionId;
@property (nonatomic) NSString *lastStreamId;
@property (nonatomic) NSString *authToken;
@property (nonatomic) NSInteger pollingInterval;

@property (nonatomic) BOOL shouldCheckMentions;
@property (nonatomic) BOOL shouldCheckStream;

@end

@implementation ADNAppDelegate

@synthesize lastMentionId = _lastMentionId, lastStreamId = _lastStreamId;
@synthesize authToken = _authToken, pollingInterval = _pollingInterval;
@synthesize shouldCheckMentions = _shouldCheckMentions, shouldCheckStream = _shouldCheckStream;

- (void) awakeFromNib {
	[self _syncPollingIntervalMenu];
	[self _syncMonitoringMenuItems];
}

+ (void) initialize {
	serialAPIQueue = dispatch_queue_create("com.jyopp.appdotnotify.serial-api-net", DISPATCH_QUEUE_SERIAL);
	[[NSUserDefaults standardUserDefaults] registerDefaults: @{
	 @"check_mentions" : @YES,
	 @"check_stream": @NO,
	 @"polling_interval": @15,
	 }];
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
	if ([self.authToken length]) {
		[self checkToken];
	} else {
		[statusItem setImage:[NSImage imageNamed:@"status_error.png"]];
		[self authenticate];
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
		self.authToken = [url substringFromIndex:NSMaxRange(tkIdRange)];
		[statusItem setImage:[NSImage imageNamed:@"status_icon.png"]];
		[self checkToken];
	}
}

#pragma mark - Notification Center

- (void) showMessageForUser: (NSString*)username body:(NSString*)body url:(NSString*)postURL isMention:(BOOL)mentioned
{
	NSUserNotification *note = [[NSUserNotification alloc] init];
	note.title = [NSString stringWithFormat: (mentioned ? @"%@ mentioned you" : @"%@"), username];
	note.informativeText = body;
	note.actionButtonTitle = @"Reply";
	note.userInfo = @{ @"url" : (postURL ?: @"https://alpha.app.net") };
	note.hasActionButton = mentioned;
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

- (BOOL)userNotificationCenter:(NSUserNotificationCenter *)center shouldPresentNotification:(NSUserNotification *)notification
{
	return !notification.isPresented;
}

#pragma mark - Menu Items

- (void) _syncPollingIntervalMenu {
	NSInteger currentInterval = self.pollingInterval;
	for (NSMenuItem* subitem in pollingSubmenu.itemArray) {
		subitem.state = (subitem.tag == currentInterval) ? NSOnState : NSOffState;
	}
}

- (void) _syncMonitoringMenuItems {
	[mentionsMenuItem setState: self.shouldCheckMentions ? NSOnState : NSOffState];
	[streamMenuItem setState:self.shouldCheckStream ? NSOnState : NSOffState];
}

- (void) selectPollingInterval:(NSMenuItem *)sender {
	[self setPollingInterval:sender.tag];
}

- (void) toggleMentions:(id)sender {
	self.shouldCheckMentions = mentionsMenuItem.state != NSOnState;
	[self _syncMonitoringMenuItems];
}

- (void) toggleStream:(id)sender {
	self.shouldCheckStream = streamMenuItem.state != NSOnState;
	[self _syncMonitoringMenuItems];
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

- (void) setLastStreamId:(NSString *)lastStreamId {
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	_lastStreamId = lastStreamId;
	if (lastStreamId) {
		[defaults setObject:lastStreamId forKey:@"last_stream"];
	} else {
		[defaults removeObjectForKey:@"last_stream"];
	}
	[defaults synchronize];
}

- (NSString*) lastStreamId {
	if (!_lastStreamId) {
		_lastStreamId = [[NSUserDefaults standardUserDefaults] stringForKey:@"last_stream"] ?: @"0";
		NSLog(@"Read lastStreamId %@", _lastStreamId);
	}
	return _lastStreamId;
}

- (void) setAuthToken:(NSString *)apiKey {
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	_authToken = apiKey;
	if (apiKey) {
		[defaults setObject:apiKey forKey:@"api_key"];
	} else {
		[defaults removeObjectForKey:@"api_key"];
	}
	[defaults synchronize];
}

- (NSString*) authToken {
	if (!_authToken) {
		_authToken = [[NSUserDefaults standardUserDefaults] stringForKey:@"api_key"];
		NSLog(@"Read API Key %@", _authToken);
	}
	return _authToken;
}

- (void) setPollingInterval:(NSInteger)pollingInterval {
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	_pollingInterval = pollingInterval;
	[defaults setInteger:pollingInterval forKey:@"polling_interval"];
	[defaults synchronize];
	NSLog(@"Set Polling Interval to %li seconds", pollingInterval);
	// Update the timer's schedule if it is running
	if (timerIsActive) {
		[self startTimer];
	}
	[self _syncPollingIntervalMenu];
}

- (NSInteger) pollingInterval {
	if (!_pollingInterval) {
		_pollingInterval = [[NSUserDefaults standardUserDefaults] integerForKey:@"polling_interval"];
		NSLog(@"Read Polling Interval %li", _pollingInterval);
	}
	return _pollingInterval ?: 15;
}

- (BOOL) shouldCheckMentions {
	if (!_doMentions_loaded) {
		_doMentions_loaded = YES;
		_shouldCheckMentions = [[NSUserDefaults standardUserDefaults] boolForKey:@"check_mentions"];
	}
	return _shouldCheckMentions;
}

- (void) setShouldCheckMentions:(BOOL)doMentions {
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	_shouldCheckMentions = doMentions;
	[defaults setBool:doMentions forKey:@"check_mentions"];
	[defaults synchronize];
	_doMentions_loaded = YES;
}

- (BOOL) shouldCheckStream {
	if (!_doStream_loaded) {
		_doStream_loaded = YES;
		_shouldCheckStream = [[NSUserDefaults standardUserDefaults] boolForKey:@"check_stream"];
	}
	return _shouldCheckStream;
}

- (void) setShouldCheckStream:(BOOL)doStream {
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	_shouldCheckStream = doStream;
	[defaults setBool:doStream forKey:@"check_stream"];
	[defaults synchronize];
	_doStream_loaded = YES;
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
				case 403:
					NSLog(@"Unauthorized!");
					mustReauthenticate = YES;
					break;
				case 429:
					// TODO: Read the next-available interval from the header and return nil until that time is passed.
					NSLog(@"Got Rate Limit response.");
					break;
				default:
					NSLog(@"Got unusable response: %lu for URL %@", [httpResponse statusCode], [request.URL absoluteString]);
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

- (void) checkToken
{
	NSURL *pollURL = [NSURL URLWithString:@"stream/0/token" relativeToURL:[NSURL URLWithString:@"https://alpha-api.app.net"]];
	dispatch_async(serialAPIQueue, ^{
		NSMutableURLRequest *r = [[NSMutableURLRequest alloc] initWithURL:pollURL cachePolicy:NSURLCacheStorageNotAllowed timeoutInterval:15.0];
		[r setAllHTTPHeaderFields:@{ @"Authorization": [NSString stringWithFormat:@"Bearer %@", self.authToken] }];
		
		NSDictionary *jsonData = [self getJSONForAPIRequest:r];
		if (jsonData) {
			userJSON = jsonData[@"user"];
			if (userJSON) {
				NSLog(@"I know who you are! %@ / %@ (%@)", userJSON[@"username"], userJSON[@"name"], userJSON[@"id"]);
				[self startTimer];
			}
		}
	});
}

- (dispatch_time_t) _timerInterval {
	return (dispatch_time_t)(self.pollingInterval) * NSEC_PER_SEC;
}

- (void) startTimer
{
	static const dispatch_time_t jitter = 9000ull;
	if (!timer) {
		__block dispatch_time_t lastFired = dispatch_walltime(NULL, 0);
		timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, serialAPIQueue);
		
		dispatch_source_set_event_handler(timer, ^{
			dispatch_time_t t = dispatch_walltime(NULL, 0);
			if ((t - lastFired) >= ([self _timerInterval] - jitter)) {
				if (self.shouldCheckMentions) {
					[self checkMentions];
				}
				if (self.shouldCheckStream) {
					[self checkStream];
				}
				lastFired = t;
			}
		});
	}
	if (timer) {
		dispatch_source_set_timer(timer, DISPATCH_TIME_NOW, [self _timerInterval], jitter);
		if (!timerIsActive) {
			dispatch_resume(timer);
			timerIsActive = YES;
		}
	}
}

- (void) stopTimer
{
	if (timerIsActive) {
		timerIsActive = NO;
		dispatch_suspend(timer);
	}
}

- (void) checkStream
{
	// This should be called on a background thread.
	NSURL *pollURL = [NSURL URLWithString:[NSString stringWithFormat:@"stream/0/posts/stream?since_id=%ld",
										   [self.lastStreamId integerValue]]
							relativeToURL:[NSURL URLWithString:@"https://alpha-api.app.net"]];
	NSMutableURLRequest *r = [[NSMutableURLRequest alloc] initWithURL:pollURL cachePolicy:NSURLCacheStorageNotAllowed timeoutInterval:15.0];
	[r setAllHTTPHeaderFields:@{ @"Authorization": [NSString stringWithFormat:@"Bearer %@", self.authToken] }];
	
	NSInteger lastStream = [self.lastStreamId integerValue];
	NSArray *jsonData = [self getJSONForAPIRequest:r];
	if ([jsonData count] > 0) {
		
		NSString *newestId = jsonData[0][@"id"];
		if ([newestId compare:self.lastStreamId options:NSNumericSearch] > 0) {
			self.lastStreamId = newestId;
		} else {
//			NSLog(@"No new posts (%lu in stream)", jsonData.count);
		}
		
		for (NSDictionary *mention in jsonData) {
			NSString *text = mention[@"text"];
			NSString *user = mention[@"user"][@"name"];
			NSString *username = mention[@"user"][@"username"];
			NSString *postId = mention[@"id"];
			if (postId && ([postId integerValue] > lastStream)) {
				NSString *postURLString = [NSString stringWithFormat:@"https://alpha.app.net/%@/post/%@", username, postId];
				dispatch_async(dispatch_get_main_queue(), ^{
					if (text) {
						// Deleted posts seem to have nil text.
						[self showMessageForUser:user body:text url:postURLString isMention:NO];
					}
					NSLog(@"[%@] Post by %@: %@", postId, user, text);
				});
			}
		}
	} else {
	//	NSLog(@"No new posts in timeline");
	}
}

- (void) checkMentions
{
	// This should be called on a background thread.
	NSURL *pollURL = [NSURL URLWithString:[NSString stringWithFormat:@"stream/0/users/%@/mentions?since_id=%ld", userJSON[@"id"], [self.lastMentionId integerValue]]
							relativeToURL:[NSURL URLWithString:@"https://alpha-api.app.net"]];
	NSMutableURLRequest *r = [[NSMutableURLRequest alloc] initWithURL:pollURL cachePolicy:NSURLCacheStorageNotAllowed timeoutInterval:15.0];
	[r setAllHTTPHeaderFields:@{ @"Authorization": [NSString stringWithFormat:@"Bearer %@", self.authToken] }];
	
	NSInteger lastMention = [self.lastMentionId integerValue];
	NSArray *jsonData = [self getJSONForAPIRequest:r];
	if ([jsonData count] > 0) {
		
		NSString *newestId = jsonData[0][@"id"];
		if ([newestId compare:self.lastMentionId options:NSNumericSearch] > 0) {
			self.lastMentionId = newestId;
		} else {
//			NSLog(@"No new mentions (%lu in list)", jsonData.count);
		}
		
		for (NSDictionary *mention in jsonData) {
			NSString *text = mention[@"text"];
			NSString *user = mention[@"user"][@"name"];
			NSString *username = mention[@"user"][@"username"];
			NSString *postId = mention[@"id"];
			if (postId && ([postId integerValue] > lastMention)) {
				NSString *postURLString = [NSString stringWithFormat:@"https://alpha.app.net/%@/post/%@", username, postId];
				dispatch_async(dispatch_get_main_queue(), ^{
					if (text) {
						// Deleted posts seem to have nil text
						[self showMessageForUser:user body:text url:postURLString isMention:YES];
					}
					NSLog(@"[%@] Mentioned by %@: %@", postId, user, text);
				});
			}
		}
	} else {
	//	NSLog(@"No new mentions in timeline");
	}
}

@end
