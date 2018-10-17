//
//  ANGLAppDelegate.m
//  AngelPlayer
//
//  Created by Uli Kusterer on 17.10.18.
//  Copyright © 2018 Uli Kusterer. All rights reserved.
//

#import "ANGLAppDelegate.h"
#import <math.h>
@import AVKit;


@interface ANGLAppDelegate () <NSWindowDelegate>
{
	BOOL _shouldPlayWhenReady;
	BOOL _pinRightNotLeft;
	BOOL _pinBottomNotTop;
	NSURL *_currentItemURL;
}

@property (weak) IBOutlet NSWindow *window;
@property (weak) IBOutlet AVPlayerView *avPlayerView;
@property (weak) IBOutlet NSProgressIndicator *volumeProgressIndicator;

@property AVQueuePlayer *avPlayer;
@property NSMutableArray<NSURL *> *playbackURLs;

@end


void *ANGLAppDelegatePlayerStatusKVOContext = &ANGLAppDelegatePlayerStatusKVOContext;
void *ANGLAppDelegatePlayerCurrentItemKVOContext = &ANGLAppDelegatePlayerCurrentItemKVOContext;


@implementation ANGLAppDelegate

-(void)	applicationDidFinishLaunching: (NSNotification *)aNotification
{
	self.volumeProgressIndicator.alphaValue = 0.0;
	
	[self updateCornerPinning];
	
	self.playbackURLs = [NSMutableArray new];
	self.avPlayer = [AVQueuePlayer queuePlayerWithItems:@[]];
	float desiredVolume = 1.0;
	NSNumber *desiredVolumeObj = [NSUserDefaults.standardUserDefaults objectForKey: @"ANGLSoundVolume"];
	if( desiredVolumeObj )
	{
		desiredVolume = desiredVolumeObj.floatValue;
	}
	self.avPlayer.volume = desiredVolume;
	[self.avPlayer addObserver:self forKeyPath:@"status" options:0 context:ANGLAppDelegatePlayerStatusKVOContext];
	[self.avPlayer addObserver:self forKeyPath:@"currentItem" options:0 context:ANGLAppDelegatePlayerCurrentItemKVOContext];
	self.avPlayerView.player = self.avPlayer;

	NSArray<NSData *> *openBookmarks = [NSUserDefaults.standardUserDefaults objectForKey:@"ANGLRecentFiles"];
	NSMutableArray<NSURL *> *openURLs = [NSMutableArray new];
	for( NSData *currBookmarkData in openBookmarks )
	{
		NSError *err = nil;
		NSURL *currentURL = [NSURL URLByResolvingBookmarkData:currBookmarkData options:NSURLBookmarkResolutionWithSecurityScope | NSURLBookmarkResolutionWithoutUI relativeToURL:nil bookmarkDataIsStale:NULL error:&err];
		if( currentURL )
		{
			[openURLs addObject: currentURL];
		}
		else
		{
			NSLog(@"Couldn't load file reference: %@", err);
		}
	}
	
	[self addURLs: openURLs];
}


-(void)	applicationWillTerminate: (NSNotification *)aNotification
{
	NSMutableArray<NSData *> *openURLs = [NSMutableArray new];
	
	for( NSURL *currentFile in self.playbackURLs )
	{
		NSError *err = nil;
		NSData *currBookmarkData = [currentFile bookmarkDataWithOptions:NSURLBookmarkCreationWithSecurityScope | NSURLBookmarkCreationSecurityScopeAllowOnlyReadAccess includingResourceValuesForKeys:nil relativeToURL:nil error:&err];
		if( currBookmarkData )
		{
			[openURLs addObject: currBookmarkData];
		}
		else
		{
			NSLog(@"Couldn't save file reference: %@", err);
			[NSApplication.sharedApplication presentError:err modalForWindow:self.window delegate:nil didPresentSelector:nil contextInfo:NULL];
		}
	}
	
	[NSUserDefaults.standardUserDefaults setObject:openURLs forKey:@"ANGLRecentFiles"];
	[NSUserDefaults.standardUserDefaults setObject: @(self.avPlayer.volume) forKey: @"ANGLSoundVolume"];
}


-(void)	application: (NSApplication *)application openURLs: (NSArray<NSURL *> *)urls
{
	[self addURLs: urls];
}


-(void) addURLs: (NSArray<NSURL *> *)urls
{
	[self.playbackURLs addObjectsFromArray: urls];
	
	for( NSURL *currURL in urls )
	{
		if( [currURL.pathExtension caseInsensitiveCompare:@"mp4"] == NSOrderedSame || [currURL.pathExtension caseInsensitiveCompare:@"m4v"] == NSOrderedSame )
		{
			AVPlayerItem *avpi = [AVPlayerItem playerItemWithURL: currURL];
			[self.avPlayer insertItem:avpi afterItem:nil];
		}
	}
	
	if( self.avPlayer.status == AVPlayerStatusReadyToPlay )
	{
		[self.avPlayer play];
	}
	else
	{
		_shouldPlayWhenReady = YES;
	}
}


-(void)	windowDidMove: (NSNotification *)notification
{
	[self updateCornerPinning];
}


-(void)	windowDidResize: (NSNotification *)notification
{
	[self updateCornerPinning];
}


-(void) updateCornerPinning
{
	NSRect windowFrame = self.window.frame;
	NSRect screenFrame = self.window.screen.frame;
	
	CGFloat leftDistance = NSMinX(windowFrame) - NSMinX(screenFrame);
	CGFloat rightDistance = NSMaxX(screenFrame) - NSMaxX(windowFrame);
	CGFloat bottomDistance = NSMinY(windowFrame) - NSMinY(screenFrame);
	CGFloat topDistance = NSMaxY(screenFrame) - NSMaxY(windowFrame);
	
	_pinRightNotLeft = (rightDistance < leftDistance);
	_pinBottomNotTop = (bottomDistance < topDistance);
}


-(void)	observeValueForKeyPath: (NSString *)keyPath ofObject: (id)object change: (NSDictionary<NSKeyValueChangeKey,id> *)change context: (void *)context
{
	if( context == ANGLAppDelegatePlayerStatusKVOContext )
	{
		dispatch_async( dispatch_get_main_queue(), ^{
			if( self->_shouldPlayWhenReady && self.avPlayer.status == AVPlayerStatusReadyToPlay )
			{
				[self.avPlayer play];
				self->_shouldPlayWhenReady = NO;
			}
			else if (self.avPlayer.status == AVPlayerStatusFailed)
			{
				[NSApplication.sharedApplication presentError:self.avPlayer.error modalForWindow:self.window delegate:nil didPresentSelector:nil contextInfo:NULL];
			}
		});
	}
	else if( context == ANGLAppDelegatePlayerCurrentItemKVOContext )
	{
		dispatch_async( dispatch_get_main_queue(), ^{
			if( self->_currentItemURL )
			{
				[self.playbackURLs removeObject: self->_currentItemURL];
				[self addURLs: @[self->_currentItemURL]];
			}
			
			AVURLAsset *currentAsset = (AVURLAsset *) self.avPlayer.currentItem.asset;
			if ([currentAsset respondsToSelector:@selector(URL)])
			{
				[self.window setRepresentedURL: currentAsset.URL];
				[self.window setTitleWithRepresentedFilename:currentAsset.URL.path];
				
				[self.avPlayerView flashChapterNumber: 0 chapterTitle: [NSFileManager.defaultManager displayNameAtPath: currentAsset.URL.path]];
				
				self->_currentItemURL = currentAsset.URL;
			}
			else
			{
				self->_currentItemURL = nil;
			}
			
			NSRect windowFrame = [self.window contentRectForFrameRect: self.window.frame];
			
			AVAssetTrack *videoTrack = [currentAsset tracksWithMediaType: AVMediaTypeVideo].firstObject;
			if( videoTrack )
			{
				[self.window setContentAspectRatio: NSZeroSize];
				
				NSRect assetBox = { NSZeroPoint, CGSizeApplyAffineTransform(videoTrack.naturalSize, videoTrack.preferredTransform) };
				
				CGFloat scaleFactor = windowFrame.size.height / assetBox.size.height;
				
				// Ensure height stays identical:
				assetBox.size.height *= scaleFactor;
				assetBox.size.width *= scaleFactor;
				
				// Ensure we resize relative to pinned corner:
				if( self->_pinRightNotLeft )
				{
					assetBox.origin.x = NSMaxX(windowFrame) - assetBox.size.width;
				}
				else
				{
					assetBox.origin.x = windowFrame.origin.x;
				}
				
				if( self->_pinBottomNotTop )
				{
					assetBox.origin.y = windowFrame.origin.y;
				}
				else
				{
					assetBox.origin.y = NSMaxY(windowFrame) - assetBox.size.height;
				}
				
				[self.window setFrame: [self.window frameRectForContentRect: assetBox] display: YES];
				
				[self.window setContentAspectRatio: assetBox.size];
			}
		});
	}
	else
	{
		[super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
	}
}


-(void) flashPlaybackProgressIndicator
{
	AVURLAsset *currentAsset = (AVURLAsset *) self.avPlayer.currentItem.asset;
	if ([currentAsset respondsToSelector:@selector(URL)])
	{
		[self.avPlayerView flashChapterNumber: 0 chapterTitle: [NSFileManager.defaultManager displayNameAtPath: currentAsset.URL.path]];
	}
}


-(void) flashVolumeProgressIndicator
{
	self.volumeProgressIndicator.doubleValue = self.avPlayer.volume;
	
	if( self.volumeProgressIndicator.alphaValue < 0.1 )
	{
		[CATransaction begin];
		[CATransaction setAnimationDuration:0.2];
		[CATransaction setCompletionBlock:^{
			[self performSelector: @selector(hideVolumeProgressIndicator) withObject: nil afterDelay: 0.5];
		}];
		self.volumeProgressIndicator.animator.alphaValue = 1.0;
		[CATransaction commit];
	}
	else
	{
		[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(hideVolumeProgressIndicator) object:nil];
		
		[self performSelector: @selector(hideVolumeProgressIndicator) withObject: nil afterDelay: 0.5];
	}
}


-(void) hideVolumeProgressIndicator
{
	[CATransaction begin];
	[CATransaction setAnimationDuration:0.2];
	self.volumeProgressIndicator.animator.alphaValue = 0.0;
	[CATransaction commit];
}


-(IBAction) advanceToNextItem: (nullable id)sender
{
	[self.avPlayer advanceToNextItem];
	[self.avPlayer play];
}


-(IBAction) advanceToPreviousItem: (nullable id)sender
{
	AVPlayerItem *currentItem = self.avPlayer.currentItem;
	AVPlayerItem *lastItem = self.avPlayer.items.lastObject;
	[self.avPlayer removeItem: lastItem];
	[self.avPlayer insertItem: lastItem afterItem: currentItem];
	[self.avPlayer advanceToNextItem];
	[self.avPlayer insertItem: currentItem afterItem: lastItem];

	_currentItemURL = nil;
}


-(IBAction) skipForward: (nullable id)sender
{
	CMTime desiredTime = CMTimeAdd(self.avPlayer.currentTime, CMTimeMakeWithSeconds(10.0, 90000));
	CMTime duration = self.avPlayer.currentItem.duration;
	if( CMTimeCompare(desiredTime, duration) == -1 )
	{
		[self.avPlayer seekToTime:desiredTime];
		
		[self flashPlaybackProgressIndicator];
	}
	else
	{
		[self advanceToNextItem: sender];
	}
}


-(IBAction) skipBackward: (nullable id)sender
{
	CMTime desiredTime = CMTimeAdd(self.avPlayer.currentTime, CMTimeMakeWithSeconds(-10.0, 90000));
	CMTime duration = self.avPlayer.currentItem.duration;
	if( CMTimeCompare(desiredTime, duration) == 1 )
	{
		[self.avPlayer seekToTime:desiredTime];
		[self flashPlaybackProgressIndicator];
	}
	else
	{
		[self advanceToPreviousItem: sender];
	}
}


-(IBAction) deleteCurrentItem: (nullable id)sender
{
	_currentItemURL = nil;
	AVURLAsset *currentAsset = (AVURLAsset *) self.avPlayer.currentItem.asset;
	if ([currentAsset respondsToSelector:@selector(URL)])
	{
		[self.playbackURLs removeObject:currentAsset.URL];
	}

	[self.avPlayer advanceToNextItem];
}


-(IBAction) increaseVolume: (nullable id)sender
{
	float volume = self.avPlayer.volume;
	volume = fmin(volume + 0.1, 1.0);
	self.avPlayer.volume = volume;
	
	[self flashVolumeProgressIndicator];
}


-(IBAction) decreaseVolume: (nullable id)sender
{
	float volume = self.avPlayer.volume;
	volume = fmax(volume - 0.1, 0.0);
	self.avPlayer.volume = volume;
	
	[self flashVolumeProgressIndicator];
}

@end
